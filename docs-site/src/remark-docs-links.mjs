import { readdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const GH = "https://github.com/Etqan-agency";
const SUBMODULES = new Set(["backend", "dashboard", "marketing", "website", "infra", "tokens"]);
const IN_SITE = new Set(["features", "guide"]);
const META = new Set(["superpowers", "kaleem-archive"]);
const DOCS_DIR = fileURLToPath(new URL("../../docs", import.meta.url));

/** Page ids (relative to docs/, no .md) of everything the site serves. */
export function scanKnownIds(docsDir = DOCS_DIR) {
	const ids = new Set();
	const walk = (dir, rel) => {
		for (const e of readdirSync(dir, { withFileTypes: true })) {
			if (e.isDirectory()) walk(path.join(dir, e.name), `${rel}${e.name}/`);
			else if (e.name.endsWith(".md")) ids.add(`${rel}${e.name.slice(0, -3)}`);
		}
	};
	for (const top of IN_SITE) walk(path.join(docsDir, top), `${top}/`);
	return ids;
}

/** Route for a page id; README is the folder index. */
export function routeFor(id) {
	const parts = id.split("/");
	if (parts[parts.length - 1].toLowerCase() === "readme") parts.pop();
	return `/${parts.join("/")}/`;
}

export function rewriteHref(href, fromId, knownIds) {
	if (/^(https?:|mailto:|tel:)/i.test(href) || href.startsWith("#") || href.startsWith("//")) return href;
	const m = href.match(/^([^#?]*)([?#].*)?$/);
	const target = m[1];
	const suffix = m[2] ?? "";
	if (!target) return href;
	const resolved = path.posix.normalize(path.posix.join(path.posix.dirname(fromId), target));
	const [first, ...rest] = resolved.split("/");
	if (META.has(first)) return `${GH}/etqan_tutor/blob/master/docs/${resolved}${suffix}`;
	if (first === ".." && SUBMODULES.has(rest[0])) {
		return `${GH}/etqan_tutor_${rest[0]}/blob/main/${rest.slice(1).join("/")}${suffix}`;
	}
	if (IN_SITE.has(first) && resolved.endsWith(".md")) {
		const id = resolved.slice(0, -3);
		const exists = !knownIds || [...knownIds].some((k) => k.toLowerCase() === id.toLowerCase());
		if (!exists) throw new Error(`broken doc link ${href} in ${fromId}`);
		return routeFor(id) + suffix;
	}
	throw new Error(`broken doc link ${href} in ${fromId}`);
}

function visit(node, fn) {
	if (node.type === "link") fn(node);
	for (const c of node.children ?? []) visit(c, fn);
}

export default function remarkDocsLinks(options = {}) {
	const docsDir = options.docsDir ?? DOCS_DIR;
	const knownIds = options.knownIds ?? scanKnownIds(docsDir);
	return (tree, file) => {
		const filePath = file.path ?? "";
		const fromId = path.relative(docsDir, filePath).split(path.sep).join("/").replace(/\.md$/, "");
		visit(tree, (node) => {
			node.url = rewriteHref(node.url, fromId, knownIds);
		});
	};
}
