# Premium dashboard UI — Phase 1 audit (theme architecture and customization)

Date: 2026-10-31. Scope: `dashboard/` only. Status: audit done; nothing changed in code.

## 1. How the dashboard is themed today

Four layers stack, in this order (later wins):

| # | Layer | Where | What it sets | Persisted in |
|---|---|---|---|---|
| 1 | Etqan tokens | `@etqan/tokens` v0.3.0 (`tokens/src/*.tokens.json` → `tokens.css`, `theme.css`), imported by `src/index.css` | Every semantic colour (shadcn contract + `primary-text`, `success`, `warning`, `info`, `overlay`), light and `.dark`; type, radius, spacing, motion, elevation | Git tag, pinned in `dashboard/package.json` |
| 2 | Light/dark | `src/lib/theme.tsx` + pre-paint script in `index.html` | `.dark` on `<html>` | `localStorage["etqan-theme"]`, else `prefers-color-scheme` |
| 3 | Named palette | `src/features/appearance/palette{,s}.ts(x)` | `data-theme` + one `<style id="etqan-palette">` replacing the **neutral** tokens (surfaces, borders, muted, status). Options: default, dracula (dark-only, forces `.dark`), nord, sunset | `localStorage["etqan-palette"]`, per browser; honoured only when the academy's `themes` feature is on and `me/` is cached |
| 4 | Academy branding | `src/features/branding/{apply.ts,BrandProvider.tsx}` | Inline `--primary`, `--primary-foreground`, `--accent`, derived `--accent-foreground`; light-only `--primary-text` via `<style id="academy-primary-text">`; favicon; `data-academy-name`; page title; logo in the wordmark | Backend `site.Branding` (one row per academy schema), read from `GET /api/v1/site/branding/` |

Branding never touches dark mode's `--primary-text`, never writes neutrals, and re-validates
every value as `#RRGGBB` before it reaches the DOM. Named palettes never write brand tokens.
The two layers are therefore orthogonal: an academy owns its brand hue; a user (when allowed)
owns the neutral palette and light/dark.

## 2. Customization capability inventory

| Kind | Supported? | Detail |
|---|---|---|
| Brand customization | **Yes** | Name (ar/en), tagline, logo, favicon, share image, primary colour, accent colour (Website → Branding, `BrandingForm.tsx`). `primary_text` is derived server-side (`site/colors.py::text_color_for`, AA 4.5:1, rejects unusable colours). |
| Theme customization | **Partial, per user** | Light/dark per browser. Four named neutral palettes per browser, gated by the per-academy `themes` feature (Etqan switches it on). The academy cannot pick a palette for its users, and cannot set any neutral or status colour. |
| Component customization | **No** | No per-academy radius, density, type or component variants. |
| Layout customization | **No** | One shell; nav is driven by permissions and feature switches only. |
| Full custom UI | **No** | No plugin or component loading. Not proposed (out of scope). |

## 3. Initialization and failure behaviour

- First paint: tokens CSS + `.dark` from the pre-paint script. Title = hostname, favicon empty
  (white-label: never Etqan's name or icon on an academy host).
- Then `site/branding/` loads (React Query, `staleTime` 60 s, `retry: false`) and the brand
  vars are written. **Until then the page shows Etqan's emerald and gold**, so a customized
  academy sees a brief flash of the Etqan hue on every cold load.
- Branding request fails → `data` undefined → `applyBranding(undefined)` clears the vars →
  Etqan token defaults. Safe.
- Invalid colour in the payload → that var is removed → token default for that var only.
  Safe and already partial-aware.
- Accent too dark/light for either text colour → token `--accent-foreground` kept.

## 4. Tenant isolation

Each academy is its own host (`<sub>.<base>` or a custom domain), so `localStorage`, the
React Query cache, cookies and inline styles are all per origin. There is no in-app academy
switcher; changing academy is a full navigation to another origin. Cross-tenant theme leakage
is structurally impossible today, and nothing in this refactor should add a shared origin.

## 5. Finding that blocks "Etqan premium is the default" (Scenario A)

`site.Branding` is created for every new academy (`site/services.py:80`) with the model
defaults `primary_color="#0E7C66"`, `accent_color="#C8962E"` — the old Kaleem teal and a
saturated amber. The API always returns them, and `applyBranding` always applies them.

So **no academy ever sees the Etqan default emerald `#146A51` or gold `#A88A3C`** once signed
in: an uncustomized academy is painted Kaleem teal/amber, and the dashboard cannot tell "never
customized" from "deliberately chose these". Fixing the default therefore needs a way to know
whether the academy set its colours (decision D1).

## 6. Palette: brief vs the shared token package

| Role | Brief | `@etqan/tokens` v0.3.0 (light) | Official site / K2 logo |
|---|---|---|---|
| Emerald | `#146B50` | `#146A51` (`primary`) | `#146B50` |
| Warm white | `#FAF9F5` | `#FBF5EB` (`background`, cream) | `#FAF9F5` |
| Gold | `#B79A58` | `#A88A3C` (`accent`) | `#B79A58` |
| Charcoal | `#202522` | `#191C1B`-family ink (`foreground` ink.950) | `#202522` |

Emerald is the same colour. Background, gold and ink differ visibly. The tokens package is
also consumed by every academy's **marketing** site, so changing a token value changes those
sites too (decision D2). `brand/design.md` still describes the Kaleem palette and is stale.

Academy surfaces stay white-label by an earlier owner decision: the K2 Ruqaa Seal logo goes on
Etqan's own surfaces (official site), not inside an academy's dashboard.

## 7. What is already in good shape

- `scripts/check-colors.mjs` (part of `pnpm lint`) bans hex literals and Tailwind palette
  utilities in source and in the built CSS: components already consume semantic tokens only.
- Contrast is gated in the tokens package (`contrast-pairs.json`, ADR-0040/0041) and named
  palettes are asserted against the same manifest (`palettes.test.ts`).
- Reduced motion has a global backstop; RTL font switch is in `index.css`.
- Size: 174 authed route files, 37 feature folders, ~80k lines of non-test TSX; shared UI in
  `src/ui/` (about 30 primitives), shell in `src/features/shell/`.

## 8. Proposed resolution model (to confirm)

```
tokens (Etqan premium default, light + dark)
  └─ named palette (user, if `themes` is on)       → neutrals only
       └─ academy brand (only if customized)        → primary, accent (+ derived fg)
            └─ invalid/missing value → that var falls back to the token default
```

The default becomes "the tokens, untouched". Branding is applied only when the academy has
actually customized it; any missing or invalid value already falls back per variable.

## 9. Open decisions (owner)

- **D1 — detecting "customized".** (a) Dashboard-only: treat the untouched model defaults
  (`#0E7C66` + `#C8962E`) as "not customized". No backend change; an academy that typed
  exactly those values gets the Etqan emerald instead. (b) Additive backend field
  `colors_customized` (default False; set True when an admin saves a colour; a data migration
  sets True where the stored colours differ from the defaults), exposed on `site/branding/`.
  Exact, but a migration and an API addition.
- **D2 — palette values.** Keep `@etqan/tokens` as is, or cut v0.4.0 moving background, accent
  and ink to the brief's values (affects academy marketing sites; needs the contrast gate).
- **D3 — branch base.** New branch `feat/premium-dashboard-ui` cut from `qa/manual-round-2`
  (stacked on open PRs #62/#63) or from `main`.
- **D4 — scope per checkpoint.** The full refactor touches ~174 routes. Proposed checkpoints:
  (1) theme foundation + shared components + shell + one screen per role, with screenshots;
  (2) feature areas in batches; (3) role portals and final QA.

## 10. Owner decisions (2026-10-31)

- D1 → (b) additive backend field `colors_customized`, with a data migration.
- D2 → cut `@etqan/tokens` v0.4.0 with the brief's background, gold and ink, behind the contrast gate.
- D3 → branch `feat/premium-dashboard-ui` from `qa/manual-round-2` in dashboard and backend;
  `feat/v0.4-premium-palette` in tokens.
- D4 → checkpoint 1 = design spec and inspiration board, theme foundation, shared components,
  shell, one key screen per role, and default-vs-custom screenshots in AR and EN. Then stop.
