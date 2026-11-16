# Etqan Tutor logo: Kufic Grid

Chosen on 2026-11-16 (concept 10, "Focus"). It replaces the Ruqaa Seal; the seal files below stay for reference.

إتقان is written in square Kufic on a one-unit grid. The emerald letters are the system and the structure; the gold squares (the dots of ن, ق and ت, and the hamza below the alif) are the data moving through it. The grid stands for the technology underneath. Every file is drawn from rectangles, so no fonts are needed.

- **Generator:** `kufic-grid/generate.mjs`. Run `node brand/logos/kufic-grid/generate.mjs` from the repo root. It writes every file below and the site's copies in `website/public/`.
- **Mark:** `etqan-tutor-kufic-grid-symbol-<light|dark|emerald|mono|reversed>.svg`.
- **App icon and favicon:** `etqan-tutor-kufic-grid-app-icon.svg`, `../favicons-app-icons/favicon.svg` and `apple-touch-icon.png` (180×180) show the ق alone on an emerald tile. Use them below 48px.
- **Website lockup:** the mark, a thin gold rule, then ETQAN / TUTOR in two letter-spaced lines, set in the site's font by `website/src/components/Logo.astro`. The mark files there are `public/brand/etqan-kufic-light.svg` (light grounds) and `etqan-kufic-dark.svg` (dark grounds).
- **Academies:** as before, this logo stays off academy-facing surfaces, which are white-label.

---

# Previous logo: Ruqaa Seal

Chosen on 2026-10-27 (concept K2 from `../exploration/etqan-tutor-2026/round-2/`).

It is a round seal, like the stamp on an ijazah: إتقان in Ruqaa sits in the centre, and ETQAN TUTOR · ACADEMY PLATFORM runs round the band, separated by gold diamonds. Every file is a vector with the text converted to outlines, so no fonts are needed.

## Website lockups

The site served these from `website/public/brand/` until 2026-11-16.

| File | Use |
|---|---|
| `logo-en-light.svg` | English, on light grounds (seal on the left) |
| `logo-ar-light.svg` | Arabic, on light grounds (seal on the right, Arabic name first) |
| `logo-en-emerald.svg`, `logo-ar-emerald.svg` | On emerald or dark grounds (footer, hero) |

## Full set

All files are named `etqan-tutor-k2-ruqaa-seal-<kind>-<treatment>.svg`.

**Kinds:**
- `symbol`: the seal alone
- `horizontal`: seal and name side by side
- `stacked`: seal above the name
- `wordmark`: the name alone, without the seal

**Treatments:**

| Treatment | Background | Colours |
|---|---|---|
| `light` | light | emerald `#146B50`, gold `#B79A58`, ink `#202522` |
| `dark` | `#022217` | emerald `#4FA082`, gold `#C7AD74` |
| `emerald` | `#146B50` | marble `#FAF9F5`, gold `#D9C69D` |
| `mono` | light | all ink `#202522` |
| `reversed` | dark | all marble `#FAF9F5` |

**Favicon (seal era):** a simplified ق seal, now replaced by the Kufic ق tile. The band text can't be read below about 64px, so small sizes use this instead. `apple-touch-icon.png` is 180×180.

## Rules

- **Minimum size:** use the full seal at 64px or larger. Below that, use the favicon ق seal.
- **Clear space:** keep a quarter of the seal's diameter clear on every side.
- **Fonts:** Aref Ruqaa (centre and Arabic name) and Readex Pro (band and English name), both OFL-licensed. Already outlined in the files.
- **Academies:** don't put this logo on academy-facing surfaces (dashboard, academy sites, academy emails). Those are white-label and show each academy's own logo.
