// Builds every SVG variant for the 8 concepts with the wordmarks converted to
// outlines (HarfBuzz shaping, so Arabic joins correctly), then writes the asset
// tree and a logos.json the exploration page inlines.
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { concepts, symbols, wordmarks } from "./concepts.mjs";

const require = createRequire(import.meta.url);
const hb = await require("harfbuzzjs");
const OUT = process.argv[2];
const here = path.dirname(new URL(import.meta.url).pathname);

const fonts = {};
for (const f of fs.readdirSync(path.join(here, "fonts"))) {
  const blob = hb.createBlob(fs.readFileSync(path.join(here, "fonts", f)));
  const face = hb.createFace(blob, 0);
  fonts[f.replace(".ttf", "")] = { font: hb.createFont(face), upem: face.upem };
}

const r2 = (n) => Math.round(n * 100) / 100;

// Transform an absolute HarfBuzz path (font units, y-up) to SVG space.
function place(d, ox, oy, k) {
  const out = [];
  let minY = Infinity, maxY = -Infinity, minX = Infinity, maxX = -Infinity;
  for (const m of d.matchAll(/([MLQCZ])([^MLQCZ]*)/g)) {
    const nums = m[2].trim() ? m[2].trim().split(/[ ,]+/).map(Number) : [];
    const pts = [];
    for (let i = 0; i < nums.length; i += 2) {
      const x = ox + nums[i] * k, y = oy - nums[i + 1] * k;
      minX = Math.min(minX, x); maxX = Math.max(maxX, x);
      minY = Math.min(minY, y); maxY = Math.max(maxY, y);
      pts.push(`${r2(x)} ${r2(y)}`);
    }
    out.push(m[1] + pts.join(" "));
  }
  return { d: out.join(""), minX, maxX, minY, maxY };
}

// Shape one run at baseline y=0 starting at x=0.
function shapeRun(run) {
  const { font, upem } = fonts[run.f];
  const buf = hb.createBuffer();
  buf.addText(run.t);
  buf.guessSegmentProperties();
  hb.shape(font, buf);
  const glyphs = buf.json();
  buf.destroy();
  const k = run.s / upem, ls = (run.ls || 0) * run.s;
  let x = 0, d = "", top = 0, bottom = 0;
  glyphs.forEach((g, i) => {
    const p = place(font.glyphToPath(g.g), x + g.dx * k, -g.dy * k, k);
    d += p.d;
    if (p.d) { top = Math.min(top, p.minY); bottom = Math.max(bottom, p.maxY); }
    x += g.ax * k + (i < glyphs.length - 1 ? ls : 0);
  });
  return { d, width: x, top, bottom };
}

function shiftPath(d, dx, dy) {
  return d.replace(/([MLQC])([^MLQCZ]*)/g, (_, c, body) => {
    const n = body.trim().split(/[ ,]+/).map(Number);
    const o = [];
    for (let i = 0; i < n.length; i += 2) o.push(`${r2(n[i] + dx)} ${r2(n[i + 1] + dy)}`);
    return c + o.join(" ");
  });
}

// Lay out one line of runs; returns parts positioned from x=0, baseline 0.
function layoutLine(runs, p) {
  const ref = runs.find((r) => r.t);
  const s = ref.s;
  let x = 0, top = 0, bottom = 0;
  const parts = [];
  for (const r of runs) {
    if (r.space) { x += r.space; continue; }
    if (r.mark === "rhombus") {
      const h = s * 0.12, gap = s * 0.16, cy = -s * 0.27;
      x += gap + h;
      parts.push(`<path fill="${p.accent}" d="M${r2(x)} ${r2(cy - h)}L${r2(x + h)} ${r2(cy)}L${r2(x)} ${r2(cy + h)}L${r2(x - h)} ${r2(cy)}Z"/>`);
      x += h + gap;
      continue;
    }
    if (r.mark === "bar") {
      const gap = s * 0.32, w = Math.max(1.4, s * 0.06);
      x += gap;
      parts.push(`<rect x="${r2(x)}" y="${r2(-s * 0.74)}" width="${r2(w)}" height="${r2(s * 0.92)}" rx="${r2(w / 2)}" fill="${p.accent}"/>`);
      x += w + gap;
      continue;
    }
    const sh = shapeRun(r);
    parts.push(`<path fill="${p[r.role]}" d="${shiftPath(sh.d, x, 0)}"/>`);
    top = Math.min(top, sh.top);
    bottom = Math.max(bottom, sh.bottom);
    x += sh.width;
  }
  return { parts, width: x, top, bottom };
}

// Text block: lines stacked, returns {svg(x,y,align), width, height} where y is block top.
function textBlock(id, p) {
  const spec = wordmarks[id];
  const lines = spec.lines.map((l) => layoutLine(l, p));
  const step = (i) => (i ? lines[i - 1].bottom + spec.gap : 0) - lines[i].top;
  const height = lines.reduce((h, l, i) => h + step(i), 0);
  const descent = lines[lines.length - 1].bottom;
  const width = Math.max(...lines.map((l) => l.width));
  const render = (bx, by, align) => {
    let y = by, out = "";
    lines.forEach((l, i) => {
      y += step(i);
      const lx = align === "center" ? bx + (width - l.width) / 2 : bx;
      out += `<g transform="translate(${r2(lx)} ${r2(y)})">${l.parts.join("")}</g>`;
    });
    return out;
  };
  return { render, width, height, descent };
}

// B's symbol: the Fraunces "e" knocked out of an emerald tile.
symbols.B = (p) => {
  const e = shapeRun({ t: "e", f: "fraunces-600", s: 34 });
  const gx = 24 - e.width / 2, gy = 24 - (e.top + e.bottom) / 2;
  return `<rect x="4" y="4" width="40" height="40" rx="10" fill="${p.primary}"/>` +
    `<path fill="${p.knock}" d="${shiftPath(e.d, gx, gy)}"/>` +
    `<path fill="${p.accent}" d="M36 31.5L38.5 34L36 36.5L33.5 34Z"/>`;
};

const palettes = {
  light: { primary: "#146B50", accent: "#B79A58", ink: "#202522", sub: "#8D6F27", knock: "#FAF9F5" },
  dark: { primary: "#4FA082", accent: "#C7AD74", ink: "#FAF9F5", sub: "#D9C69D", knock: "#022217" },
  mono: { primary: "#202522", accent: "#202522", ink: "#202522", sub: "#202522", knock: "#FAF9F5" },
  emerald: { primary: "#FAF9F5", accent: "#D9C69D", ink: "#FAF9F5", sub: "#E6D9BC", knock: "#146B50" },
  reversed: { primary: "#FAF9F5", accent: "#FAF9F5", ink: "#FAF9F5", sub: "#FAF9F5", knock: "#146B50" },
};
const onTile = { primary: "#FAF9F5", accent: "#D9C69D", ink: "#FAF9F5", sub: "#FAF9F5", knock: "#146B50" };

const svg = (w, h, body, label) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${r2(w)} ${r2(h)}" width="${r2(w)}" height="${r2(h)}" role="img" aria-label="${label}">${body}</svg>`;

function variants(c) {
  const out = {};
  for (const [pn, p] of Object.entries(palettes)) {
    const sym = symbols[c.id](p);
    const tb = textBlock(c.id, p);
    const gapH = 13, gapV = 12;
    const hw = 48 + gapH + tb.width, hh = Math.max(48, 24 + tb.height / 2 + tb.descent);
    const horizontal = svg(hw, hh, `<g>${sym}</g>${tb.render(48 + gapH, 24 - tb.height / 2, "left")}`, "Etqan Tutor");
    const sw = Math.max(48, tb.width), sh = 48 + gapV + tb.height + tb.descent;
    const stacked = svg(sw, sh, `<g transform="translate(${r2((sw - 48) / 2)} 0)">${sym}</g>${tb.render((sw - tb.width) / 2, 48 + gapV, "center")}`, "Etqan Tutor");
    const wordmark = svg(tb.width, tb.height + tb.descent, tb.render(0, 0, "left"), "Etqan Tutor");
    out[pn] = { symbol: svg(48, 48, sym, "Etqan Tutor mark"), horizontal, stacked, wordmark };
  }
  // Favicon: B is already a tile; the rest sit on an emerald tile, scaled up a touch.
  out.favicon = c.id === "B"
    ? svg(48, 48, symbols.B({ ...palettes.light }).replace('x="4" y="4" width="40" height="40" rx="10"', 'x="0" y="0" width="48" height="48" rx="11"'), "Etqan Tutor")
    : svg(48, 48, `<rect width="48" height="48" rx="11" fill="#146B50"/><g transform="translate(24 24) scale(0.78) translate(-24 -24)">${symbols[c.id](onTile)}</g>`, "Etqan Tutor");
  return out;
}

const data = {};
for (const c of concepts) {
  const v = variants(c);
  data[c.id] = v;
  const dir = path.join(OUT, "assets", `concept-${c.id.toLowerCase()}`);
  fs.mkdirSync(dir, { recursive: true });
  const stem = `etqan-tutor-${c.id.toLowerCase()}-${c.key}`;
  for (const pn of Object.keys(palettes))
    for (const kind of ["symbol", "horizontal", "stacked", "wordmark"])
      fs.writeFileSync(path.join(dir, `${stem}-${kind}-${pn}.svg`), v[pn][kind] + "\n");
  fs.writeFileSync(path.join(dir, `${stem}-favicon.svg`), v.favicon + "\n");
}
fs.writeFileSync(path.join(here, "logos.json"), JSON.stringify({ concepts, svgs: data }));
console.log("ok", Object.keys(data).length, "concepts");
