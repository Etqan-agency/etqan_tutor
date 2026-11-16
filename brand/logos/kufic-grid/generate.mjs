// Etqan Tutor logo: Kufic Grid (concept 10, "Focus"), adopted 2026-11-16.
// إتقان in square Kufic on a 1-unit grid; the gold squares are the dots and the hamza.
// Run from the repo root:  node brand/logos/kufic-grid/generate.mjs
// Writes the masters into brand/, copies the site files into website/, and
// renders apple-touch-icon.png with the website's sharp.
import { mkdirSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const site = join(root, "website/etqan_tutor_official_site");

// ── The mark: columns 1–15, rows 1–9 (one unit = one grid cell) ──
const LETTERS = [
	"M15 1h1v7h-1Z", // ا of إ
	"M5 1h1v6h1v-2h3v2h3v-1h1v2h-9ZM8 6v1h1v-1Z", // ا + ق loop + ت tooth on one baseline
	"M1 5h1v2h1v-2h1v3h-3Z", // ن
].join("");
const DOTS = [[2, 3], [7, 3], [9, 3], [11, 4], [13, 4]] // ن, ق ق, ت ت
	.map(([x, y]) => `M${x} ${y}h1v1h-1Z`)
	.join("") + "M15.2 9.2h.6v.6h-.6Z"; // hamza below the alif

const TREATMENTS = {
	light: { ink: "#146B50", gold: "#B79A58" },
	dark: { ink: "#4FA082", gold: "#C7AD74", bg: "#022217" },
	emerald: { ink: "#FAF9F5", gold: "#D9C69D", bg: "#146B50" },
	mono: { ink: "#202522", gold: "#202522" },
	reversed: { ink: "#FAF9F5", gold: "#FAF9F5", bg: "#202522" },
};

function symbol({ ink, gold, bg }, pad = 0) {
	const [x, y, w, h] = [1 - pad, 1 - pad, 15 + 2 * pad, 9 + 2 * pad];
	return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${x} ${y} ${w} ${h}" width="${w * 8}" height="${h * 8}" role="img" aria-label="إتقان Etqan Tutor">`
		+ (bg ? `<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${bg}"/>` : "")
		+ `<path fill="${ink}" fill-rule="evenodd" d="${LETTERS}"/><path fill="${gold}" d="${DOTS}"/></svg>\n`;
}

// ── The app icon / favicon: the ق alone on an emerald tile (cell = 6 of 48) ──
const appIcon = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" width="48" height="48" role="img" aria-label="Etqan Tutor">`
	+ `<rect width="48" height="48" rx="11" fill="#146B50"/>`
	+ `<path fill="#FAF9F5" fill-rule="evenodd" d="M15 20h18v18h-18ZM21 26v6h6v-6Z"/>`
	+ `<path fill="#D9C69D" d="M15 8h6v6h-6ZM27 8h6v6h-6Z"/></svg>\n`;

function write(path, text) {
	mkdirSync(dirname(path), { recursive: true });
	writeFileSync(path, text);
	console.log("wrote", path.slice(root.length + 1));
}

for (const [name, t] of Object.entries(TREATMENTS)) {
	write(join(root, `brand/logos/etqan-tutor-kufic-grid-symbol-${name}.svg`), symbol(t, t.bg ? 1 : 0));
}
write(join(root, "brand/logos/etqan-tutor-kufic-grid-app-icon.svg"), appIcon);
write(join(root, "brand/favicons-app-icons/favicon.svg"), appIcon);

// The site uses the bare mark (no background) on light and on dark grounds.
write(join(site, "public/brand/etqan-kufic-light.svg"), symbol(TREATMENTS.light));
write(join(site, "public/brand/etqan-kufic-dark.svg"), symbol({ ink: "#FAF9F5", gold: "#D9C69D" }));
write(join(site, "public/favicon.svg"), appIcon);

const sharp = createRequire(createRequire(join(site, "package.json")).resolve("astro"))("sharp");
const png = await sharp(Buffer.from(appIcon), { density: 384 }).resize(180, 180).png().toBuffer();
for (const p of ["brand/favicons-app-icons/apple-touch-icon.png", "website/etqan_tutor_official_site/public/apple-touch-icon.png"]) {
	writeFileSync(join(root, p), png);
	console.log("wrote", p);
}
