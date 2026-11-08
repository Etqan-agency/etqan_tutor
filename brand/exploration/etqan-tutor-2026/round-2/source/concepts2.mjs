// Round 2: four styles × two concepts. Same emerald + gold, new type, new shapes.
// Symbols draw on a 48×48 grid. Helpers needing font outlines (glyph, glyphRun) are
// injected by build2.mjs. p = palette; u = unique id suffix for gradients.

const r2 = (n) => Math.round(n * 100) / 100;
const rh = (cx, cy, h) => `M${r2(cx)} ${r2(cy - h)}L${r2(cx + h)} ${r2(cy)}L${r2(cx)} ${r2(cy + h)}L${r2(cx - h)} ${r2(cy)}Z`;

// K1 — square Kufic إتقان on a 14×7 cell grid (visual order, left to right: ن ا ق ت إ).
const KUFIC_INK = [
  [0, 2], [0, 3], [0, 4], [1, 4], [2, 4], [2, 3], [2, 2],      // ن
  [4, 0], [4, 1], [4, 2], [4, 3], [4, 4],                      // ا
  [5, 4], [6, 4], [7, 4], [8, 4], [9, 4], [10, 4],             // baseline
  [5, 2], [6, 2], [7, 2], [5, 3], [7, 3],                      // ق loop
  [10, 2], [10, 3],                                            // ت tooth
  [13, 0], [13, 1], [13, 2], [13, 3], [13, 4],                 // إ
];
const KUFIC_GOLD = [[1, 0], [5, 0], [7, 0], [9, 0], [11, 0]];
const cells = (list, c, ox, oy, fill) =>
  `<path fill="${fill}" d="${list.map(([x, y]) => `M${r2(ox + x * c)} ${r2(oy + y * c)}h${r2(c)}v${r2(c)}h${r2(-c)}Z`).join("")}"/>`;
// Merge touching cells visually: draw slightly oversized so no hairline seams show.
const cellsSolid = (list, c, ox, oy, fill) =>
  `<path fill="${fill}" stroke="${fill}" stroke-width="0.35" stroke-linejoin="miter" d="${list.map(([x, y]) => `M${r2(ox + x * c)} ${r2(oy + y * c)}h${r2(c)}v${r2(c)}h${r2(-c)}Z`).join("")}"/>`;

// P2 — isometric cube faces.
function cube(x, y, a, faces, flat, knock) {
  const w = a * 0.866, h = a * 0.5;
  const P = (pts) => "M" + pts.map(([px, py]) => `${r2(px)} ${r2(py)}`).join("L") + "Z";
  const left = P([[x, y], [x - w, y - h], [x - w, y - h - a], [x, y - a]]);
  const right = P([[x, y], [x + w, y - h], [x + w, y - h - a], [x, y - a]]);
  const top = P([[x, y - a], [x - w, y - h - a], [x, y - 2 * h - a], [x + w, y - h - a]]);
  const st = flat ? ` stroke="${knock}" stroke-width="1.3" stroke-linejoin="round"` : "";
  return `<path fill="${faces[0]}"${st} d="${top}"/><path fill="${faces[1]}"${st} d="${left}"/><path fill="${faces[2]}"${st} d="${right}"/>`;
}

const sparkle = (cx, cy, r) =>
  `M${cx} ${cy - r}Q${cx} ${cy} ${cx + r} ${cy}Q${cx} ${cy} ${cx} ${cy + r}Q${cx} ${cy} ${cx - r} ${cy}Q${cx} ${cy} ${cx} ${cy - r}Z`;

export function makeSymbols(h) {
  return {
    // W1 — Qalam Q: a heavy Unbounded O whose tail is a gold reed-pen stroke.
    W1: (p) => h.qalamO(p, 21.5, 22, 34),

    // W2 — Underline Signature: the e sits on the gold swash that runs under the wordmark.
    W2: (p) => {
      const e = h.glyph("bricolage-800", "e", 30);
      return `<circle cx="24" cy="24" r="21" fill="${p.primary}"/>` +
        `<path fill="${p.knock}" d="${h.shift(e.d, 24 - e.cx, 22.5 - e.cy)}"/>` +
        `<rect x="13.5" y="32.5" width="21" height="4.2" rx="2.1" fill="${p.flat ? p.knock : p.accent}"/>`;
    },

    // K1 — Kufic Qaf: the ق loop with its two dots, lifted from the Kufic wordmark.
    K1: (p) => {
      // Initial-form ق: loop on the right, baseline running out to the left (RTL joining).
      const c = 8, ox = 4, oy = 4;
      const ink = [[0, 4], [1, 4], [2, 4], [3, 4], [4, 4], [2, 2], [3, 2], [4, 2], [2, 3], [4, 3], [0, 3]];
      return cellsSolid(ink, c, ox, oy, p.primary) + cells([[2, 0], [4, 0]], c, ox, oy, p.accent);
    },

    // K2 — Ruqaa Seal: a round seal, إتقان in Ruqaa at the centre, the name running round the band.
    K2: (p) => h.seal(p),

    // P1 — Bubble Tile: a chunky, lit 3D app tile with an extruded e and a gold sparkle.
    P1: (p, u) => {
      const e = h.glyph("baloo-800", "e", 31);
      const ex = 24 - e.cx, ey = 23 - e.cy;
      const top = p.flat ? p.primary : `url(#bt${u})`;
      return (p.flat ? "" : `<defs><linearGradient id="bt${u}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${p.hi}"/><stop offset="1" stop-color="${p.primary}"/></linearGradient></defs>`) +
        `<rect x="5" y="8" width="38" height="37" rx="12" fill="${p.shade}"/>` +
        `<rect x="5" y="4" width="38" height="37" rx="12" fill="${top}"/>` +
        (p.flat ? "" : `<rect x="10" y="7.5" width="22" height="3.2" rx="1.6" fill="#FFFFFF" fill-opacity="0.22"/>`) +
        (p.flat ? "" : `<path fill="${p.shade}" d="${h.shift(e.d, ex, ey + 2)}"/>`) +
        `<path fill="${p.knock}" d="${h.shift(e.d, ex, ey)}"/>` +
        `<path fill="${p.flat ? p.knock : p.accent}" d="${sparkle(37.5, 11, 5)}"/>`;
    },

    // P2 — Building Blocks: three isometric blocks; the top one is gold.
    P2: (p) => {
      const a = 13.5, w = a * 0.866, hh = a * 0.5;
      const em = [p.hi, p.primary, p.side], au = [p.accentHi, p.accent, p.accentLo];
      const x0 = 24 - w / 2, y0 = 44.5;
      return cube(x0 + w, y0 - hh, a, em, p.flat, p.knock) + cube(x0, y0, a, em, p.flat, p.knock) +
        cube(x0 + w / 2, y0 - hh / 2 - a, a, au, p.flat, p.knock);
    },

    // M1 — Bookmark Check: a bold bookmark with a gold tick — the lesson that's done.
    M1: (p) =>
      `<path fill="${p.primary}" d="M13 3.5H35A4.5 4.5 0 0 1 39.5 8V44.5L24 35.55L8.5 44.5V8A4.5 4.5 0 0 1 13 3.5Z"/>` +
      `<path fill="none" stroke="${p.flat ? p.knock : p.accent}" stroke-width="5.2" stroke-linecap="round" stroke-linejoin="round" d="M16.5 18.5L22 24L32.5 13.5"/>`,

    // M2 — Pinwheel: four bold capsules turning around a gold core; an eight-point star in motion.
    M2: (p) => {
      const cap = `<rect x="8" y="5.5" width="23" height="10.5" rx="5.25"/>`;
      const g = (deg, fill) => `<g fill="${fill}" transform="rotate(${deg} 24 24)">${cap}</g>`;
      return g(0, p.primary) + g(90, p.hi2) + g(180, p.primary) + g(270, p.hi2) +
        `<path fill="${p.accent}" d="${rh(24, 24, 5.2)}"/>`;
    },
  };
}

// Wide marks used in lockups instead of the 48×48 symbol.
export function makeMarks(h) {
  return {
    K1: (p) => {
      const c = 48 / 5.6, ox = 0, oy = 3;
      return { w: r2(14 * c), body: cellsSolid(KUFIC_INK, c, ox, oy, p.primary) + cells(KUFIC_GOLD, c, ox, oy, p.accent) };
    },
  };
}

export const wordmarks2 = {
  W1: { lines: [[{ t: "ET", f: "unbounded-800", s: 27, role: "ink", ls: 0.02 }, { custom: "qalamO", f: "unbounded-800", s: 27, role: "ink" }, { t: "AN", f: "unbounded-800", s: 27, role: "ink", ls: 0.02 }], [{ t: "TUTOR", f: "unbounded-500", s: 9.5, role: "sub", ls: 0.62 }]], gap: 6 },
  W2: { lines: [[{ t: "et", f: "bricolage-800", s: 38, role: "primary", ls: -0.03 }, { custom: "swashQ", f: "bricolage-800", s: 38, role: "primary" }, { t: "an", f: "bricolage-800", s: 38, role: "primary", ls: -0.03 }, { space: 7 }, { t: "tutor", f: "bricolage-500", s: 38, role: "ink", ls: -0.03 }]] },
  K1: { lines: [[{ t: "ETQAN", f: "readex-600", s: 21, role: "ink", ls: 0.12 }], [{ t: "TUTOR", f: "readex-400", s: 21, role: "sub", ls: 0.12 }]], gap: 4 },
  K2: { lines: [[{ t: "Etqan Tutor", f: "readex-600", s: 23, role: "ink", ls: -0.01 }], [{ t: "إتقان تيوتر", f: "ruqaa-700", s: 21, role: "primary", ls: 0 }]], gap: 4 },
  P1: { lines: [[{ t: "etqan", f: "baloo-800", s: 34, role: "primary", ls: -0.01, extrude: 2.4 }, { space: 7 }, { t: "tutor", f: "baloo-800", s: 34, role: "sub", ls: -0.01 }]] },
  P2: { lines: [[{ t: "etqan", f: "fredoka-700", s: 32, role: "primary", ls: 0 }, { space: 6 }, { t: "tutor", f: "fredoka-500", s: 32, role: "ink", ls: 0 }]] },
  M1: { lines: [[{ t: "etqan", f: "jakarta-800", s: 30, role: "ink", ls: -0.04 }, { space: 6 }, { t: "tutor", f: "jakarta-800", s: 30, role: "primary", ls: -0.04 }]] },
  M2: { lines: [[{ t: "Etqan", f: "outfit-700", s: 31, role: "ink", ls: -0.02 }, { space: 6 }, { t: "Tutor", f: "outfit-400", s: 31, role: "primary", ls: -0.02 }]] },
};

export const concepts2 = [
  { id: "W1", key: "qalam-q", name: "Qalam Q", direction: "Bold wordmark", style: "wordmark",
    idea: "ETQAN in a wide, heavy display face. The Q's tail is a single gold reed-pen stroke, cut flat the way a qalam leaves the paper: Arabic calligraphy hidden inside a Latin wordmark.",
    traits: ["Unbounded 800, wide and confident", "Gold tail = reed-pen stroke", "Q alone works as the icon"] },
  { id: "W2", key: "underline-signature", name: "Underline Signature", direction: "Bold wordmark", style: "wordmark",
    idea: "A heavy, characterful lowercase wordmark. The q's descender keeps going and turns into a gold underline under the whole name, like a teacher's signature under work that passed.",
    traits: ["Bricolage Grotesque 800", "q swash = signature underline", "Feels editorial and human"] },
  { id: "K1", key: "square-kufic", name: "Square Kufic", direction: "Arabic calligraphy", style: "arabic",
    idea: "إتقان written in square Kufic, the geometric script of tiles and minarets, built on a strict cell grid. Every dot is a gold square. The ق loop alone becomes the app icon, and it is also the Q in Etqan.",
    traits: ["Real Arabic word, built on a grid", "Gold dots, emerald strokes", "Pixel-perfect at small sizes"] },
  { id: "K2", key: "ruqaa-seal", name: "Ruqaa Seal", direction: "Arabic calligraphy", style: "arabic",
    idea: "A round seal (khatm), like the stamp on an ijazah certificate. إتقان in Ruqaa script sits in the centre; ETQAN TUTOR · ACADEMY PLATFORM runs round the band, set off by gold diamonds.",
    traits: ["Certificate / ijazah feeling", "Aref Ruqaa calligraphy", "Premium, traditional, trusted"] },
  { id: "P1", key: "bubble-tile", name: "Bubble Tile", direction: "Playful 3D", style: "3d",
    idea: "A soft, chunky app tile that looks pressable: lit from above, with a deep emerald base, an extruded e and a gold sparkle. The wordmark has the same pressed-button depth.",
    traits: ["Duolingo-style depth", "Baloo Bhaijaan 2 (Arabic + Latin)", "Made for the app icon"] },
  { id: "P2", key: "building-blocks", name: "Building Blocks", direction: "Playful 3D", style: "3d",
    idea: "Three isometric blocks: two emerald blocks hold up one gold block. Teachers and admins lay the base, and the student's achievement sits on top. It is also the academy, built block by block.",
    traits: ["True isometric 3D", "Gold = the achievement", "Fredoka, round and friendly"] },
  { id: "M1", key: "bookmark-check", name: "Bookmark Check", direction: "Bold modern icon", style: "icon",
    idea: "A heavy bookmark with a gold tick: the lesson that's done, the attendance taken, the invoice paid. Every part of running an academy ends in that tick.",
    traits: ["One bold silhouette", "Bookmark + done = progress", "Plus Jakarta Sans 800"] },
  { id: "M2", key: "pinwheel", name: "Pinwheel", direction: "Bold modern icon", style: "icon",
    idea: "Four bold capsules turn around a gold core and form an eight-point star in motion. The star in today's logo comes back as something that moves, the way Slack's or Airbnb's marks do.",
    traits: ["Two-tone emerald + gold core", "Echoes the current star", "Strong, animated feel"] },
];
