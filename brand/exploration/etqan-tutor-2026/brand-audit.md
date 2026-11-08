# Brand audit: Etqan Tutor (2026-10-27)

I read the sources below. Every hex value here was copied from a file, not estimated.

## Sources

| Source | Role |
|---|---|
| `etqan_tutor_official_site/src/styles/global.css` | The live marketing site's palette and fonts. **Used as the reference for the logo.** |
| `etqan_tutor/tokens/src/color.primitive.tokens.json`, `tokens/tokens.css` | Product (dashboard) tokens, "Serene Scholar v2" |
| `etqan_tutor_official_site/src/components/Logo.astro`, `public/favicon.svg` | The current logo and favicon |
| `etqan_tutor/brand/design.md`, `brand/logos/README.md`, `brand/ASSET-INDEX.md` | The old Kaleem brand brief. Out of date (see Conflicts) |

## Colours used in the concepts

| Role in the logos | Hex | Source token |
|---|---|---|
| Primary mark (light) | `#146B50` | site `--color-emerald-700` (tokens `emerald-700` is `#146A51`) |
| Mark on dark grounds | `#4FA082` | site `--color-emerald-500` (tokens `emerald-500` is `#50A083`) |
| Dark ground | `#022217` | site `--color-emerald-950` |
| Gold accent (light) | `#B79A58` | site `--color-gold` |
| Gold text (TUTOR) | `#8D6F27` | site `--color-gold-deep` |
| Gold on dark | `#C7AD74` | site `--color-gold-400` |
| Gold on emerald | `#D9C69D` / `#E6D9BC` | site `--color-gold-300` / `--color-gold-soft` |
| Light ground, reversed | `#FAF9F5` | site `--color-marble` |
| Wordmark ink, mono | `#202522` | site `--color-ink` |

No colour outside these was added to any logo. The mockups also use the dashboard's own token values: `#FBF5EB`, `#146A51`, `#DFF1E9`, `#E0D9CD` and `#545D59` in light, and `#191C1B`, `#2A302E` and `#9FD0BC` in dark.

## Type

The site loads these three faces, and the logos use the same ones:

| Face | Use | Logos |
|---|---|---|
| Fraunces Variable | display | B, G, H |
| Inter Variable | UI | A, C, D, E, F, and "TUTOR" in A and H |
| IBM Plex Sans Arabic | Arabic | G |

All three are OFL-licensed. For the logos they were converted to outlines from the static instances Google Fonts serves.

## Current logo

The current mark is an eight-point star (rub el hizb) drawn as two outlined squares with 2px strokes, in `#146B50`, with a gold dot `#B79A58`. Beside it, the wordmark has "Etqan" in Inter bold with "TUTOR" below, tracked, in gold-deep. The outline is about 1px wide at 16–24px, so the favicon looks faint. Concept A keeps this idea and makes it solid.

## Conflicts found

1. **`brand/design.md` and `brand/logos/README.md` describe the old Kaleem brand.** Its palette is `#0E5C4F` / `#C9A227`, its ground is cream `#FAF7F0`, and its wordmark is "kaleem". They were never updated for Etqan, so they should not be used as the brand source.
2. **The gold differs between the site and the product.** The site accent is `#B79A58`. The product `--accent` is `#A88A3C`, and the closest primitive `gold-400` is `#C1A665`. The emerald differs only by rounding (`#146B50` vs `#146A51`).
3. **The neutrals differ too.** The site uses marble `#FAF9F5` and ink `#202522`. The product uses sand-50 `#FBF5EB` and ink-950 `#191C1B`.

**What to treat as authoritative for now:** the marketing site palette, for anything the logo touches, because the logo is first seen there. When the chosen logo is integrated, unify the gold (site `#B79A58` vs tokens `#A88A3C`) in one place. That is a separate decision; nothing was changed.
