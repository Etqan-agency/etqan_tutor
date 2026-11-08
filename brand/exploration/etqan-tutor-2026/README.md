# Etqan Tutor logo identity exploration (October 2026)

This folder holds eight logo directions for Etqan Tutor. Each has a full set of SVG files and an interactive page for comparing them.
Nothing here is wired into the product. The marketing site, dashboard and `@etqan/tokens` are unchanged.

## Open it

Open `index.html` in a browser. It is self-contained; fonts load from Google Fonts and the page works offline with fallbacks.
The page has five sections:
- **A:** brand overview
- **B:** gallery
- **C:** in-context mockups (site header, hero, dashboard sidebar, login, mobile, favicon, grounds)
- **D:** side-by-side comparison, with favourite, copy ID, copy SVG and download
- **E:** scores

## Contents

| Path | What |
|---|---|
| `index.html` | Interactive exploration page |
| `brand-audit.md` | The brand colours and type actually in use, with the conflicts found |
| `competitor-research.md` | Competitor and SaaS logo research, each point marked Verified or Assumption |
| `skills-review.md` | Review of the six suggested Claude skills (none installed; see the file) |
| `logo-comparison.md` | Concept notes, scores and the top-three recommendation |
| `assets/concept-a … concept-h/` | 21 SVGs per concept (see the list below), plus `png/` previews |
| `screenshots/` | Page screenshots (desktop, mobile, dark), the comparison section after use, and a 16/24/32/64px size test |
| `source/` | The generator. Fonts are not included; see "Rebuild" below |

### SVG names

`etqan-tutor-<id>-<key>-<kind>-<treatment>.svg`

- **kind:** `horizontal`, `stacked`, `symbol` or `wordmark`.
- **treatment:**

  | Treatment | Use it on | What it looks like |
  |---|---|---|
  | `light` | light grounds | emerald and gold, ink text |
  | `dark` | `#022217` | emerald-500 and gold-400, marble text |
  | `emerald` | `#146B50` | marble with gold-300 |
  | `mono` | light grounds | all ink `#202522` |
  | `reversed` | dark grounds | all marble `#FAF9F5` |
- **favicon:** `…-favicon.svg`. It is the mark on an emerald tile. For B, the symbol is already a tile.

Every SVG is real vector work. Wordmarks are converted to outlines with HarfBuzz, so they need no font, and the Arabic in G is shaped and joined correctly. The files embed no raster images and have transparent backgrounds; the only backgrounds are the favicon tiles and B's symbol tile.

## Selection guide

1. **Shortlist from the gallery (B) at normal size.** Ask whether it feels like Etqan and whether you would trust it as an academy owner.
2. **Check section C for the two places the logo lives most:** the site header and the dashboard sidebar. If a logo only looks good large, drop it.
3. **In section D, set Version = Favicon and Height = 16px, then compare.** This is the browser-tab test.
4. **Switch the background to Dark and Emerald.** The logo has to hold up on the site's emerald panels.
5. **Show your top two to two or three academy owners** without explaining them, and ask what they see. This matters most for G (it may read as a smiling face) and H (it may read as a mosque doorway).
6. **Mark your favourite and send its ID** (for example `ETQ-LOGO-H-gateway-arch`). The next step would be refinement: optical tweaks, an Arabic lockup for all layouts, a clear-space and minimum-size spec, and app icons. Then integration, but only after you approve it.

Before you commit to a final mark, run a trademark search. This exploration did not do one.

## Rebuild

```sh
cd source
npm i harfbuzzjs@0.4.7 playwright-core@1.58.0
# put these OFL TTFs in source/fonts/: fraunces-500/600, inter-500/600/700, plexar-700
# (static instances from Google Fonts: Fraunces opsz 72)
node build.mjs ..          # writes ../assets and logos.json
node assemble.mjs .. /tmp/page.html
```
