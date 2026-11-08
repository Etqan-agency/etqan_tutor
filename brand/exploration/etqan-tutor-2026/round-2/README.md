# Etqan Tutor logos, round 2 (2026-10-27)

Khaled found round 1 "too plain, generic", and didn't like its fonts or style. He asked for four styles and to keep the emerald and gold. Round 2 has two concepts per style:

| ID | Name | Style | Idea | Wordmark font |
|---|---|---|---|---|
| W1 | Qalam Q | Bold wordmark | The Q's tail is a gold reed-pen (qalam) stroke | Unbounded 800/500 |
| W2 | Underline Signature | Bold wordmark | The q's descender becomes a gold signature underline | Bricolage Grotesque 800/500 |
| K1 | Square Kufic | Arabic calligraphy | إتقان in hand-built square Kufic, gold square dots; the ق loop is the icon | Readex Pro |
| K2 | Ruqaa Seal | Arabic calligraphy | Ijazah-style round seal, إتقان in Ruqaa, name on the band | Aref Ruqaa + Readex Pro |
| P1 | Bubble Tile | Playful 3D | Pressable 3D app tile, extruded e, gold sparkle | Baloo Bhaijaan 2 |
| P2 | Building Blocks | Playful 3D | Isometric blocks; two emerald blocks lift a gold one | Fredoka |
| M1 | Bookmark Check | Bold modern icon | A heavy bookmark with a gold tick: lesson done | Plus Jakarta Sans 800 |
| M2 | Pinwheel | Bold modern icon | Four capsules turning around a gold core | Outfit |

**Recommended top three (your call):**
1. **K1 Square Kufic (9.0)**
2. **M1 Bookmark Check (8.3)**
3. **K2 Ruqaa Seal (8.6)**

The full scores and reasons are in `index.html`, section E.

## Files

- `index.html`: interactive page with the gallery, mockups, comparison and scores.
- `concepts-overview.png`: one-image overview, made with the logo-design skill's `concept_sheet.py`.
- `assets/concept-<id>/`: 21 SVGs per concept, named the same way as in round 1.
  - Treatments: `light`, `dark`, `emerald`, `mono`, `reversed`.
  - Versions: `symbol`, `horizontal`, `stacked`, `wordmark`, plus `favicon`.
- `screenshots/`: desktop, mobile, dark mode, and the comparison section after use.
- `source/`: the generator. It needs the OFL TTFs listed above in `source/fonts/`.

## Colours

Only colours that already exist on the marketing site or in `@etqan/tokens`:

| Group | Colours |
|---|---|
| Emerald | `#146B50`, `#4FA082`, `#07503A`, `#022217`, `#C2E3D4`, `#76B9A0` (tokens emerald-400) |
| Gold | `#B79A58`, `#8D6F27`, `#C7AD74`, `#D9C69D`, `#E6D9BC`, `#F5EEDF` |
| Neutrals | `#FAF9F5`, `#202522` |

The 3D concepts (P1, P2) use more tones of the same colours for light and shade.

## Checks run

**`svg_audit.py` (logo-design skill)** on every symbol. The warnings that are left are deliberate:
- The seal's ring text is set on a curve.
- P1 and P2 use gradients and several shades for the 3D effect.
- The marks on tiles are light-on-tile by design.
- W1's tail is set at 15.5°.

**Playwright** on the page:
- No horizontal scrolling at desktop or mobile width, and no JS errors.
- The compare, favourite, size, download and concept-switch controls all work.

## Not done yet

- A trademark search.
- Testing the Kufic reading with Arabic readers.
- The K2 favicon is a simplified ق seal, because the band text can't be read below about 64px.
- Flat masters for P1 and P2 exist only as the `mono` and `reversed` versions.
