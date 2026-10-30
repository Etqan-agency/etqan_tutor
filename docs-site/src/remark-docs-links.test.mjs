import { expect, test } from "vitest";
import plugin, { rewriteHref } from "./remark-docs-links.mjs";

const GH = "https://github.com/Etqan-agency";

test.each([
	["online-payments.md", "features/sessions", "/features/online-payments/"],
	["sessions.md#postponement", "features/billing", "/features/sessions/#postponement"],
	["../guide/testing.md", "features/sessions", "/guide/testing/"],
	["README.md", "features/sessions", "/features/"],
	["runbooks/deploy.md", "guide/README", "/guide/runbooks/deploy/"],
	["../superpowers/specs/a.md", "features/ai", `${GH}/etqan_tutor/blob/master/docs/superpowers/specs/a.md`],
	["../kaleem-archive/x.md", "features/ai", `${GH}/etqan_tutor/blob/master/docs/kaleem-archive/x.md`],
	["../../backend/etqan/platform/features.py", "features/feature-toggles",
		`${GH}/etqan_tutor_backend/blob/main/etqan/platform/features.py`],
	["https://example.com/x", "features/ai", "https://example.com/x"],
	["mailto:a@b.c", "features/ai", "mailto:a@b.c"],
	["#concepts", "features/ai", "#concepts"],
])("%s from %s", (href, from, want) => expect(rewriteHref(href, from)).toBe(want));

test("broken in-site link fails the build", () => {
	expect(() => rewriteHref("nope.md", "features/ai", new Set(["features/ai"]))).toThrow(
		/broken doc link nope.md in features\/ai/,
	);
});

test("plugin rewrites link nodes and throws on unknown targets", () => {
	const known = new Set(["features/ai", "features/sessions"]);
	const tree = { type: "root", children: [{ type: "link", url: "sessions.md" }] };
	plugin({ knownIds: known, docsDir: "/x/docs" })(tree, { path: "/x/docs/features/ai.md" });
	expect(tree.children[0].url).toBe("/features/sessions/");
	const bad = { type: "root", children: [{ type: "link", url: "zzz.md" }] };
	expect(() => plugin({ knownIds: known, docsDir: "/x/docs" })(bad, { path: "/x/docs/features/ai.md" })).toThrow(/broken doc link/);
});
