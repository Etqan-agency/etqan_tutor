# Hosted docs site: the feature reference behind a login

Date: 2026-10-30. Status: draft, awaiting owner approval.

## Why

The written reference already exists: `docs/features/` (38 pages, about 5,900 lines, one shape per
page: Concepts, How it works, Configuration, API, Dashboard, Background jobs, Code map, Design
history) and `docs/guide/` (architecture, onboarding, testing, runbooks). The owner and developers
still can't use it easily, for two reasons:

1. **Hard to get at.** It's Markdown spread across a private repo, with no search and no single
   place to answer "what does this switch do?" or "what does this feature create?"
2. **Not trusted to be current.** The pages were last audited on 2026-10-17. Work has merged since
   then, for example fast background academy creation (backend#64).

## Goal

A hosted docs site, reachable from any browser behind a login, where developers can browse and
search every feature and see every switch with its configuration.

Success looks like this: a developer opens one URL, logs in, types "online payments", and lands on
the page that shows what the feature does, which switches and settings control it, what it creates
(models, routes, screens, jobs), and where its code lives. Every one of the 88 switches appears in
one table that matches `features.py`.

## Audience

The owner and Etqan developers. Not academy staff, not the public.

## Non-goals

- No rewrite of the existing pages. Their shape is already right.
- No user-facing help docs for academy admins, teachers or students.
- No per-user accounts, SSO or roles for the docs site.
- No API reference generated from DRF (OpenAPI). The API sections in the pages are enough for now.

## Anti-goals (a failure even if it works)

- A second copy of the docs that drifts from `docs/`. The site must build from the Markdown files
  that are already in the repo.
- A switches table someone types out by hand. It must come from the registry.
- Any page reachable without logging in, including search indexes and static assets.

## Design

### 1. The site

- **Tool:** Astro Starlight. *(My call.)* The team already ships Astro (`website/`,
  `marketing/`), and Starlight gives a sidebar, full-text search (Pagefind, built at build time,
  no outside service) and Markdown rendering out of the box.
- **Location:** a new `docs-site/` folder in the meta repo, next to `docs/`. *(My call.)* The docs
  live in the meta repo, so the site does too, and no new submodule is needed.
- **Content source:** Starlight reads `docs/features/` and `docs/guide/` in place (a content
  collection whose loader points at `../docs`). No files are copied into `docs-site/`. Links
  between pages that work on GitHub today (relative `.md` links) must keep working on the site.
- **Not published:** `docs/superpowers/`, `docs/kaleem-archive/` and the root audit files stay
  out of the site. *(My call: they're working history, and the "Design history" links on each page
  can point to them on GitHub.)*
- **Sidebar:** follows the groups in `docs/features/README.md` (Platform, People and access,
  Teaching operations, Money, Communication, Learning, Website, AI and apps, Sales add-ons), then
  the Guide and Runbooks.

### 2. The generated switches reference

- A build step runs a small backend management command (say `manage.py dump_features`) that writes
  `REGISTRY` out as JSON: code, English and Arabic labels, group, default, built, requires, and the
  doc page that covers it.
- The site renders that JSON as a "Switches" page: one table, filterable by group, with default
  on/off, prerequisites, built or not, and a link to the feature page.
- The mapping from switch to doc page is new data. It goes next to `REGISTRY` as a `doc` field on
  each `Feature` (a page slug such as `online-payments`). A backend test checks that every switch
  has one and that the page exists.
- The hand-written lists in `feature-toggles.md` (defaults, prerequisite pairs) are replaced with a
  link to the generated page, so there's only one list.

### 3. Freshness pass

A one-off pass over every page in `docs/features/` and `docs/guide/` against the code at today's
`main`, focusing on changes merged after 2026-10-17. Each page's Configuration section must list
every switch, settings field and environment variable the feature reads. Fix what has drifted and
note the commits checked in each page's Design history.

Going forward, the rule in `docs/guide/adding-a-feature.md` (update the feature page in the same
PR) stays the way pages are kept current. The switch test from section 2 catches the most common
drift automatically.

### 4. Hosting and login

- **Address:** `docs.{$BASE_DOMAIN}`. The existing wildcard certificate already covers it. `docs`
  must be added to `RESERVED_SUBDOMAINS` in `backend/etqan/tenants/services.py`, with a check that
  no existing academy already uses it, so no academy can claim that host.
- **Serving:** a static nginx container built from `docs-site/`, the same pattern as `website/`,
  added to `infra/docker-compose.production.yml` and shipped by the existing deploy.
- **Login:** Caddy `basic_auth` on the whole `docs.{$BASE_DOMAIN}` site block, which runs before
  any file is served, search index included. *(My call: the simplest option with no app code.)*
  One username per developer, bcrypt hashes passed in through env/secrets, never committed. Taking
  someone's access away means removing their line and reloading Caddy.
- The `docs.` block must sit above the `*.{$BASE_DOMAIN}` academy block so it wins, and must not
  forward anything to Django.
- **Local:** `just docs` runs the Starlight dev server with no login.

## Constraints

- Follow the CLAUDE.md flow: spec → plan → code; feat branch, PR, merge.
- Caddy stays the only proxy hop; the edge-wide rules in the Caddyfile header still apply.
- CI is billing-locked until 1 Nov 2026: gate merges on local `ci.yml` runs. The docs build
  (including the `dump_features` step) gets added to CI.

## Decisions from review (my calls)

- **Order:** the site ships first, with the pages as they are. The freshness pass is a separate
  track with its own PRs and doesn't block the site. The site is useful right away, and once it's
  up, out-of-date pages are easier to spot.
- **`doc` field:** holds a page slug, optionally with an anchor (`sessions#postponement`).
  Switches with no page yet, including the unbuilt ones, point at `feature-toggles`. The test
  checks that the page exists, not the anchor. No new pages get written for this.
- **TLS:** `docs.` is an explicit site block, not on-demand. In `cloudflare` mode it uses the
  wildcard certificate. In `http` mode Caddy gets its own HTTP-01 certificate for that one named
  host, the same way it does for the base domain. In `internal` mode it uses Caddy's CA. No change
  to `/internal/tls-allowed`.
- **Credentials:** a file on the host, mounted into Caddy and pulled into the `docs.` block with
  `import` (one `user hash` line each), managed by hand. A runbook entry in
  `docs/guide/runbooks/operations.md` covers adding and removing a person.
- **Submodule links:** links to `backend/...`, `dashboard/...` and other submodules are rewritten
  to GitHub URLs on `main`. Links to `docs/superpowers/` go to GitHub on the meta repo's `master`.

## Left to the builder

- The exact Starlight config for loading content from `../docs` and rewriting `.md` links.
- How the build gets the registry JSON (running Django in the docs image's build stage, or a
  committed JSON regenerated by a check that fails when it's stale). Pick whichever keeps the docs
  image build simple. If it's a committed JSON, CI must fail when it's stale.
- Styling. The Starlight defaults are fine; `@etqan/tokens` colours are optional.
