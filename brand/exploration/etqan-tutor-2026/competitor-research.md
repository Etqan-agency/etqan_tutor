# Competitor logo research — Etqan Tutor 2026

Research date: 2026-10-27. Method: each homepage was downloaded with `curl` (HTML only). The header logo SVG or image and the favicon were downloaded too, and the SVGs were rendered locally to look at them. No scripts from these sites were run.

**Labels:**
- **Verified** means it was seen in the fetched HTML, an inline SVG, an SVG file, or a favicon file. This includes hex values read from `fill=` or `<style>`, and shapes seen in a local render.
- **Assumption** means it was inferred, or comes from general knowledge, and was not confirmed in the fetched source.

"Primary colour" means the logo's fill colour unless noted otherwise.

---

## A. Category competitors (tutoring and academy management, course platforms)

### 1. TutorBird
- **Source:** https://www.tutorbird.com/ — logo `wp-content/uploads/2023/07/TutorBird-Logo.svg`
- **Architecture:** symbol plus wordmark (combination). **Verified**
- **Symbol:** a bird head (toucan or parrot style) inside a dark circle, with a large yellow and orange beak. It sits up against the "T". **Verified** (render)
- **Wordmark:** "TutorBird" in camel case. A heavy, slightly slanted humanist sans, with a separate orange period after it. **Verified** (render). The site font is Poppins, loaded from Google Fonts (**Verified**). Whether the wordmark is set in Poppins is an **Assumption**: it looks more like a custom or rounded humanist face.
- **Colours** (from the SVG): `#333333` for text, `#FFCC33` and `#FF9933` for the beak and dot. **Verified**. `meta theme-color #f3a226`. **Verified**
- **Favicon:** the bird head alone, on a teal circular ground (48 px PNG). **Verified**
- **Header:** an `<img class="is-logo-image">` in a WordPress header. **Verified**

### 2. TutorCruncher
- **Source:** https://tutorcruncher.com/ — inline `<svg>` in `header_logo` (225×36). JSON-LD also points to `/logo_full.png`.
- **Architecture:** symbol plus wordmark. **Verified**
- **Symbol:** a small dinosaur (T-rex) silhouette in solid fill, placed to the left of the wordmark. **Verified** (render)
- **Wordmark:** "TutorCruncher" in camel case. A regular-weight neo-grotesque sans (Inter- or Roboto-like), not bold. **Verified** (render). The exact typeface is an **Assumption**.
- **Colours:** the logo fill is `#1F374E` (dark navy). **Verified**. The page also uses `#362E83` (indigo) heavily and `#FFFDF6` (cream). **Verified** (HTML)
- **Favicon:** `/favicon.ico`. Its contents were not inspected. The dinosaur is an **Assumption**.
- **Header:** inline SVG React component (`LogoSvg`). **Verified**

### 3. Teachworks
- **Source:** https://teachworks.com/ — `teachworks-white.svg`, favicon `…_tw.png`
- **Architecture:** wordmark only, with a separate "tw" monogram for the favicon. **Verified**
- **Wordmark:** "teachworks." in all lowercase. A bold humanist sans (Open Sans / Segoe-like) ending in a period. **Verified** (render). The typeface is an **Assumption**.
- **Colours:** the header file is white (`#fff`) for use on dark or photo backgrounds. **Verified**. The brand accent colour was not found in the static HTML. **Assumption:** blue or teal.
- **Favicon:** a black circle with a white lowercase "tw". **Verified**
- **Header:** `<img>` (Webflow). **Verified**

### 4. LearnWorlds
- **Source:** https://www.learnworlds.com/ — `assets/images/logo.svg`
- **Architecture:** symbol plus wordmark. **Verified**
- **Symbol:** a square rotated 45° (a diamond) with a thick rounded outline. Inside it, two interlocking stroke shapes read as "L" and "W". A geometric monogram in a container. **Verified** (render)
- **Wordmark:** "LearnWorlds" in camel case with a weight contrast: "Learn" is bold and "Worlds" is regular. Geometric sans. **Verified** (render)
- **Colours:** the logo is black. **Verified**. The page uses `#029C91` (teal) and `#E1F7F5`. **Verified** (HTML). The Safari mask colour is `#5bbad5`. **Verified**, but this is the default value from favicon generators.
- **Favicon:** the diamond monogram alone, black. **Verified**
- **Header:** `<img>`. **Verified**

### 5. Thinkific
- **Source:** https://www.thinkific.com/ — `themes/thinkific/assets/images/logo-dark.svg`
- **Architecture:** symbol plus wordmark. **Verified**
- **Symbol:** a horizontal rounded bar above a dot, forming an abstract "T" or a person-like glyph. **Verified** (render)
- **Wordmark:** "THINKIFIC" in all caps. A geometric sans at medium-bold weight with wide tracking. **Verified** (render)
- **Colours:** the logo is `#271526` (deep aubergine, close to black). **Verified**. The page uses `#716A5C` (warm grey), `#F3F1EC` (warm off-white) and `#FCCC18` (yellow). **Verified** (HTML)
  - **Note:** Thinkific already uses a warm off-white ground, close to Etqan's marble.
- **Favicon:** not in the static `<head>`. Its contents are an **Assumption**.
- **Header:** `<img>` in `.logo-wrapper`. **Verified**

### 6. Teachable
- **Source:** https://www.teachable.com/ — `teachable-logo-color.svg`, plus `teachable-logo-light.svg` in the footer
- **Architecture:** wordmark only. A separate glyph is used for the favicon. **Verified**
- **Wordmark:** "teachable" in all lowercase. A custom rounded geometric sans, heavy, with circular bowls. **Verified** (render)
- **Colours:** `#e6ff32` (acid chartreuse). **Verified** (SVG `<style>`). It is used on dark backgrounds.
- **Favicon:** a chartreuse circle with a dark glyph that looks like a looped "t". **Verified** (32 px PNG). The glyph reading is an **Assumption**.
- **Header:** `<img class="nav_brand-image">`. **Verified**

### 7. Kajabi
- **Source:** https://kajabi.com/ — `Kajabi Dark Logo.svg`
- **Architecture:** symbol plus wordmark. **Verified**
- **Symbol:** a black square tile with a "K" made of folded planes, using grey linear gradients that look like paper folds. **Verified** (render, three `linearGradient` fills)
- **Wordmark:** "kajabi" in all lowercase. A neutral grotesque at medium weight. **Verified** (render)
- **Colours:** `#231F20` (logo). The page uses `#1F1F1E`, `#0A0A0A`, and warm greys `#949189` and `#D4D3CE`. **Verified**. Kajabi has moved to a near-monochrome, warm-neutral brand.
- **Favicon:** the K tile alone. **Verified**
- **Header:** `<img>` (Webflow). **Verified**

### 8. Wise (wiseapp.live)
- **Source:** https://www.wiseapp.live/ — `wise-logo-white.svg`
- **Architecture:** symbol plus wordmark plus tagline lockup. **Verified**
- **Symbol:** a pictogram of a teacher (an orange dot over a trapezoid "desk/body") above three student dots. **Verified** (render)
- **Wordmark:** "wise" in lowercase. A heavy rounded geometric sans, with an all-caps tracked tagline "TUTORING SIMPLIFIED" underneath. **Verified**
- **Colours:** `#FF6833` orange, `#FFCE00` yellow, `#36CE74` green, `#924DFF` purple, with white text. **Verified**
- **Favicon:** the pictogram on a dark indigo circle. **Verified** (72 px PNG)
- **Header:** `<img class="wise-logo-hero">`. **Verified**

### 9. Oases Online
- **Source:** https://oasesonline.com/ — `OOLogoHorizontal-scaled-1-1024x173.jpg`
- **Architecture:** symbol plus wordmark. **Verified**
- **Symbol:** two overlapping rings, interlocked like a loop or infinity, in a blue-to-violet gradient. **Verified** (render)
- **Wordmark:** "OASESONLINE" in all caps. A geometric sans, two-tone: "OASES" in dark grey, "ONLINE" in blue. **Verified**
- **Colours:** the page uses `#4F6DF5` (blue, 47 uses), `#1F1F1F` and `#FF5757`. **Verified** (HTML)
- **Favicon:** the ring symbol alone. **Verified**
- **Header:** a raster JPG logo, which suggests low brand craft. **Verified**

### 10. MyTutor (UK marketplace, adjacent)
- **Source:** https://www.mytutor.co.uk/ — `/mt-assets/favicon-64x64.svg`
- **Architecture:** monogram favicon ("M" in a square). **Verified**. The header is rendered client-side and was not in the static HTML, so the full lockup is an **Assumption**.
- **Colours:** `#00CBBA` (teal) square, `#232323` "M". **Verified**

### 11. TutorHamster (named by the owner)
- **Not verified.**
  - `https://tutorhamster.com` and `www.` both returned Cloudflare "Error code: 525" (SSL handshake failed). The domain resolves, but no site could be loaded.
  - Two web searches ("TutorHamster tutoring software" and "tutor hamster"/"tutorhamster" app) found no product by that name, only unrelated hamster pet games.
  - It may be defunct, regional, or spelled differently. Ask the owner for a URL.

---

## B. SaaS logo-system references

### Linear — https://linear.app/
- **Symbol plus wordmark:**
  - The symbol is a circle cut by four parallel diagonal lines, so it reads as a sphere with motion stripes. **Verified** (inline SVG, `fill="currentColor"`)
  - The wordmark "Linear" is in title case, a medium-weight grotesque. **Verified**
- **Colour:** monochrome. `theme-color #08090a`. **Verified**
- **Favicon:** the symbol in white on a black rounded square (`favicon.svg`, `rx=2`). **Verified**
- **Lesson:** a single-colour mark that inherits `currentColor` and works in light and dark mode with no variants.

### Stripe — https://stripe.com/
- **Wordmark:** "stripe" in lowercase, a custom bold sans. The header SVG uses `fill="var(--hds-color-text-solid)"` with a `#031323` fallback. **Verified**
- **Favicon:** a white slanted parallelogram on `#533AFD` (blurple) in a square with `rx=64` on a 512 canvas. **Verified**
- **Lesson:** the homepage image alt texts describe crosswalks and windows "forming Stripe's parallelogram logo" (**Verified**). A simple geometric primitive becomes a system-wide motif.

### Notion — https://www.notion.com/
- The header has an inline 33×34 SVG symbol with `fill: var(--notion-logo-fill, var(--tatami-color-black))`. **Verified**
- The symbol is the "N" in an outlined, slightly 3D square, in black and white. **Assumption** (local render failed because of the CSS variable fill)
- **Lesson:** a mark driven by tokens, monochrome, with a hand-drawn character.

### Asana — https://asana.com/
- **Symbol plus wordmark:** three coral dots in a triangle, plus "asana" in lowercase geometric sans. **Verified** (inline SVG)
- **Colours:** dots `#F06A6A`, text `#0D0E10`, `theme-color #2e3c54`. **Verified**
- **Favicon:** the three dots alone, as PNGs from 57 to 180 px. **Verified**
- **Lesson:** a symbol built from primitives that survives at 16 px.

---

## C. Patterns & whitespace

### What is overused in this category
1. **Literal mascots and animals.** TutorBird (bird), TutorCruncher (dinosaur), the possible TutorHamster, and the owl or graduation-cap clichés from the wider ed-tech market. They read as friendly but small-business and B2C, not as an institutional platform.
2. **Lowercase rounded geometric wordmarks.** Teachable, Wise, Kajabi, Teachworks, Stripe and Asana all use them. Lowercase is now the default "friendly SaaS" register.
3. **Saturated "tech" colour.**
   - Blue or violet: Oases `#4F6DF5`, TutorCruncher `#362E83`, Stripe `#533AFD`.
   - Teal or turquoise: LearnWorlds `#029C91`, MyTutor `#00CBBA`, TutorBird's favicon ground.
   - Acid or neon: Teachable `#e6ff32`.
   - Multi-colour dots: Wise.
   - Nobody uses deep green, and nobody uses gold or brass.
4. **Trailing-period wordmarks.** TutorBird and Teachworks both do it. It already feels like a sub-category cliché.
5. **"People" pictograms built from dots and bars.** Thinkific (bar over dot) and Wise (teacher plus students as dots). Expect "teacher plus learners" glyphs to look generic.
6. **Interlocking or overlapping rings and loops.** Oases is the clearest example.
7. **Gradients in the mark.** Kajabi and Oases. These are weak at 16 px and in single-colour reproduction.
8. **Raster or white-only header logos.** Oases uses a JPG and Teachworks a white-only SVG. Craft is uneven, so a crisp, tokenised SVG system is itself a differentiator.
9. **Not seen in the fetched marks, but common in the wider category:** books, caps, owls, pencils, light bulbs and speech bubbles. Avoid them per the logo-design skill guidance.

### Where the market is moving
- **Toward warm neutrals and monochrome.** Kajabi (warm greys `#D4D3CE` and `#949189`) and Thinkific (`#F3F1EC` off-white with `#271526` aubergine). A warm-paper ground on its own is therefore not distinctive. The emerald plus gold pairing must carry the difference.

### Whitespace for Etqan Tutor
- **Colour:** no verified competitor uses deep green or gold.
  - An emerald `#146B50` mark with a restrained gold `#B79A58` accent sits in empty colour space.
  - It also signals the "established institution or academy" register rather than "consumer app".
  - Gold should stay an accent, never the only carrier of meaning. It is low contrast on marble, so the mark must work in one colour.
- **Bilingual identity:** no competitor shows an Arabic or bilingual mark. Teachworks claims 45 languages, but the mark is Latin only.
  - A lockup designed for both scripts from day one would be a genuine differentiator for the MENA academy market. That means Arabic "إتقان" and Latin "Etqan" with matched x-height or baseline logic and a mirrored RTL lockup.
- **Register:** the category splits between playful mascots and neutral-tech lowercase.
  - A calm, geometric but not cute symbol would be unoccupied ground. Examples are a construction from the letter ت/E, or a pattern-derived Islamic-geometry primitive kept very simple.
  - A wordmark with real typographic craft (a serif display or a carefully drawn sans in title case) would also stand out.
- **System thinking:** the strongest references (Stripe, Linear, Asana) own one primitive that becomes a motif. Few tutoring competitors do this.
  - An Etqan primitive could scale into patterns, academy-tenant badges and app icons. Examples are a precise "mastery" step or angle, or an 8-fold geometric unit.
- **Multi-tenant fit:** academies will put their own logos on top of Etqan. A mark that is quiet, single-colour and comfortable at 16–24 px matters more for a "powered by" footprint than a loud mascot does.
- **Caution:** the brand-identity skill (see `skills-review.md`) flags cream grounds, gold accents, Fraunces display and Inter body as common AI-generated defaults. The Etqan palette and fonts overlap with that list, so differentiation must come from the mark's form and the bilingual system, not from palette and type alone. The rationale for each choice should be written down from the brief: Etqan means "mastery/precision", and the palette has a heritage reading.
