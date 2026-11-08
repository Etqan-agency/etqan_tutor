// Etqan Tutor logo concepts. Every symbol is drawn on a 48×48 grid and only
// paints its own shapes (no background), so it works transparent on any surface.
// p = { primary, accent, ink, sub }

const r2 = (n) => Math.round(n * 100) / 100;

// A — octagram keystone: union of two squares (half-size 14) traced as one polygon.
function octagram(cx, cy, s) {
  const t = s * Math.SQRT2, k = t - s;
  const pts = [
    [t, 0], [s, k], [s, s], [k, s], [0, t], [-k, s], [-s, s], [-s, k],
    [-t, 0], [-s, -k], [-s, -s], [-k, -s], [0, -t], [k, -s], [s, -s], [s, -k],
  ];
  return "M" + pts.map(([x, y]) => `${r2(cx + x)} ${r2(cy + y)}`).join("L") + "Z";
}
const circle = (cx, cy, r) =>
  `M${cx - r} ${cy}a${r} ${r} 0 1 0 ${2 * r} 0a${r} ${r} 0 1 0 ${-2 * r} 0Z`;
const rhombus = (cx, cy, h) =>
  `M${cx} ${cy - h}L${cx + h} ${cy}L${cx} ${cy + h}L${cx - h} ${cy}Z`;

const symbols = {
  A: (p) =>
    `<path fill="${p.primary}" stroke="${p.primary}" stroke-width="2" stroke-linejoin="round" fill-rule="evenodd" d="${octagram(24, 24, 13.6)}${circle(24, 24, 7.6)}"/>` +
    `<circle cx="24" cy="24" r="4" fill="${p.accent}"/>`,

  // B uses the real Fraunces "e" — injected by build.mjs (needs font outlines).
  B: null,

  C: (p) =>
    `<path fill="${p.primary}" d="M7 8h34a1.5 1.5 0 0 1 1.5 1.5v5a1.5 1.5 0 0 1-1.5 1.5H38V38.5a1.5 1.5 0 0 1-1.5 1.5h-5a1.5 1.5 0 0 1-1.5-1.5V16H14.5v16H24a1.5 1.5 0 0 1 1.5 1.5v5A1.5 1.5 0 0 1 24 40H7a1.5 1.5 0 0 1-1.5-1.5v-29A1.5 1.5 0 0 1 7 8Z"/>` +
    `<rect x="17.5" y="20.5" width="7" height="7" rx="1.2" fill="${p.accent}"/>`,

  D: (p) =>
    `<rect x="29" y="6" width="13" height="10" rx="2.5" fill="${p.accent}"/>` +
    `<rect x="17.5" y="19" width="24.5" height="10" rx="2.5" fill="${p.primary}"/>` +
    `<rect x="6" y="32" width="36" height="10" rx="2.5" fill="${p.primary}"/>`,

  E: (p) => {
    // top-left leaf; the other three are mirrors. Outer corner is a quarter circle,
    // inner corner chamfered to make room for the shared core.
    const leaf = "M4 19A15 15 0 0 1 19 4H20.5A1.5 1.5 0 0 1 22 5.5V16L16 22H5.5A1.5 1.5 0 0 1 4 20.5Z";
    return (
      `<g fill="${p.primary}"><path d="${leaf}"/><path d="${leaf}" transform="matrix(-1 0 0 1 48 0)"/>` +
      `<path d="${leaf}" transform="matrix(1 0 0 -1 0 48)"/><path d="${leaf}" transform="matrix(-1 0 0 -1 48 48)"/></g>` +
      `<path fill="${p.accent}" d="${rhombus(24, 24, 4.6)}"/>`
    );
  },

  F: (p) =>
    `<path fill="none" stroke="${p.primary}" stroke-width="7" d="M8 24H40A16 16 0 1 0 34.28 36.26"/>` +
    `<circle cx="37.67" cy="32.31" r="3" fill="${p.accent}"/>`,

  G: (p) =>
    `<path fill="none" stroke="${p.primary}" stroke-width="7" stroke-linecap="round" d="M8.5 21C8.5 33 14 38.5 24 38.5S39.5 33 39.5 21"/>` +
    `<path fill="${p.accent}" d="${rhombus(18.5, 13, 4.4)}${rhombus(29.5, 13, 4.4)}"/>`,

  H: (p) => {
    // Two-centred pointed arch, walls 6 units thick, open at the threshold.
    const outer = "M8 44V24A22 22 0 0 1 24 2.83A22 22 0 0 1 40 24V44H34V24A13.5 13.5 0 0 0 24 10.96A13.5 13.5 0 0 0 14 24V44Z";
    return `<path fill="${p.primary}" d="${outer}"/><path fill="${p.accent}" d="${rhombus(24, 33, 4.6)}"/>`;
  },
};

// Wordmark runs. role picks the palette colour; ls = letter-spacing in em.
const wordmarks = {
  A: { lines: [[{ t: "Etqan", f: "inter-700", s: 25, role: "ink", ls: -0.015 }], [{ t: "TUTOR", f: "inter-600", s: 9.6, role: "sub", ls: 0.34 }]], gap: 2.5 },
  B: { lines: [[{ t: "etqan", f: "fraunces-600", s: 31, role: "primary", ls: -0.01 }, { mark: "rhombus" }, { t: "tutor", f: "fraunces-500", s: 31, role: "ink", ls: -0.01 }]] },
  C: { lines: [[{ t: "ETQAN", f: "inter-700", s: 21, role: "ink", ls: 0.09 }, { space: 8 }, { t: "TUTOR", f: "inter-500", s: 21, role: "sub", ls: 0.09 }]] },
  D: { lines: [[{ t: "Etqan", f: "inter-700", s: 25, role: "ink", ls: -0.02 }, { space: 6 }, { t: "Tutor", f: "inter-500", s: 25, role: "primary", ls: -0.02 }]] },
  E: { lines: [[{ t: "etqan", f: "inter-700", s: 27, role: "primary", ls: -0.03 }, { space: 6 }, { t: "tutor", f: "inter-500", s: 27, role: "ink", ls: -0.03 }]] },
  F: { lines: [[{ t: "etqan", f: "inter-600", s: 26, role: "ink", ls: -0.025 }, { mark: "bar" }, { t: "tutor", f: "inter-500", s: 26, role: "sub", ls: -0.025 }]] },
  G: { lines: [[{ t: "Etqan Tutor", f: "fraunces-600", s: 22, role: "ink", ls: -0.005 }], [{ t: "إتقان تيوتر", f: "plexar-700", s: 17, role: "primary", ls: 0, rtl: true }]], gap: 3 },
  H: { lines: [[{ t: "Etqan", f: "fraunces-600", s: 29, role: "ink", ls: -0.01 }], [{ t: "TUTOR", f: "inter-600", s: 9.4, role: "sub", ls: 0.4 }]], gap: 2.5 },
};

export const concepts = [
  {
    id: "A", key: "octagram-keystone", name: "Octagram Keystone", direction: "Premium Geometric SaaS",
    idea: "The eight-point star from the current site, rebuilt as a solid, heavier mark with a round window and a gold core. It keeps the equity of today's logo but stops depending on a 2px outline that disappears at favicon size.",
    traits: ["Evolution of the current mark", "Solid fill, survives 16px", "Inter wordmark with tracked TUTOR, like today"],
  },
  {
    id: "B", key: "scholar-wordmark", name: "Scholar Wordmark", direction: "Custom Typography / Wordmark",
    idea: "The name does the work. Lowercase etqan in Fraunces, the display face the site already uses for headings, joined to tutor by a gold rhombus. The symbol is the Fraunces e cut out of an emerald tile.",
    traits: ["Typography-led, editorial", "Rhombus = Arabic nuqta shape", "Symbol is a derived app tile"],
  },
  {
    id: "C", key: "et-ligature", name: "ET Ligature", direction: "ET Letterform Monogram",
    idea: "E and T share one top bar. The E's middle bar is pulled out and turned gold: the one piece that makes the letters read, the same way an academy's operations hold together around one system.",
    traits: ["Monogram, square and sturdy", "Reads as ET without a wordmark", "Strong in a dashboard sidebar"],
  },
  {
    id: "D", key: "ascent", name: "Ascent", direction: "Abstract Learning & Progress",
    idea: "Three right-aligned bars, growing toward the gold top step. Read one way it is progress and levels; read the other it is a right-aligned block of text, the shape of an Arabic paragraph.",
    traits: ["Progress / levels metaphor", "Pure rectangles, pixel-crisp", "Echoes RTL text alignment"],
  },
  {
    id: "E", key: "academy-quad", name: "Academy Quad", direction: "Connected Academy Ecosystem",
    idea: "Four leaves around one gold core: teachers, students, parents and staff, connected through one academy. Each leaf rounds outward and is cut inward toward the centre, so the core is held, not crowded.",
    traits: ["Four roles, one platform", "Symmetric, very stable", "Good for app icon and loaders"],
  },
  {
    id: "F", key: "loop-e", name: "Loop e", direction: "Minimal Modern EdTech",
    idea: "A single geometric e drawn with one stroke. The loop stops short, and a gold dot sits in the gap: the last step that turns practice into mastery (itqan). The most product-like of the eight.",
    traits: ["Most minimal", "Monoline stroke", "Friendly, modern SaaS tone"],
  },
  {
    id: "G", key: "ta-nuqta", name: "Ta & Nuqta", direction: "Distinctive Arabic-English Identity",
    idea: "The Arabic letter <bdi lang=\"ar\">ت</bdi>, as in <bdi lang=\"ar\">إتقان</bdi> and <bdi lang=\"ar\">تيوتر</bdi>: an emerald bowl with its two dots in gold, drawn as rhombi the way a reed pen writes them. The lockup sets English and Arabic as equals.",
    traits: ["Arabic letterform, not ornament", "Bilingual lockup", "Most distinctive in the category"],
  },
  {
    id: "H", key: "gateway-arch", name: "Gateway Arch", direction: "Experimental Premium Brand Mark",
    idea: "A pointed arch, the doorway of a place of learning, with a gold rhombus standing in the opening. It ties directly to the arch photography already on the marketing site, kept abstract and architectural.",
    traits: ["Matches site photography", "Premium, institutional", "Arch carries cultural weight"],
  },
];

export { symbols, wordmarks };
