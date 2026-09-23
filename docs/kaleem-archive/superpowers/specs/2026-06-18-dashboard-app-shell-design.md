---
name: dashboard-app-shell
phase: A
modules: [identity]
status: draft
created: 2026-06-18
closed: null
---

## Goal

Give the authenticated dashboard a persistent application shell — a slim topbar
plus a role-aware sidebar — that wraps every signed-in page. Today each
`/_authed/*` page hand-rolls its own navigation (the home page has inline
"Profile"/"Sign out" buttons, the profile page a lone "Home" button) and the
signed-in area has no theme or locale controls at all. The shell replaces that
ad-hoc chrome with one consistent layout that later identity features (email
management, children/invites, student onboarding) plug into without re-inventing
navigation.

This is **Spec 1 of 4** in the dashboard-completion roadmap (shell → email
management → children/invites → student onboarding). It owns the layout only; it
adds no new API calls beyond the `me`/`logout` the dashboard already uses.

## User flow

A signed-in user lands on any `/_authed/*` route and sees:

1. **Topbar** (full width): brand wordmark on the leading edge; on the trailing
   edge the locale toggle, theme toggle, and a user menu (their name/initial).
   On narrow screens a hamburger button appears on the leading edge to open the
   sidebar.
2. **Sidebar** (leading rail on `md`+): the section nav. At ship time that is
   **Home** and **Profile**; later specs append their own entries. The link for
   the current route is marked active (`aria-current="page"`). On screens below
   `md` the rail is hidden and opens as a slide-in drawer from the hamburger
   button; choosing a link or pressing `Escape` closes it.
3. **Main**: the page content (`<Outlet/>`), unchanged.
4. **User menu** (topbar): opens a dropdown with **Profile** (navigates to
   `/profile`) and **Sign out** (calls logout, then redirects to `/login`).

There is **no footer** in the authenticated app (deliberate — see Out of scope).

Error / edge cases:
- If `useMe()` has no data yet, the shell renders its frame with a neutral
  placeholder for the user name (it never blocks on the query; the auth guard in
  `_authed.tsx` already guarantees a session before this renders).
- Sign-out failure leaves the user on the current page with the menu closed; the
  logout mutation's error is surfaced (not silently swallowed) via the existing
  `Alert` primitive — exact placement settled in the plan.
- RTL (Arabic): the sidebar mirrors to the trailing (right) edge and the drawer
  slides from the right; all paddings/icons flip via the existing
  `lib/direction` + logical CSS properties.

## Data model delta

None. No new tables, fields, or endpoints. The shell consumes the existing
`useMe()` query (name + `profiles` for role-gating) and `useLogout()` mutation.

## API delta

None. Reuses `GET identity/me/` and `POST identity/logout/` already wired in
`src/features/identity/`.

## Frontend

**Routes.** No new routes. The shell is installed at the existing layout route
`src/routes/_authed.tsx`, whose component changes from a bare `Outlet` to
`<AppShell><Outlet/></AppShell>`. Every `/_authed/*` page inherits it; the
signed-out pages (login/register/verify) keep the existing centered
`AuthLayout` card and are untouched.

**Nav configuration.** A single data-driven array is the source of truth so later
specs extend nav by appending one entry:

```
type NavItem = {
  to: string;                 // TanStack Router path, e.g. "/"
  labelKey: string;           // i18n key, e.g. "nav.home"
  icon: LucideIcon;
  requires?: "student" | "parent" | "teacher";  // omitted = always shown
};
```

The sidebar renders `NAV_ITEMS.filter(i => !i.requires || me.profiles.includes(i.requires))`.
Ship-time items: Home (`/`, always), Profile (`/profile`, always).

**Components** (new):
- `src/features/shell/AppShell.tsx` — the CSS-grid frame (topbar / sidebar /
  main); owns the mobile drawer open state (local `useState`); reads `useMe()`.
- `src/features/shell/AppTopbar.tsx` — brand, mobile hamburger, and the trailing
  cluster: `LocaleToggle`, `ThemeToggle` (reused from `src/ui`), `UserMenu`.
- `src/features/shell/AppSidebar.tsx` — renders the filtered `NAV_ITEMS`; the
  same component is used for the `md`+ rail and the mobile drawer body.
- `src/features/shell/UserMenu.tsx` — a dropdown built on the **already-installed
  `radix-ui`** package (`import { DropdownMenu } from "radix-ui"`; **no new
  dependency, no docker reseed**), styled with the existing tokens; items
  Profile + Sign out (`useLogout()`).
- `src/features/shell/nav.ts` — the `NavItem` type + `NAV_ITEMS` array.
- `src/features/shell/index.ts` — barrel export.

Icons come from the already-present `lucide-react`. All labels go through
`react-i18next`; new keys (`nav.home`, `nav.profile`, `nav.menu`, `nav.openMenu`,
`nav.closeMenu`, `auth.profile`, `auth.signOut` — last two already exist) are
added to both `en` and `ar` resource bundles.

**States.** Loading: shell frame renders immediately with a name placeholder.
Empty: n/a (nav is static). Error: only sign-out can error → surfaced via the
existing alert/toast pattern. Success: active link reflects the current route.

**Cleanup folded in (serves this work).** Remove the now-redundant inline nav
from the two existing authed pages: the home page's inline Profile/Sign-out
buttons (`src/routes/_authed/index.tsx`) and the profile page's "Home" button
(`src/routes/_authed/profile.tsx`) — those affordances now live in the shell.
The page bodies (greeting, role cards, profile form) stay.

**"Done"** = built, all dashboard tests green at 100% coverage, deployed to
staging, and verified in the browser end-to-end (desktop + mobile widths, light/
dark, en + ar/RTL).

## Module boundaries

Frontend-only; the `shell` feature is a dashboard-internal UI concern. It depends
on `features/identity` (`useMe`, `useLogout`) and `src/ui` primitives — the same
direction existing pages already depend. No backend module boundary is involved.

## Out of scope

- **No in-app footer** (chosen 2026-06-18). The authenticated dashboard has no
  footer; legal/marketing links live on the marketing site and the signed-out
  auth pages, not here.
- The email-management, children/invites, and student-onboarding pages (Specs
  2–4). This spec only provides the shell + nav config they will extend.
- Breadcrumbs, a command palette, notifications bell, global search — not now.
- Any change to the signed-out `AuthLayout` or auth pages.
- Collapsible/pinned desktop sidebar (icon-rail collapse). Ship the simple
  always-expanded rail on `md`+; revisit if needed.

## Test plan

Vitest + React Testing Library; failing test first; 100% line+branch (repo gate).

Happy path:
- Shell renders a topbar, a sidebar nav, and the page outlet content; **no
  footer** element is present.
- The nav link matching the current route has `aria-current="page"`; others do
  not.
- Locale and theme toggles render in the topbar and still function (locale flips
  `dir`, theme flips the class) from inside the shell.

Role gating:
- A parent-only / student-only nav item appears only for the matching profile and
  is absent for the other (drive `useMe` with each profile set).

Mobile drawer:
- Below `md` the rail is hidden and a menu button is shown; clicking it opens the
  drawer; clicking a link closes it; pressing `Escape` closes it.

User menu:
- Opening the menu shows Profile + Sign out; Profile navigates to `/profile`;
  Sign out calls the logout mutation and redirects to `/login`; a logout error
  keeps the user in place and surfaces the error (no silent failure).

a11y / RTL:
- Nav is keyboard-navigable with a visible focus ring; the menu is reachable and
  dismissible by keyboard; under `dir="rtl"` the sidebar/drawer are on the
  trailing edge.

Regression:
- The existing `_authed/index` and `profile` route tests still pass after their
  inline nav is removed and the shell wraps them.

## Open questions

Resolved during brainstorming (2026-06-18):
- Layout: **sidebar + topbar** (drawer under `md`).
- Footer: **none in-app.**
- User menu: **radix-ui DropdownMenu** (already a dependency — no new package).
- Nav contents at ship: **Home + Profile only**; later specs append entries.
- Account actions (Profile, Sign out) live in the **topbar user menu**, not the
  sidebar.
