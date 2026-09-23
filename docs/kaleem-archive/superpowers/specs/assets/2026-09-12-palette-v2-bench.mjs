// Phase 1 palette design tool — OKLCH ramps + WCAG 2.2 verification.
// Throwaway: the verified VALUES graduate to tokens/src/*.tokens.json in phase 2,
// and contrast.mjs in the tokens repo is the real gate. This is the design bench.

// ---------- colour maths ----------
function oklchToRgb(L, C, H) {
	const a = C * Math.cos((H * Math.PI) / 180);
	const b = C * Math.sin((H * Math.PI) / 180);
	const l_ = L + 0.3963377774 * a + 0.2158037573 * b;
	const m_ = L - 0.1055613458 * a - 0.0638541728 * b;
	const s_ = L - 0.0894841775 * a - 1.291485548 * b;
	const l = l_ ** 3,
		m = m_ ** 3,
		s = s_ ** 3;
	const lin = [
		4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
		-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
		-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
	];
	return lin.map((c) => {
		const v = c <= 0.0031308 ? 12.92 * c : 1.055 * c ** (1 / 2.4) - 0.055;
		return Math.round(Math.min(1, Math.max(0, v)) * 255);
	});
}
// Is the colour inside sRGB before clamping? Clamping silently changes the hue.
function inGamut(L, C, H) {
	const a = C * Math.cos((H * Math.PI) / 180);
	const b = C * Math.sin((H * Math.PI) / 180);
	const l_ = L + 0.3963377774 * a + 0.2158037573 * b;
	const m_ = L - 0.1055613458 * a - 0.0638541728 * b;
	const s_ = L - 0.0894841775 * a - 1.291485548 * b;
	const l = l_ ** 3,
		m = m_ ** 3,
		s = s_ ** 3;
	const lin = [
		4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
		-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
		-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
	];
	return lin.every((c) => c >= -0.0005 && c <= 1.0005);
}
const hex = (L, C, H) =>
	"#" +
	oklchToRgb(L, C, H)
		.map((v) => v.toString(16).padStart(2, "0"))
		.join("")
		.toUpperCase();

function relLum(h) {
	const c = h.replace("#", "");
	const ch = [0, 2, 4]
		.map((i) => parseInt(c.slice(i, i + 2), 16) / 255)
		.map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
	return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2];
}
function ratio(a, b) {
	const [hi, lo] = [relLum(a), relLum(b)].sort((x, y) => y - x);
	return (hi + 0.05) / (lo + 0.05);
}
// Composite a foreground with alpha over an opaque backdrop (for --overlay).
function over(fgHex, alpha, bgHex) {
	const p = (h) =>
		[0, 2, 4].map((i) => parseInt(h.replace("#", "").slice(i, i + 2), 16));
	const [fr, fg_, fb] = p(fgHex),
		[br, bg_, bb] = p(bgHex);
	const mix = (f, b) => Math.round(f * alpha + b * (1 - alpha));
	return (
		"#" +
		[mix(fr, br), mix(fg_, bg_), mix(fb, bb)]
			.map((v) => v.toString(16).padStart(2, "0"))
			.join("")
			.toUpperCase()
	);
}

// ---------- hue anchors: Serene Scholar, rebuilt ----------
// Hues held constant down each ramp so the family reads as one system.
// `green` is deliberately NOT the brand emerald: a success alert that is the exact
// colour of the primary CTA reads as an action, not an outcome. Shifted yellow-ward.
const H = { emerald: 168, green: 146, gold: 88, cream: 82, ink: 170, red: 28, blue: 232 };

// One lightness ladder, shared by every ramp → perceptually even steps and
// predictable cross-ramp swaps (emerald-700 and red-700 carry the same weight).
const STEPS = {
	50: 0.972,
	100: 0.942,
	200: 0.888,
	300: 0.818,
	400: 0.734,
	500: 0.646,
	600: 0.558,
	700: 0.468,
	800: 0.384,
	900: 0.302,
	950: 0.224,
};
// Chroma peaks mid-ramp and falls off at both ends (near-white and near-black
// cannot hold chroma in sRGB).
const CHROMA = {
	50: 0.012,
	100: 0.022,
	200: 0.04,
	300: 0.058,
	400: 0.078,
	500: 0.09,
	600: 0.094,
	700: 0.088,
	800: 0.074,
	900: 0.058,
	950: 0.042,
};

// A near-white neutral needs its chroma held roughly FLAT, not bell-curved: scaling
// the shared curve collapses step 50 to ~0.002 and the cream reads as grey. Serene
// Scholar's warmth lives almost entirely in the lightest two steps, so `sand` gets
// its own curve rather than a scale factor.
const SAND_CHROMA = {
	50: 0.014,
	100: 0.016,
	200: 0.018,
	300: 0.018,
	400: 0.017,
	500: 0.016,
	600: 0.015,
	700: 0.013,
	800: 0.011,
	900: 0.009,
	950: 0.007,
};

function ramp(hue, chromaScale = 1, hueShift = {}, chromaMap = null) {
	const out = {};
	for (const k of Object.keys(STEPS)) {
		const L = STEPS[k];
		let C = (chromaMap ? chromaMap[k] : CHROMA[k] * chromaScale);
		const h = hue + (hueShift[k] ?? 0);
		while (C > 0 && !inGamut(L, C, h)) C -= 0.002; // stay in sRGB honestly
		out[k] = { hex: hex(L, C, h), L, C: +C.toFixed(3), H: h };
	}
	return out;
}

const R = {
	emerald: ramp(H.emerald),
	green: ramp(H.green),
	gold: ramp(H.gold, 1.15),
	// Neutrals: a hint of the cream hue so greys never read cold against the brand.
	sand: ramp(H.cream, 1, {}, SAND_CHROMA),
	ink: ramp(H.ink, 0.14),
	red: ramp(H.red, 1.2),
	blue: ramp(H.blue, 0.95),
};

// ---------- semantic assignment ----------
const light = {
	background: R.sand[50].hex,
	foreground: R.ink[950].hex,
	card: "#FFFFFF",
	"card-foreground": R.ink[950].hex,
	popover: "#FFFFFF",
	"popover-foreground": R.ink[950].hex,
	primary: R.emerald[700].hex,
	"primary-foreground": "#FFFFFF",
	secondary: R.sand[100].hex,
	"secondary-foreground": R.ink[900].hex,
	muted: R.sand[100].hex,
	"muted-foreground": R.ink[700].hex,
	accent: R.gold[500].hex,
	"accent-foreground": R.gold[950].hex,
	destructive: R.red[600].hex,
	"destructive-foreground": "#FFFFFF",
	border: R.sand[200].hex,
	input: R.sand[500].hex,
	ring: R.emerald[600].hex,
	success: R.green[700].hex,
	"success-foreground": "#FFFFFF",
	warning: R.gold[600].hex,
	"warning-foreground": "#FFFFFF",
	info: R.blue[600].hex,
	"info-foreground": "#FFFFFF",
	overlay: { color: R.ink[950].hex, alpha: 0.55 },
};

const dark = {
	background: R.ink[950].hex,
	foreground: R.sand[100].hex,
	card: R.ink[900].hex,
	"card-foreground": R.sand[100].hex,
	popover: R.ink[900].hex,
	"popover-foreground": R.sand[100].hex,
	primary: R.emerald[500].hex,
	"primary-foreground": R.ink[950].hex,
	secondary: R.ink[800].hex,
	"secondary-foreground": R.sand[100].hex,
	muted: R.ink[800].hex,
	"muted-foreground": R.ink[300].hex,
	accent: R.gold[400].hex,
	"accent-foreground": R.gold[950].hex,
	destructive: R.red[400].hex,
	"destructive-foreground": R.red[950].hex,
	border: R.ink[800].hex,
	input: R.ink[500].hex,
	ring: R.emerald[400].hex,
	success: R.green[400].hex,
	"success-foreground": R.ink[950].hex,
	warning: R.gold[400].hex,
	"warning-foreground": R.gold[950].hex,
	info: R.blue[400].hex,
	"info-foreground": R.ink[950].hex,
	overlay: { color: "#000000", alpha: 0.68 },
};

// ---------- the pairing manifest (phase 2 ships this as JSON) ----------
// [foreground, [surfaces], threshold, label]
const PAIRS = [
	["foreground", ["background", "card", "popover"], 4.5, "body text"],
	["muted-foreground", ["background", "card", "muted"], 4.5, "secondary text"],
	["primary-foreground", ["primary"], 4.5, "primary button label"],
	["secondary-foreground", ["secondary"], 4.5, "secondary button label"],
	["accent-foreground", ["accent"], 4.5, "accent badge label"],
	["destructive-foreground", ["destructive"], 4.5, "destructive label"],
	["success-foreground", ["success"], 4.5, "success label"],
	["warning-foreground", ["warning"], 4.5, "warning label"],
	["info-foreground", ["info"], 4.5, "info label"],
	// WCAG 1.4.11 — form-control boundary must be identifiable at rest.
	// --border (decorative card/divider hairlines) is exempt by 1.4.11 and absent here.
	["input", ["card", "background"], 3.0, "form-control border"],
	// WCAG 2.4.11 Focus Appearance. Model the ACTUAL rendered stack, which the
	// recipe `ring-2 ring-ring ring-offset-2 ring-offset-<surface>` produces:
	//
	//   [surface] [ring 2px] [offset 2px = surface colour] [component]
	//
	// The offset gap means the ring NEVER abuts the component — on both of its
	// edges the adjacent colour is the surface. So `ring on primary` is not a
	// rendered pair, and asserting it was wrong, not merely strict. What 2.4.11
	// actually requires is that the ring area differ ≥3:1 between its focused and
	// unfocused states — unfocused, that area IS the surface. Hence: ring vs every
	// surface a focusable control can sit on.
	//
	// This is only sound while the offset colour tracks the surface. The current
	// recipe hardcodes `ring-offset-background`, so a control on a card draws a
	// background-coloured halo. Contrast still passes (ring clears 3:1 on both),
	// but it is a visible seam -> logged for the Dialog/focusRing work, not here.
	["ring", ["background", "card", "secondary", "muted"], 3.0, "focus ring"],
	// Non-text status surfaces must be distinguishable from the page (1.4.11).
	["primary", ["background", "card"], 3.0, "primary surface vs page"],
	["destructive", ["background", "card"], 3.0, "destructive surface vs page"],
];
const AAA = [["foreground", ["background", "card"], 7.0, "body text (AAA target)"]];

// ---------- report ----------
function check(theme, name) {
	let fails = 0,
		aaaMiss = 0;
	const lines = [];
	const run = (list, isAAA) => {
		for (const [fg, surfaces, min, label] of list) {
			for (const s of surfaces) {
				const r = ratio(theme[fg], theme[s]);
				const ok = r >= min;
				if (!ok) isAAA ? aaaMiss++ : fails++;
				lines.push(
					`  ${ok ? "PASS" : "FAIL"} ${r.toFixed(2).padStart(5)}:1 (≥${min}) ${label}: ${fg} ${theme[fg]} on ${s} ${theme[s]}`,
				);
			}
		}
	};
	run(PAIRS, false);
	run(AAA, true);
	// --- overlay, composited ---
	// The earlier version asserted `foreground on scrim`, which is a pair NOTHING
	// paints: the scrim sits BEHIND the dialog, and dialog text renders on the
	// popover surface. Asserting an unpainted pair is how a gate ends up measuring
	// something real-looking and irrelevant. What is actually rendered is the
	// popover sitting ON the scrim, so that is what gets the 1.4.11 threshold.
	const scrim = over(theme.overlay.color, theme.overlay.alpha, theme.background);
	const rSep = ratio(theme.popover, scrim);
	// NOT a blocking assertion, and the second thing I got wrong here. SC 1.4.11
	// covers user-interface COMPONENTS (controls) and graphics needed to understand
	// content. A modal's background FILL is neither — the controls inside it are
	// covered by their own pairs above. Asserting 3:1 here demands something no dark
	// theme can give: the page and the dialog are both dark, so no scrim alpha fixes
	// it (a lighter scrim moves the page closer to the dialog and makes it worse).
	// Reported as a design-quality signal instead.
	lines.push(
		`  note ${rSep.toFixed(2).padStart(5)}:1        popover ${theme.popover} vs scrimmed page ${scrim} — modal separation`,
	);
	// Non-blocking: how much the scrim darkens the page behind the modal. In dark
	// mode this is necessarily weak — the page is already near-black, so a black
	// scrim has little room to work. Modality there is carried by the popover being
	// LIGHTER than the page (the check above), not by the scrim. Reporting it as a
	// blocking failure would be demanding something the theme cannot give.
	const rDim = ratio(scrim, theme.background);
	lines.push(
		`  ${rDim >= 1.5 ? "ok  " : "note"} ${rDim.toFixed(2).padStart(5)}:1        overlay dims the page behind the modal`,
	);
	// Evidence for the standing ban on --accent as a text colour (design-system.md).
	// Not an assertion: a future palette could legitimately make it pass. Printed so
	// the ban stays justified by a number rather than by folklore.
	lines.push(
		`  note ${ratio(theme.accent, theme.background).toFixed(2).padStart(5)}:1        --accent as TEXT on background (banned; needs 4.5)`,
	);
	console.log(`\n=== ${name} ===`);
	console.log(lines.join("\n"));
	console.log(`  --> ${fails} AA/1.4.11/2.4.11 failures, ${aaaMiss} AAA target missed`);
	return fails;
}

if (process.argv[2] === "ramps") {
	for (const [n, r] of Object.entries(R))
		console.log(
			n.padEnd(8),
			Object.entries(r)
				.map(([k, v]) => `${k}:${v.hex}`)
				.join(" "),
		);
} else {
	const f = check(light, "LIGHT") + check(dark, "DARK");
	console.log(`\nTOTAL BLOCKING FAILURES: ${f}`);
	if (process.argv[2] === "emit") {
		const fmt = (t) =>
			Object.entries(t)
				.map(([k, v]) =>
					k === "overlay"
						? `  --overlay: color-mix(in srgb, ${v.color} ${Math.round(v.alpha * 100)}%, transparent);`
						: `  --${k}: ${v};`,
				)
				.join("\n");
		console.log("\n:root {\n" + fmt(light) + "\n}\n\n.dark {\n" + fmt(dark) + "\n}");
	}
}
