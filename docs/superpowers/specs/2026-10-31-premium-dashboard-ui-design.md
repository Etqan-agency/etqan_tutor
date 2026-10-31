# Premium dashboard UI — design spec (checkpoint 1)

Date: 2026-10-31. Audit: `2026-10-31-premium-dashboard-ui-audit.md`. Inspiration board:
`assets/2026-10-31-dashboard-inspiration.md`. Scope: `dashboard/` (plus the additive backend flag
and tokens v0.4.0 it needs).

## 1. Direction — "The Gateway"

The gates of Masjid al-Haram, translated for a working tool:
- **Frame, not decoration.** The arch frames the page; it never decorates a component.
- **Gold as a rule, not a fill.** Gold appears as hairlines, the lozenge keystone, and the active
  bar. It is never a background behind text.
- **Calm density.** Smaller type, quiet labels, and large tabular figures only where a number is
  the point.

## 2. Theme resolution

```
@etqan/tokens v0.4.0 (Etqan premium default)      data-brand="etqan" → arch on
  └ named palette (user; `themes` feature)       neutrals only
     └ academy colours if Branding.colors_customized   data-brand="academy" → arch off
        └ an invalid or missing value → that variable keeps the token default
```

- The flag is `site.Branding.colors_customized`, default False (migration `academy_site` 0009).
- It is written only from Website → Branding ("Etqan theme" / "Your own colours"). Stored colours
  are kept when the academy switches back.
- The academy's name, logo and favicon are always its own (white-label).
- First paint: `index.html` reads `localStorage["etqan-brand"]`, which is per origin and therefore
  per academy, and re-validates every value as `#RRGGBB`. Known limit: on a device that has never
  loaded a customized academy, its first paint is Etqan's until branding loads (server-inlined
  branding would remove that; not in this checkpoint).
- `BrandProvider` does not clear the variables while branding loads, so a customized academy never
  flashes Etqan's colours.

## 3. Tokens (v0.4.0)

| Role | Light | Note |
|---|---|---|
| background | `#FAF9F5` | `sand.50`, the approved warm white |
| foreground / card-fg / popover-fg | `#202522` | new `charcoal` primitive |
| primary | `#146A51` | unchanged; same as `#146B50` |
| accent | `#B79A58` | `gold.500`; badge text 6.34:1 |

- Dark mode is unchanged.
- The contrast gate passes: 56 pairs, 0 failures.

## 4. Type (dashboard-local density, `src/index.css`)

| Rank | EN | AR | Use |
|---|---|---|---|
| xs | 12px | 13px | secondary labels, table headers |
| sm | 13px | **14px** | body, table cells (Arabic floor, owner) |
| base | 15px | 15px | |
| lg / xl / 2xl | 16 / 19 / 22px | same | |
| display | 26px | 26px | page titles (Fraunces) |

Marketing keeps the package sizes.

## 5. Ornament rules

- **Arch** (`ui/arch-backdrop.tsx`, mask from `scripts/derive-arch-mask.py`):
  - painted with `--accent` through a CSS mask;
  - top of the content column only, fading out by 50% of its height;
  - on phones the whole arch spans the width; from 40rem it keeps its proportions and crops the
    sides;
  - opacity 0.35 in light and 0.30 in dark. This is the contrast ceiling: muted text and links over
    the strongest line still clear 4.5:1 (measured 4.61–5.54:1).
  - Dense routes (`staticData.ornament: "quiet"`: students, invoices) get a 22rem arch at 0.20
    light / 0.14 dark.
  - Signed-out pages frame the card from below the header at 0.70 light / 0.50 dark. No text sits
    on it there; the card is opaque.
  - Hidden in print, forced-colors, and academy themes.
- Tables are opaque (`--card`) so rows never sit on the line-work.
- **Page rule:** a 2.5rem, 2px line plus the lozenge directly under every `PageHeader` title, before the description.
- **Sidebar brand hairline:** a gold gradient rule under the academy name.
- **Auth card crown:** a 3px gold gradient on the top edge.
- **Empty state:** the icon sits in a small arch (rounded-top frame, accent hairline).

## 6. Shell

- **Sidebar:** full height and sticky, on a card surface.
  - The brand block heads it and links home.
  - Group labels are 12px semibold, uppercase in LTR only.
  - Items keep a 44px minimum target.
  - The active item gets an `primary/8` wash, `primary-text`, and a 3px gold bar flush with the
    start edge.
- **Topbar:** 64px, sticky, translucent with a backdrop blur. It carries the controls only; the
  wordmark appears there only between `sm` and `md`.
- **Mobile:** an 18rem drawer on a card surface, with the brand at its head.

## 7. Components touched

- `PageHeader`: an `actions` slot, the rule, and `text-balance`.
- `StatCard` / `Stat`: new. One summary shape for the overview, with tabular 24px figures (a second
  currency steps down to 15px) and divided cells. Its header is `CardHeader`'s recipe (24px top,
  16px under the rule, the display face at `text-lg`).
- Ornament colour `--ornament`: the accent in Etqan's theme; the academy's primary in its theme.
  In dark mode on a customized academy, links, ornaments and the focus ring use the primary mixed
  35% into the body text colour, which keeps the hue and clears contrast. The light focus ring
  follows a primary that reads on white.
- Arabic titles use IBM Plex Sans Arabic (Fraunces has no Arabic glyphs).
- `EmptyState`: the arch frame, and a display-face title.
- `PageContainer`: a `quiet` prop.
- `AuthLayout`: the arch frame and a centred card with the crown.
- Tables: base-layer defaults for every table in the app (12–13px semibold headers, tabular
  figures, row hover). Their own utilities still win.

## 8. Not in checkpoint 1 (next batches)

- Breadcrumbs and a ⌘K jump.
- A parent child-switcher and a bottom bar for families.
- Status dots.
- Filter chips.
- Skeleton rows.
- Migrating the ~50 tables to a shared component.
- Feature-area pages.
- Re-pinning marketing to v0.4.0.
- Moving marketing to `colors_customized`.
