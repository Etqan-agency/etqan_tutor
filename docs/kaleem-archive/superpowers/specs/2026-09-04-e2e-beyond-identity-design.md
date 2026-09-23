---
name: e2e-beyond-identity
phase: B
modules: [identity, scheduling, platform]
status: implemented
created: 2026-09-04
closed: 2026-09-04
---

## Goal

Extend the Playwright harness past `identity` to the other three user-facing areas that
exist today — **scheduling availability**, **family / children**, **account + email
management** — plus the **app shell** that frames all of them.

The harness is not the deliverable here; it already exists and blocks CI (ADR-0027). This
is the follow-on that spec explicitly deferred:

> **Converting existing features.** ADR-0021 wants e2e per user-facing feature. This slice
> builds the harness and proves it; the backlog of conversions is follow-on.

Until that backlog is worked, `CLAUDE.md`'s D3 table says e2e is in force for `identity`
and nothing else, and D9 still leans on a human click-through for everything else. This
slice closes the gap for every area that has shipped UI.

**No new ADR.** This executes ADR-0027 and ADR-0021 as written; it decides nothing they
did not already decide.

## Why these flows and not unit tests

Each area below has a green vitest suite already. What those suites cannot reach is the
same thing the identity conversion found: the seam between a real browser, a real cookie
on a sibling subdomain, and a real Django server. Concretely, every flow in scope here is
a **state-changing request** — `POST`/`PUT`/`DELETE` — and therefore the first thing in
this codebase to exercise **CSRF on a mutation across the ADR-0019 subdomain boundary**.
The six identity flows are all reads plus one login. A CSRF regression on writes would be
invisible to every test we own today.

## Decisions

**1. Four spec files, one per area, mirroring the feature folders.**
`e2e/availability.spec.ts`, `e2e/family.spec.ts`, `e2e/account.spec.ts`,
`e2e/shell.spec.ts`. `identity.spec.ts` is untouched. A spec file per user-facing area is
what makes the `CLAUDE.md` D3 table checkable at a glance rather than by reading code.

**2. Mutating flows use per-run unique data; the seed prunes what they leave behind.**

Three of the four areas write. They differ in how reversible they are:

| Flow | Reversibility | Handling |
| --- | --- | --- |
| Save availability | replaces the whole week | convergent — the spec sets an exact known week and asserts it; no cleanup needed |
| Add → remove an email alias | reversible in the UI | self-cleaning, but a mid-spec failure strands the address |
| Add a child | **not reversible in the UI** — there is no delete-child | strands a `User` on every run |

So: mutating specs generate a unique address per run
(`e2e.alias.<random>@kaleem.test`, `e2e.child.<random>@kaleem.test`), and `seed_e2e`
grows a **prune** step that deletes anything matching those prefixes before it seeds.

This keeps the command's existing promise — *"idempotent in the strong sense: every run
converges on the declared state"* — true of the whole database rather than only of the
four declared accounts. Without it a developer's local DB accumulates children forever
and the `family` spec's "child appears in the list" assertion gets progressively harder
to write honestly. CI starts from an empty database each run and would not have noticed;
that is exactly the kind of gap that makes a suite pass locally for the wrong reason.

The prune is prefix-scoped to `e2e.alias.` / `e2e.child.` at `@kaleem.test`, and rides the
same `DEBUG`-only guard as the rest of the command. It deletes nothing a human created.

**3. Still no session injection. Every spec logs in through the real form.**
Unchanged from ADR-0027 and for the same reason. The cost is real — each spec pays a
login — and the suite roughly triples in size, so CI wall-clock was expected to go from
~3m to ~8m. **Measured after the fact: 2m31s for all 20**, i.e. the estimate was wrong by
a wide margin and the login cost is not the bottleneck. If it ever becomes the binding
constraint the escape is a Playwright project
dependency that logs in once and reuses a **real** `storageState` (still not a forged
cookie). Deliberately not done now: adding an optimisation before the thing is slow is
how the fixture stops resembling what users do.

**4. Selectors stay role + accessible name.** Same argument as ADR-0027 §5 — the suite
doubles as a WCAG 2.2 AA regression net (ADR-0020) at no cost. Every assertion below is
expressible that way; where a control turned out to be unnameable, that is a finding, not
a reason for a `data-testid`.

**5. Assert what is built, not what should be built.** Two known gaps are in `ISSUES.md`
and stay there rather than becoming red specs in this slice:

- `/availability` has no in-component teacher gate — a parent deep-linking gets a bare
  403, not a friendly empty state. The shell spec asserts the **current** contract (the
  nav entry is absent for a parent), and the deep-link gate stays an open issue.
- `/billing` shows in the nav for every student including a linked child, who then gets a
  server-side 403 at checkout.

Writing a failing spec for unimplemented behaviour would turn a documented backlog item
into a red gate and make the branch un-mergeable for a reason unrelated to this slice
(D10).

## Scope: flows in this slice

### `availability.spec.ts` — teacher

| Flow | Asserts |
| --- | --- |
| Add a time range and save | the round trip: `PUT` with CSRF across subdomains, `Saved.` status, and the pill **still there after a reload** — the reload is the assertion, an optimistic UI would pass without it |
| Remove a range and save | deletion persists; the day falls back to `Unavailable` |
| End before start is refused | client-side guard shows `role="alert"` and does **not** POST |

### `family.spec.ts` — parent

| Flow | Asserts |
| --- | --- |
| Add a child | child appears in the list with a `Pending` badge and its email; survives a reload |
| Generate an invite code | a code renders and the expiry note appears |
| A teacher sees neither card | `/family` for a non-parent non-student renders the `Nothing here yet.` empty state |

### `account.spec.ts` — parent, plus one student check

| Flow | Asserts |
| --- | --- |
| Add an email alias | listed with an `Unverified` badge and no `Primary` badge; survives a reload |
| Remove that alias | the confirm dialog completes and the row is gone |
| Wrong current password is refused | the add form surfaces a field error and the list is unchanged — the password re-auth is a security control and has never been exercised in a browser |
| Student sees the preference cards, parent does not | role-conditional rendering of `StudentPreferencesCard` / `StudentAvailabilityCard` |

### `shell.spec.ts`

| Flow | Asserts |
| --- | --- |
| Role-aware nav (teacher) | `Availability` and `Insights` present; `Family` and `Billing` absent |
| Role-aware nav (parent) | `Family` and `Billing` present; `Availability` and `Insights` absent |
| Active-link marking | after navigating, the destination link carries `aria-current="page"` and no other does |
| Mobile drawer | at a 390px viewport the drawer opens, navigates, closes on navigation, and `Escape` closes it |

## Explicitly out of scope

- **Change password.** It would rotate the shared seed password mid-suite and break every
  spec that has not logged in yet. Worth covering, but it needs a dedicated throwaway
  account — its own small slice.
- **Anything needing a real inbox** — registration, password reset, child activation,
  clicking a verification link. Unchanged from ADR-0027; still needs a mail-catcher in CI.
- **Billing.** Permanently excluded: the hosted Stripe redirect cannot run in Playwright.
- **The five scaffold routes** (`/schedule`, `/curriculum`, `/assessments`, `/messages`,
  `/insights`). They are placeholder pages ahead of their backend modules; there is no
  behaviour to assert beyond "a heading renders", which vitest already covers.
- **Cross-browser.** Chromium only, unchanged.

## Module boundaries

The only backend change is the prune step inside
`kaleem/identity/management/commands/seed_e2e.py`, which touches identity models and
allauth's `EmailAddress` only — no cross-module call, same as the command it extends. The
dashboard specs live in `e2e/` and import nothing from `src/`, so no cross-feature import
rule applies.

## Definition of done

- The four spec files pass locally against the dev stack and in CI.
- Each new assertion written to fail first against a deliberately broken expectation —
  a spec that has never been red has not been shown to test anything.
- `seed_e2e` prunes `e2e.alias.*` / `e2e.child.*` and still converges on the four declared
  accounts; a backend test covers the prune (the 97 floor is a ratchet, D3).
- `CLAUDE.md`'s D3 table updated to name the four areas now covered — precisely, not
  aspirationally.
- `ISSUES.md`: the "e2e covers `identity` only" entry narrowed to what genuinely remains
  (change-password, inbox-dependent flows, billing).

## Outcome

All of the above shipped (backend #38, dashboard #32, meta #140). 6 flows → 20, green in
CI in 2m31s.

Decision 5 earned its keep twice over: the conversion found **two** defects rather than
the two it anticipated, and both were logged instead of fixed.

- **The mobile drawer does not restore focus when it closes.** This one was written as an
  assertion first, failed, and was then *measured* rather than assumed flaky —
  `document.activeElement` is `<body>` after Escape. The drawer opens from `AppShell`
  state instead of a `Dialog.Trigger`, so Radix has no trigger to restore to. WCAG 2.4.3,
  against a baseline ADR-0020 makes repo-wide. Fixing it reshapes `AppTopbar`'s
  `onOpenMenu` prop contract, so it went to `ISSUES.md` (D10) and the spec says so in a
  comment rather than asserting it.
- Two `/family` buttons share the accessible name **"Add child"**. Exactly the class of
  finding decision 4 predicts role-plus-name selectors would surface, and a `data-testid`
  would have hidden.

This is the argument for the harness restated: a suite that only ever confirms what unit
tests already know is not worth its CI minutes. Both findings came from a real browser and
neither was reachable from vitest.
