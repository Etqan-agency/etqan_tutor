#!/usr/bin/env node
/**
 * G3 — the `@etqan/tokens` pin must agree with the `tokens` submodule.
 *
 * THESE ARE INDEPENDENT, and that is the trap. pnpm installs the package from
 * its git URL at the ref in package.json; the submodule checkout exists only so
 * the source is readable and the contrast gate has data to read. Bumping one
 * without the other produces a tree that looks coherent, reviews clean, and
 * installs the OLD palette.
 *
 * That is not hypothetical. It is finding T5 in the design-system v2 audit: the
 * package said 0.1.0 while the consumed tag was v0.1.1. And it recurred in a
 * different form on 2026-09-12, when the LOCAL dev container held v0.1.0 for
 * days after the v2 swap -- every local visual check was against the old palette
 * and nothing said so, because nothing compared the two.
 *
 * Three things are asserted:
 *   1. Every consumer pins the same ref (a half-done bump).
 *   2. That ref is a real tag in the submodule, and the submodule's committed
 *      gitlink is exactly that tag's commit (the T5 drift).
 *   3. No `link:` override is committed -- the local-iteration workaround that
 *      hot-reloads token edits. It resolves to no tag at all, so a tree
 *      carrying one installs whatever happens to be on disk.
 */
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const CONSUMERS = ["dashboard/package.json"];
const fail = (msg) => {
	console.error(`\n${msg}\n`);
	process.exit(1);
};

const git = (args) =>
	execFileSync("git", args, { encoding: "utf8" }).trim();

const pins = new Map();
for (const file of CONSUMERS) {
	const pkg = JSON.parse(readFileSync(file, "utf8"));
	const ref = { ...pkg.dependencies, ...pkg.devDependencies }["@etqan/tokens"];
	if (!ref) fail(`${file} does not depend on @etqan/tokens at all.`);
	if (ref.startsWith("link:") || ref.startsWith("file:")) {
		fail(
			`${file} pins @etqan/tokens to "${ref}".\n` +
				`That is the local-iteration override and must never be committed: it\n` +
				`resolves to no tag, so CI and the Docker build install whatever is on\n` +
				`disk. Re-pin to a tag before merging.`,
		);
	}
	if (JSON.stringify(pkg.pnpm ?? {}).includes("@etqan/tokens")) {
		fail(`${file} carries a pnpm override for @etqan/tokens. Remove it.`);
	}
	pins.set(file, ref);
}

const refs = new Set(pins.values());
if (refs.size !== 1) {
	fail(
		`Consumers disagree on the @etqan/tokens ref — a half-done bump:\n` +
			[...pins].map(([f, r]) => `  ${f}  ${r}`).join("\n") +
			`\nBoth surfaces share one palette; one of them is rendering a different one.`,
	);
}

const ref = [...refs][0];
const tag = ref.split("#")[1];
if (!tag) fail(`@etqan/tokens is pinned to "${ref}" with no #tag.`);

let tagged;
try {
	tagged = git(["-C", "tokens", "rev-parse", `${tag}^{commit}`]);
} catch {
	fail(
		`The consumers pin @etqan/tokens#${tag}, but that tag does not exist in\n` +
			`the tokens submodule. Push the tag, or fix the pin.`,
	);
}

// Read the INDEX, not HEAD. In CI the two are identical (the runner checks out
// the commit), but locally HEAD is the PREVIOUS commit — so a HEAD-based check
// fails on a correctly staged pointer bump and passes on an unstaged one, which
// is exactly backwards for a pre-commit check. It caught its own author this way
// on the v0.2.2 bump.
const gitlink = git(["ls-files", "-s", "tokens"]).split(/\s+/)[1];
if (gitlink !== tagged) {
	fail(
		`The tokens submodule pointer and the package pin disagree.\n\n` +
			`  package.json pins  ${tag}  -> ${tagged.slice(0, 10)}\n` +
			`  submodule pointer        -> ${gitlink.slice(0, 10)}\n\n` +
			`pnpm installs from the pin, so the palette that SHIPS is ${tag}, while the\n` +
			`source this repo shows — and the contrast gate reads — is a different\n` +
			`commit. Bump both, or neither.`,
	);
}

console.log(`token pin check: ${tag} -> ${tagged.slice(0, 10)}, submodule agrees`);
