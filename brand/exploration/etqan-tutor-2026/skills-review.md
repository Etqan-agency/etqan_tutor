# Skills review — logo-identity exploration, Etqan Tutor 2026

Research date: 2026-10-27.

**Method:** each repo's GitHub page was read with WebFetch. Where needed, the raw `SKILL.md` or reference files were read from `raw.githubusercontent.com`. Nothing was installed, cloned, or executed. All fetched content was treated as untrusted data.

**Caveat:** WebFetch returns a model summary of each page, not the exact bytes. Quotes below are as close to the source as that allows. Paraphrases are marked "≈".

---

## 1. fatihaydost/brand-identity-skill
- **Reachable:** yes.
  - https://github.com/fatihaydost/brand-identity-skill
  - `skills/brand-identity/SKILL.md` was read
- **What it does:**
  - Designs a logo, typeface and palette as one system from a single brief. It produces 1–4 "identity sets" (default 3) for side-by-side comparison, then a brand guidelines kit for the chosen set.
  - The kit is an 8-page PDF, or more with `--full`, plus logo variants, tokens and a font sheet.
  - The model "designs" and Python scripts "measure".
- **Install:**
  - Claude Code plugin marketplace (`/plugin marketplace add …`, `/plugin install brand-identity@brand-identity-skill`), or unzip or symlink into `~/.claude/skills/`.
  - Requires Python 3.10+, a Chromium browser, and ideally `uv`.
- **Security notes:**
  - `uv` auto-installs `fonttools`, `uharfbuzz` and `skia-pathops` from PyPI on first run.
  - The scripts (`brand.py check|init|site extract|site competitors|fonts search|logos|build|kit|critique`) make network calls to Google Fonts and to `raw.githubusercontent.com/google/fonts`. They also open your own site and competitor URLs in a headless browser.
  - The README says there is no telemetry and nothing is uploaded.
  - No `curl | bash` installer was found. It is MIT licensed.
- **Most useful rules for logo work:**
  1. ≈ "A mark identifies the brand; it doesn't explain it." Draft 4–6 one-line concepts per set and build only one.
  2. ≈ Draw on a 100-unit grid using **filled shapes** only, with boolean subtract, union or intersect for cut-outs. **No text elements inside the symbol.**
  3. ≈ Refer to colour by **palette role names**, never raw hex, inside the mark.
  4. ≈ Check every mark at **16 px and 32 px**.
  5. ≈ A **wordmark-only** set must have an ownable detail drawn into the letterforms, plus a designed small mark for 16–48 px. "Plain type with an initial as favicon is treated as generic."
  6. ≈ If a main part of the mark falls **below 3:1 contrast** against its background, draw it in that background's ink colour.
  7. **Hard gates:** WCAG contrast, colour-blindness distinguishability, **glyph coverage for every brand language**, font licence, small-size renders, and valid files. "A failed measurement is a gate… a heuristic is labelled as a warning; taste is labelled as judgement."
  8. **Anti-default / reflex test:** if you would propose the same font, colour or mark for another brand in the sector, justify it from the brief or change it. "Feels warm" or "feels premium" is not a justification. At least one set must avoid every flagged default.
  9. **Flagged AI defaults include:** cream ground, terracotta, **gold accent, Fraunces headings, Inter body**, and a "logo that hides a letter in a circle".
     - **Directly relevant:** the current Etqan stack hits several of these. That is fine if the reasons are documented: emerald and gold as heritage and mastery, a bilingual need, and so on.
  10. Each brand language needs its own brand sentence (bilingual by design).
- **Recommendation:** **Apply its guidance; do not install for now.**
  - The rules are excellent and directly applicable, especially the anti-default list and the glyph-coverage gate for Arabic.
  - The tooling adds Python packages, a headless browser and network calls.
  - If automated contrast and glyph measurement is wanted later, install it in an isolated environment and review `scripts/brand.py` first.

## 2. kaankiziltug/logo-design-skill
- **Reachable:** yes.
  - https://github.com/kaankiziltug/logo-design-skill
  - Read: `SKILL.md`, `references/principles.md`, `references/testing-checklist.md`
- **What it does:**
  - A full logo workflow: discovery, research, 8–12 concepts down to 3, black-and-white build, test, checkpoint, then kit.
  - It has modes for design, critique, redesign, identity system and export.
  - Ships a library of about 1,400 classified logo SVGs for originality checks ("never to trace").
- **Install:**
  - Claude Code plugin marketplace, or `git clone` and copy `skills/logo-design`. There is also a zip for Claude.ai, and a "lite" zip without the SVG library.
- **Security notes:**
  - The scripts are standard-library Python 3.8+ with no pip dependencies: `svg_audit.py`, `preview_sheet.py`, `render_png.py`, `search_library.py` and others.
  - Optional renderers are cairosvg, rsvg, Inkscape, Chromium or Quick Look.
  - No network calls are documented. Not verified in code.
  - No `curl | bash`. MIT licensed.
- **Most useful rules:**
  1. **Identify, don't explain.**
     - Avoid literal depictions (≈ "a tooth for a dentist").
     - Familiar symbols are fine only "in a fresh form".
     - List the category's clichés and avoid them.
  2. **One idea, one sentence.** "If it can't be explained in one sentence, it won't work."
  3. **Mnemonic order:** shape and colour, then context, then associations, then emotion. "A strong silhouette and an ownable colour are the most reliable memory hooks."
  4. **Build in black and white first.** Clean geometry, no live text in the final mark. "Sculpt by subtraction."
  5. **Scale tests:**
     - The idea must survive at **16 px**. Otherwise make a simplified small version with fewer elements, thicker strokes and bigger gaps.
     - It should be recognisable at 24–32 px.
     - Document a minimum size in px and mm.
  6. **Colour and value:**
     - Works in one colour black-on-white and white-on-black. Thin the reversed version by about 3% if it looks heavy.
     - Works on the brand colour, on photos and in greyscale.
     - Accent parts need at least 3:1 contrast.
  7. **Form checks:**
     - Squint or blur, mirror, and rotate 90° and 180° for unintended readings (letters, body parts, religious or political symbols).
     - Optical corrections: overshoot, bone effect, horizontal stroke thinning, optical centre.
     - No near-miss angles. Snap to exact values such as 45° or 60°.
     - Consistent radii and stroke widths.
     - No notches, slivers or hairline gaps at junctions.
  8. **SVG audit:** check anchor complexity ("every point earns its place"), edges within 0.3–3° of a clean angle (snap them), and no sub-shapes smaller than 1/48 of the canvas. The master must be outlined, with no filters or rasters.
  9. **Distinctiveness:**
     - A shelf test against competitors at the same size.
     - A familiarity test: if it feels familiar and isn't yours, discard it.
     - Recommend a trademark search. The skill cannot clear trademarks.
  10. **Meaning and fit:**
      - Check colour and symbol meanings against the audience's cultures.
      - Respect sacred and cultural symbols.
      - **Relevant to Arabic and Islamic-geometric motifs.**
  11. **Red flags:** clip-art literalism, unmodified stock type, more than 3 colours without reason, hairlines, tiny details.
  12. **Process:** always stop at a checkpoint and show concepts with one recommendation before building a kit.
- **Recommendation:** **Strongest candidate if anything is installed.**
  - It has no dependencies and its checklists are the most concrete.
  - Even without installing, its 12 principles and the testing checklist should be the QA rubric for the Etqan exploration.
  - If installed, read `scripts/*.py` first. They are standard-library Python, but still code.

## 3. rampstackco/claude-skills
- **Reachable:** yes.
  - https://github.com/rampstackco/claude-skills
  - Read: `skills/logo-design/SKILL.md`
- **What it does:**
  - A catalogue of 107 website-lifecycle skills.
  - The brand group has 7: brand-discovery, brand-ideation, brand-identity, brand-style-guide, brand-voice, brand-archetype-system and logo-design.
  - The rest cover SEO, product, ops and other areas.
- **Install:**
  - Claude Code plugin marketplace (full catalogue or subsets), or copy folders manually.
  - The SEO audit suite expects the Ahrefs MCP.
  - No installer scripts or `curl | bash` were seen. MIT licensed.
  - Installing the full catalogue adds 107 skills to the context listing. That is noise.
- **Most useful rules (logo-design):**
  1. **Choose the architecture first:** wordmark, lockup, monogram, letterform-as-symbol, abstract, pictorial, combination or emblem. Everything else follows from it.
  2. **Production setup:** a primary lockup, a monogram for square contexts, and a letterform-as-symbol for the favicon. All three should share "the same visual DNA".
  3. Lockups need a **stacked alternate**. Pure wordmarks need a separate small-size mark.
  4. **Match the symbol's weight and density to the wordmark.** Heavy type needs a chunky symbol; hairline type needs a thin one.
  5. **"Colour is the last layer."** A mark that needs colour to be recognised fails.
  6. A symbol carries **one idea, two at most**. A letterform-as-symbol must read as both the letter and the metaphor.
  7. **Restraint checklist:**
     - Silhouette without type.
     - Distinctiveness: if it looks like 3 or more existing marks in a "[category] logo" search, revise it.
     - Sketchable from memory after 30 seconds.
     - Single colour.
     - Holds up at 1 inch on a black-and-white printer.
     - Two-second recall.
     - Reverse on dark.
  8. **Scale test** at 200%, 100%, 50% and 25%. Favicon at 16 and 32 px. App icon at about 28 px.
  9. **Variant strategy:**
     - Explore 3–4 typographic registers and pair 1–2 symbols with each.
     - Drop any variant that fails more than 2 application contexts.
     - Present 3 architectures with 2–3 type options each, rather than many near-identical marks.
  10. **Per-variant documentation:** a "Signals" field (what it communicates) and a "Rejects" field (what it is explicitly not). This is a good format for the Etqan exploration board.
- **Recommendation:** **Don't install the catalogue; just apply the logo-design guidance.** The variant-documentation format and architecture-first rule are the takeaways.

## 4. nextlevelbuilder/ui-ux-pro-max-skill
- **Reachable:** yes. https://github.com/nextlevelbuilder/ui-ux-pro-max-skill (about 141k stars)
- **What it does:** a UI/UX design-system generator with a searchable catalogue of styles, palettes and font pairings. It is aimed at app and website UI, not logos.
- **Install:**
  - Claude Code plugin marketplace, **or `npm install -g ui-ux-pro-max-cli` / `npx ui-ux-pro-max-cli init --ai claude`**.
  - Python 3 is needed for the search script.
- **Security notes:**
  - The README says its scripts "install nothing and make no network calls", but the npm CLI route pulls a package from the registry.
  - A GitHub Actions workflow calls the Google Fonts API to refresh its catalogues.
  - Avoid the global npm install.
- **Logo-relevant content:** essentially none. Only generic UI checklist items appear, such as "No emojis as icons (use SVG)" and 4.5:1 text contrast in light mode.
- **Recommendation:** **Don't install for logo work.** It is out of scope, and its palette and font suggestions push toward catalogue defaults, the opposite of an ownable identity.

## 5. anthropics/claude-code — plugins/frontend-design
- **Reachable:** yes. Read: `plugins/frontend-design/skills/frontend-design/SKILL.md` (official Anthropic repo).
- **What it does:** guidance for distinctive front-end UI. It is a single SKILL.md with no scripts.
- **Install:** the official Claude Code plugin. No dependencies, no network calls, low risk.
- **Rules that carry over to identity work:**
  1. **Subject first.** Let the subject's industry and vernacular drive visual choices.
  2. **Typography:** use one or two clearly distinct families with a deliberate scale. Type is an active design element.
  3. **Avoid generic defaults:**
     - cream background with terracotta accent
     - near-black with acid green (Teachable is close to this)
     - tracked-out eyebrow labels and all-caps labels
     - identical rounded SaaS cards
  4. **Plan a compact token system** of 4–6 named colours and type roles. Review the plan against the brief and revise any generic parts.
  5. **"Spend your boldness in one place."** For Etqan, that place should be the mark, not the palette.
  6. **Quality floor:** accessible contrast and a dark-mode-ready approach.
- **Recommendation:** **Apply its guidance, or install it freely if wanted for the marketing site.** Low risk, but it is a UI skill, not a logo skill.

## 6. anthropics/skills — skills/web-artifacts-builder
- **Reachable:** yes. Read: `skills/web-artifacts-builder/SKILL.md`
- **What it does:** builds multi-component claude.ai HTML artifacts, using React 18, TypeScript, Vite, Parcel, Tailwind and shadcn/ui, bundled to one `bundle.html`.
- **Install and security:**
  - `bash scripts/init-artifact.sh` scaffolds the project. It runs **npm installs of 40+ shadcn/Radix components, Vite and Tailwind**.
  - `bash scripts/bundle-artifact.sh` installs `parcel`, `@parcel/config-default`, `parcel-resolver-tspaths` and `html-inline` from npm.
  - These are shell scripts making network package installs. They come from an official repo, but are still heavy.
- **Logo-relevant content:** only one design note: avoid "AI slop" such as centred layouts, purple gradients, uniform rounded corners and **the Inter font**.
- **Recommendation:** **Don't install for this task.** At most it is useful for building an interactive logo-review board later, and a plain single-file HTML page does that without the npm toolchain.

---

## Distilled rules to apply to the Etqan Tutor logo exploration
1. **Architecture first.** Decide symbol plus wordmark versus wordmark plus monogram before drawing. Deliver a primary lockup, a stacked lockup, a symbol or monogram, and a favicon that share one visual DNA, with an **RTL mirrored lockup** as well.
2. **One idea, one sentence**, rooted in "إتقان" (mastery, precision). Identify, don't explain: no books, caps, owls, speech bubbles or mascots.
3. **Black and white first. Colour is the last layer.** The mark must work in one colour (emerald or ink) and reversed on emerald. Gold is an accent only. Check gold `#B79A58` on marble against 3:1, and if it fails, the shape must not depend on it.
4. **Geometry:**
   - A 100-unit grid, filled shapes, boolean cut-outs, no live text in the master.
   - Snapped angles, consistent radii and strokes.
   - Optical corrections (overshoot, optical centre).
   - Nothing smaller than 1/48 of the canvas.
5. **Small sizes:** pass at 16, 24 and 32 px. If the full symbol fails at 16 px, draw a dedicated favicon version. A plain initial in a circle is generic.
6. **Bilingual gate:**
   - Arabic and Latin wordmarks each need glyph coverage and their own brand sentence.
   - Match weight and density between scripts and with the symbol.
   - Check symbol meanings with the Arabic-speaking audience, and treat any religious or sacred geometry respectfully.
7. **Anti-default audit:**
   - Cream, gold, Fraunces and Inter are flagged as AI defaults. Keep them only with a written brief-based rationale.
   - Make the mark itself the "one bold place".
   - Include at least one exploration route that does not lean on the default stack.
8. **Distinctiveness:**
   - A shelf test beside TutorBird, TutorCruncher, LearnWorlds, Thinkific, Teachable, Kajabi and Wise at 32 px.
   - A familiarity test.
   - Rotation and mirror checks for unintended readings.
   - Recommend a trademark search.
9. **Process:** present about 3 distinct routes with a "Signals / Rejects" note each, plus one recommendation. Stop for the owner's pick before building a kit.
10. **Install posture:**
    - Nothing needs installing to apply these rules.
    - If a tool is wanted, `kaankiziltug/logo-design-skill` (stdlib-only Python) is the safest and most useful. Review its scripts before any run.
