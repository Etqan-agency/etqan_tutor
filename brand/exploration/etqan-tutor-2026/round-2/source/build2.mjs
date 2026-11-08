// Round 2 builder: same outline pipeline as build.mjs (HarfBuzz → paths), extended with
// wide lockup marks, extruded text, custom letters (qalam Q, swash q) and the Ruqaa seal.
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { concepts2, makeSymbols, makeMarks, wordmarks2 } from "./concepts2.mjs";

const require = createRequire(import.meta.url);
const hb = await require("harfbuzzjs");
const OUT = process.argv[2];
const here = path.dirname(new URL(import.meta.url).pathname);
const r2 = (n) => Math.round(n * 100) / 100;

const fonts = {};
for (const f of fs.readdirSync(path.join(here, "fonts"))) {
  const face = hb.createFace(hb.createBlob(fs.readFileSync(path.join(here, "fonts", f))), 0);
  fonts[f.replace(".ttf", "")] = { font: hb.createFont(face), upem: face.upem };
}

function place(d, ox, oy, k) {
  return d.replace(/([MLQCZ])([^MLQCZ]*)/g, (_, c, body) => {
    const n = body.trim() ? body.trim().split(/[ ,]+/).map(Number) : [];
    const o = [];
    for (let i = 0; i < n.length; i += 2) o.push(`${r2(ox + n[i] * k)} ${r2(oy - n[i + 1] * k)}`);
    return c + o.join(" ");
  });
}
const shift = (d, dx, dy) => d.replace(/([MLQC])([^MLQCZ]*)/g, (_, c, body) => {
  const n = body.trim().split(/[ ,]+/).map(Number), o = [];
  for (let i = 0; i < n.length; i += 2) o.push(`${r2(n[i] + dx)} ${r2(n[i + 1] + dy)}`);
  return c + o.join(" ");
});
function points(d) {
  const n = (d.match(/-?\d+(\.\d+)?/g) || []).map(Number), pts = [];
  for (let i = 0; i + 1 < n.length; i += 2) pts.push([n[i], n[i + 1]]);
  return pts;
}
function bbox(d) {
  const pts = points(d);
  const xs = pts.map((q) => q[0]), ys = pts.map((q) => q[1]);
  return { x0: Math.min(...xs), x1: Math.max(...xs), y0: Math.min(...ys), y1: Math.max(...ys) };
}

function shapeRun(run) {
  const { font, upem } = fonts[run.f];
  const buf = hb.createBuffer();
  buf.addText(run.t);
  buf.guessSegmentProperties();
  hb.shape(font, buf);
  const glyphs = buf.json();
  buf.destroy();
  const k = run.s / upem, ls = (run.ls || 0) * run.s;
  let x = 0, d = "";
  glyphs.forEach((g, i) => {
    d += place(font.glyphToPath(g.g), x + g.dx * k, -g.dy * k, k);
    x += g.ax * k + (i < glyphs.length - 1 ? ls : 0);
  });
  const b = d ? bbox(d) : { x0: 0, x1: 0, y0: 0, y1: 0 };
  return { d, width: x, top: Math.min(0, b.y0), bottom: Math.max(0, b.y1), b };
}
// A glyph run with its bbox centre, for centring inside symbols.
function glyph(f, t, s) {
  const r = shapeRun({ f, t, s });
  return { d: r.d, cx: (r.b.x0 + r.b.x1) / 2, cy: (r.b.y0 + r.b.y1) / 2, b: r.b };
}

// Qalam tail: a parallelogram with flat horizontal cuts, like a reed-pen stroke.
function qalamTail(b, s, fill) {
  const w = b.x1 - b.x0, t = 0.085 * s;
  // Starts under the bowl's centre and sweeps right along the baseline (a flat Q tail, not a handle).
  const sx = b.x0 + 0.42 * w, sy = b.y1 - 0.13 * (b.y1 - b.y0);
  const ex = b.x1 + 0.34 * w, ey = b.y1 + 0.09 * s;
  // Vertical thickness t, nib-cut ends (thick start, tapering slightly to the exit).
  return `<path fill="${fill}" d="M${r2(sx)} ${r2(sy - t)}L${r2(ex)} ${r2(ey - t * 0.55)}L${r2(ex - t * 0.5)} ${r2(ey + t * 0.45)}L${r2(sx - t * 0.4)} ${r2(sy + t)}Z"/>`;
}

const h = {
  glyph, shift,
  qalamO(p, cx, cy, s) {
    const o = glyph("unbounded-800", "O", s * 0.92);
    const dx = cx - o.cx - s * 0.05, dy = cy - o.cy - s * 0.04;
    const d = shift(o.d, dx, dy);
    return `<path fill="${p.primary}" d="${d}"/>` + qalamTail(bbox(d), s * 0.92, p.flat ? p.primary : p.accent);
  },
  seal(p) {
    const band = `<path fill="${p.primary}" fill-rule="evenodd" d="M24 1.5a22.5 22.5 0 1 0 0.001 0ZM24 9a15 15 0 1 1-0.001 0Z"/>`;
    const ring = `<circle cx="24" cy="24" r="13" fill="none" stroke="${p.accent}" stroke-width="0.9"/>`;
    const w = glyph("ruqaa-700", "إتقان", 12.5);
    const word = `<path fill="${p.primary}" d="${shift(w.d, 24 - w.cx, 24.6 - w.cy)}"/>`;
    // Ring text: glyph by glyph around the band, baseline pointing outward.
    const text = "ETQAN TUTOR", text2 = "ACADEMY PLATFORM";
    const s = 4.3, rB = 17.35;
    const segs = [{ t: text }, { mark: 1 }, { t: text2 }, { mark: 1 }];
    const { font, upem } = fonts["readex-600"], k = s / upem;
    const items = [];
    for (const sg of segs) {
      if (sg.mark) { items.push({ mark: true, adv: s * 1.6 }); continue; }
      const buf = hb.createBuffer(); buf.addText(sg.t); buf.guessSegmentProperties(); hb.shape(font, buf);
      for (const g of buf.json()) items.push({ g: g.g, adv: g.ax * k });
      buf.destroy();
    }
    const natural = items.reduce((a, i) => a + i.adv, 0), circ = 2 * Math.PI * rB;
    const extra = (circ - natural) / items.length;
    let acc = 0, out = "";
    for (const it of items) {
      const mid = acc + it.adv / 2 + extra / 2, deg = (mid / circ) * 360;
      if (it.mark) out += `<path fill="${p.flat ? p.knock : p.accent}" transform="rotate(${r2(deg)} 24 24)" d="M24 ${r2(24 - rB - 1.55)}l1.1 1.1l-1.1 1.1l-1.1-1.1Z"/>`;
      else {
        const gd = place(font.glyphToPath(it.g), -it.adv / 2, 0, k);
        if (gd) out += `<path fill="${p.knock}" transform="rotate(${r2(deg)} 24 24) translate(24 ${r2(24 - rB)})" d="${gd}"/>`;
      }
      acc += it.adv + extra;
    }
    return band + ring + word + out;
  },
};

const symbols = makeSymbols(h), marks = makeMarks(h);

function layoutLine(runs, p) {
  let x = 0, top = 0, bottom = 0;
  const back = [], parts = [];
  for (const r of runs) {
    if (r.space) { x += r.space; continue; }
    if (r.custom === "qalamO") {
      const sh = shapeRun({ ...r, t: "O" });
      const d = shift(sh.d, x, 0);
      parts.push(`<path fill="${p[r.role]}" d="${d}"/>`, qalamTail(bbox(d), r.s, p.flat ? p[r.role] : p.accent));
      top = Math.min(top, sh.top); bottom = Math.max(bottom, 0.1 * r.s);
      x += sh.width + 0.03 * r.s;
      continue;
    }
    if (r.custom === "swashQ") {
      const sh = shapeRun({ ...r, t: "q" });
      const d = shift(sh.d, x, 0);
      const desc = points(d).filter(([, y]) => y > 0.05 * r.s);
      const dx1 = Math.max(...desc.map((q) => q[0])), dx0 = Math.min(...desc.map((q) => q[0]));
      const db = Math.max(...desc.map((q) => q[1]));
      const bh = (dx1 - dx0) * 0.78;
      back.push(`<rect x="0" y="${r2(db - bh)}" width="${r2(dx1)}" height="${r2(bh)}" rx="${r2(bh / 2)}" fill="${p.flat ? p[r.role] : p.accent}"/>`);
      parts.push(`<path fill="${p[r.role]}" d="${d}"/>`);
      top = Math.min(top, sh.top); bottom = Math.max(bottom, sh.bottom);
      x += sh.width;
      continue;
    }
    const sh = shapeRun(r);
    if (r.extrude && !p.flat) parts.push(`<path fill="${p.shade}" d="${shift(sh.d, x, r.extrude)}"/>`);
    parts.push(`<path fill="${p[r.role]}" d="${shift(sh.d, x, 0)}"/>`);
    top = Math.min(top, sh.top);
    bottom = Math.max(bottom, sh.bottom + (r.extrude && !p.flat ? r.extrude : 0));
    x += sh.width;
  }
  return { parts: [...back, ...parts], width: x, top, bottom };
}

function textBlock(id, p) {
  const spec = wordmarks2[id];
  const lines = spec.lines.map((l) => layoutLine(l, p));
  const step = (i) => (i ? lines[i - 1].bottom + spec.gap : 0) - lines[i].top;
  const height = lines.reduce((acc, l, i) => acc + step(i), 0);
  const width = Math.max(...lines.map((l) => l.width));
  const descent = lines[lines.length - 1].bottom;
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

const palettes = {
  light: { side: "#07503A", primary: "#146B50", accent: "#B79A58", ink: "#202522", sub: "#8D6F27", knock: "#FAF9F5", shade: "#07503A", hi: "#4FA082", hi2: "#4FA082", accentHi: "#D9C69D", accentLo: "#8D6F27" },
  dark: { side: "#146B50", primary: "#4FA082", accent: "#C7AD74", ink: "#FAF9F5", sub: "#D9C69D", knock: "#022217", shade: "#146B50", hi: "#76B9A0", hi2: "#C2E3D4", accentHi: "#E6D9BC", accentLo: "#8D6F27" },
  emerald: { side: "#C2E3D4", primary: "#FAF9F5", accent: "#D9C69D", ink: "#FAF9F5", sub: "#E6D9BC", knock: "#146B50", shade: "#07503A", hi: "#FFFFFF", hi2: "#C2E3D4", accentHi: "#F5EEDF", accentLo: "#B79A58" },
  mono: { side: "#202522", primary: "#202522", accent: "#202522", ink: "#202522", sub: "#202522", knock: "#FAF9F5", shade: "#202522", hi: "#202522", hi2: "#202522", accentHi: "#202522", accentLo: "#202522", flat: true },
  reversed: { side: "#FAF9F5", primary: "#FAF9F5", accent: "#FAF9F5", ink: "#FAF9F5", sub: "#FAF9F5", knock: "#146B50", shade: "#FAF9F5", hi: "#FAF9F5", hi2: "#FAF9F5", accentHi: "#FAF9F5", accentLo: "#FAF9F5", flat: true },
};
const onTile = { ...palettes.emerald };

const svg = (w, hh, body, label) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${r2(w)} ${r2(hh)}" width="${r2(w)}" height="${r2(hh)}" role="img" aria-label="${label}">${body}</svg>`;

function favicon(c) {
  if (c.id === "P1") return svg(48, 48, `<g transform="translate(24 24) scale(1.16) translate(-24 -24.5)">${symbols.P1(palettes.light, "fav")}</g>`, "Etqan Tutor");
  if (c.id === "K2") {
    const q = glyph("ruqaa-700", "ق", 30);
    return svg(48, 48, `<circle cx="24" cy="24" r="24" fill="#146B50"/><circle cx="24" cy="24" r="20.5" fill="none" stroke="#D9C69D" stroke-width="1.6"/><path fill="#FAF9F5" d="${shift(q.d, 24 - q.cx, 24 - q.cy)}"/>`, "Etqan Tutor");
  }
  return svg(48, 48, `<rect width="48" height="48" rx="11" fill="#146B50"/><g transform="translate(24 24) scale(0.8) translate(-24 -24)">${symbols[c.id](onTile, "fav")}</g>`, "Etqan Tutor");
}

function variants(c) {
  const out = {};
  for (const [pn, p] of Object.entries(palettes)) {
    const u = `-${c.id}-${pn}`;
    const sym = symbols[c.id](p, u);
    const mk = marks[c.id] ? marks[c.id](p, u) : { w: 48, body: sym };
    const tb = textBlock(c.id, p);
    const gapH = marks[c.id] ? 18 : 14, gapV = 13;
    const hw = mk.w + gapH + tb.width, hh = Math.max(48, 24 + tb.height / 2 + tb.descent);
    const horizontal = svg(hw, hh, `<g>${mk.body}</g>${tb.render(mk.w + gapH, 24 - tb.height / 2, "left")}`, "Etqan Tutor");
    const sw = Math.max(mk.w, tb.width), sh = 48 + gapV + tb.height + tb.descent;
    const stacked = svg(sw, sh, `<g transform="translate(${r2((sw - mk.w) / 2)} 0)">${mk.body}</g>${tb.render((sw - tb.width) / 2, 48 + gapV, "center")}`, "Etqan Tutor");
    const wordmark = svg(tb.width, tb.height + tb.descent, tb.render(0, 0, "left"), "Etqan Tutor");
    out[pn] = { symbol: svg(48, 48, sym, "Etqan Tutor mark"), horizontal, stacked, wordmark };
  }
  out.favicon = favicon(c);
  return out;
}

const data = {};
for (const c of concepts2) {
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
fs.writeFileSync(path.join(here, "logos2.json"), JSON.stringify({ concepts: concepts2, svgs: data }));
console.log("ok", Object.keys(data).length);
