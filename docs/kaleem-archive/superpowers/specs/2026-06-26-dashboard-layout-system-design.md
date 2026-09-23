# Dashboard layout system — design

- **Date:** 2026-06-26
- **Status:** Approved (autonomous execution authorized by user 2026-06-26; deadline-driven)
- **Repos:** `dashboard` (primary). Token promotion to `tokens` deferred — see Deviation.
- **Driver:** UI/UX audit of the authenticated dashboard. User reported a visible
  "huge layout sizing problem." Audit confirmed a structural cause, not a per-page bug.

## Problem

The app shell ([`AppShell.tsx`](../../../dashboard/src/features/shell/AppShell.tsx)) renders the
content region as `<main className="min-w-0 p-4">` — **no max-width, no centering, no shared
container**. Width discipline is therefore delegated to each page, and the pages disagree:

| Page | Wrapper today | Effective width |
| --- | --- | --- |
| Home | `mx-auto max-w-2xl` | 672px |
| Account | `mx-auto max-w-md` | 448px |
| Family | `mx-auto max-w-md` | 448px |
| Availability | `mx-auto max-w-2xl` **+ extra `p-4`** | 672px, double padding |
| Billing/Schedule/Curriculum/Assessments/Messages/Insights | `mx-auto max-w-3xl` | 768px |

Consequences, confirmed in the browser at 1440px (see `assets/2026-06-26-dashboard-layout/`):

1. **Width jumps + position shifts** when navigating (448 → 672 → 768). The content column
   visibly resizes and moves between pages. This is the jarring effect the user's eye caught.
2. **Content drifts right into a void.** `mx-auto` centers *within `<main>`*, which begins after
   the 256px sidebar. A narrow 448px column floats with a ~360px empty band between the sidebar
   and the content — it reads as "lost content / broken layout."
3. **Edge-to-edge is structural risk.** Width lives per-page, so any page that omits the wrapper
   stretches full width with unbounded line length (violates the Container Width guideline).
4. **No spacing/width token** exists. Every width above is a magic number, so drift is inevitable.

Secondary findings (the "follow global standards" part):

- **Inconsistent heading hierarchy.** Home & Family have an `<h1>`; **Account has none** (jumps
  straight into a Card); placeholders have `h1 + description`. No shared page-header convention.
- **Sidebar nav touch targets** (`px-3 py-2 text-sm` ≈ 36px) are under the 44px minimum — matters
  in the mobile drawer where they are touch targets.
- **No vertical spacing rhythm** — pages mix `gap-4` / `gap-6` / `gap-4 p-4` ad hoc.
- **Mobile topbar horizontal overflow** (found during the visual run): at 375px the topbar's
  right cluster (locale + theme + the user-name button) forced the document to ~480px → a
  horizontal scrollbar and clipped page content. Pre-existing (topbar unchanged by this work), but
  it is a layout-sizing finding, so it is fixed here: the username text hides below the `sm`
  breakpoint (avatar + chevron remain; `aria-label` keeps it accessible).

## Goals

- One canonical, centered content container owned by the shell. Consistent width + padding across
  every authed page. No per-page width drift; no edge-to-edge risk.
- A standard page-header pattern (`<h1>` + optional description) so every page has a correct,
  consistent heading.
- Codify width + spacing as **tokens** (Tailwind v4 `@theme`), not magic numbers.
- Fix the related standards findings (double padding, nav touch targets).
- Verify visually (before/after at 1440 / 768 / 375) and keep mobile/RTL/dark intact.

## Non-goals (YAGNI)

- No redesign of the Serene Scholar visual language (colors, type, components stay).
- No multi-column / data-dense dashboard layout. Calm single column stays; a `wide` variant is the
  only escape hatch (for the availability grid now; schedule/insights later).
- No backend changes. No new pages.

## Design

### 1. Layout tokens (Tailwind v4 `@theme`, in `dashboard/src/index.css`)

Add a named content-width scale + page padding as design tokens so the container references names,
never pixels:

```css
@theme {
  --container-page:   48rem;  /* 768px — standard authed page (default) */
  --container-narrow: 28rem;  /* 448px — focused/auth + simple confirmations */
  --container-wide:   72rem;  /* 1152px — data-rich (availability grid; future schedule/insights) */
}
```

These generate `max-w-page` / `max-w-narrow` / `max-w-wide` utilities. Page horizontal padding is
standardized at `px-4 sm:px-6` (a 16→24px rhythm already in use).

> **Why three, not one:** consistency is the win, so 7 of 9 pages collapse onto the single `page`
> width. `narrow` and `wide` are *semantic* opt-ins (not per-page whims) — focused flows and
> data-rich grids respectively. This is the one centralized escape hatch.

### 2. `PageContainer` component (`dashboard/src/ui/page-container.tsx`)

```tsx
type Width = "page" | "narrow" | "wide";
<PageContainer width="page">…</PageContainer>
```

- Centers content (`mx-auto`), applies the chosen `max-w-*` token + `w-full` + `px-4 sm:px-6` +
  a consistent vertical stack (`flex flex-col gap-6`).
- Defaults to `width="page"`. This is the single source of width/padding for authed pages.

### 3. `PageHeader` component (`dashboard/src/ui/page-header.tsx`)

- Renders `<h1 className="font-display text-2xl font-semibold">{title}</h1>` + optional muted
  `<p>` description. One heading pattern everywhere → fixes Account's missing `<h1>`.

### 4. Shell owns the container

`AppShell`'s `<main>` keeps only structural padding/scroll concerns; the **page content gets wrapped
in `PageContainer` at the page level** (so each page picks its width semantically) while the shell
guarantees the outer `<main>` no longer fights it. Specifically: `<main className="min-w-0 py-6">`
(vertical padding only; horizontal padding + max-width + centering move into `PageContainer`).

### 5. Per-page migration

Replace every ad-hoc `mx-auto max-w-* … p-*` wrapper with `PageContainer` (+ `PageHeader` where a
heading exists):

- Home → `PageContainer` (page) + `PageHeader`.
- Account → `PageContainer` (page) + add the missing `PageHeader`.
- Family → `PageContainer` (page) + `PageHeader`.
- Availability → `PageContainer` (**wide**); delete the extra `p-4` (double padding fix).
- `ModulePlaceholder` → built on `PageContainer` (page) + `PageHeader` (billing/schedule/curriculum/
  assessments/messages/insights all inherit consistency automatically).
- `AuthLayout` (login/register/etc.) → align to `narrow` token for consistency (it already centers).

### 6. Nav touch targets

Sidebar links get `min-h-11` (44px) so the mobile drawer meets the touch-target minimum; desktop is
unaffected visually.

### 7. Mobile topbar overflow

`UserMenu`'s name span becomes `hidden sm:block` so the topbar fits within a 375px viewport (no
horizontal scroll). Verified by measuring `documentElement.scrollWidth` ≤ viewport at 375px.

## Deviation: token home (recorded, with rationale)

The user chose "token in the shared `@kaleem/tokens` package + shell component." During execution I
found `@kaleem/tokens` is consumed as a **pinned git tag baked into `node_modules`**
(`github:kaleem-lms/tokens#v0.1.1`). Changing it requires publish → re-pin → reinstall → Docker
rebuild, which (a) risks the running dev environment overnight and (b) **breaks live visual
verification** (the dashboard source is bind-mounted with HMR, but `node_modules` is a baked volume).

**Decision:** define the layout tokens in the dashboard's own `@theme` layer for this slice (real
tokens, real utilities, zero magic numbers, ships + verifies tonight). Promoting `--container-*` and
a spacing scale into the shared `tokens` package is a fast-follow logged in `ISSUES.md`, to ride the
next tokens version bump. This honors the intent (token-driven, single source) while respecting the
deadline and D10 (no cross-repo refactor sprees mid-feature).

## Testing (D3 — TDD, 100% line+branch)

- `page-container.test.tsx`: renders children; applies the correct `max-w-*` per `width`; defaults to
  `page`; centers + has page padding.
- `page-header.test.tsx`: renders an `<h1>` with the title; renders/omits the description.
- Update `AppShell.test.tsx` for the new `<main>` structure.
- Update each migrated route/`ModulePlaceholder` test to assert it renders inside a `PageContainer`
  (and Account now has an `<h1>`).
- `AppSidebar.test.tsx`: assert the 44px min-height class on links.
- `jest-axe` (existing `a11y.test.tsx`) stays green; heading-order improves.

## Verification (visual run — user-requested)

Before shots captured (1440px): home, account, billing, availability. After implementation, recapture
the same pages at 1440 / 768 / 375 and confirm: consistent width, no inter-page jump, no right-drift
void, mobile unchanged, RTL + dark intact. Store under `assets/2026-06-26-dashboard-layout/`.

**Result (done):** after-shots captured at 1440 (home/account/billing/availability), 768 and 375
(account). Confirmed: all standard pages now share the 768px `page` width (Account/Family went from
448px, Home from 672px) — no inter-page jump; the right-drift void is gone; Account gained its `<h1>`;
availability uses the `wide` width with the double padding removed; and the 375px overflow is gone
(`scrollWidth` 372 ≤ 375, zero offenders). Captured via the running dev container over HMR.

## Risks / rollback

- Low blast radius: presentational shell + page wrappers only; no data/logic/routes change.
- Fully reversible (revert the dashboard feature branch).
- If `page` (768px) still feels void-y at ultra-wide in after-shots, tune `--container-page` up; the
  token makes that a one-line change.
