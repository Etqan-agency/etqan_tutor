# ISSUES

Spotted-a-problem backlog. Write it here in 15 seconds, keep going (D10).

**Triaged by consequence, not by date.** Three buckets, and nothing else:

- **Blocks launch** — must be fixed before real users and real money. Read this section
  before planning any phase.
- **Blocks a phase close** — stops the current or next phase reaching D9.
- **Someday** — real, small, unbounded in time. Polish, D10 notes, deferred niceties.

Resolved entries are **deleted**, not struck through — git remembers them. Last triage:
2026-09-03 (removed 11 entries that were already fixed or stale).

---

## Blocks launch

- ~~**`text-primary` links fail AA in dark mode wherever they sit on a card.**~~ **FIXED
  2026-09-13** in `@kaleem/tokens` v0.2.2 + dashboard #63. The root cause was not a bad
  value but an **undeclared pair**: `--primary` is a SURFACE colour, and nothing asserted it
  as text, so 4.29:1 on `--card` and 3.14:1 on `--secondary` shipped on every auth page.

  `--primary-text` is the emerald chosen to clear 4.5:1 on every surface a link can land on
  (light: emerald.700 — the same value `--primary` already had, so light did not change;
  dark: emerald.300). The pair is now **declared** against background, card, popover,
  secondary and muted, and mutation-checked: pointing it back at emerald.500 reproduces the
  exact four failures.

  Three gates were blind to it, each for a different reason, and all three are now closed:
  the token gate proves declared pairs (now declares it); the browser-axe sweep ran only on
  `/design-preview`, which renders primitives rather than pages (now sweeps the four real
  auth routes in **both themes**); and Lighthouse audits the default theme only, scoring
  these same pages 1.00 the same day (the new sweep is explicitly dark-first). A source lint
  also now rejects the primary/accent SURFACE colours used as text.

- **Staging passwords were world-readable on a then-public `master`, and remain in git
  history.** On 2026-09-08 `kaleem-lms/Kaleem` was public and
  `curl https://raw.githubusercontent.com/kaleem-lms/Kaleem/master/STATE.md` returned
  `KaleemC3d!2026` and `KaleemStaging!2026` to an anonymous caller. **The repo has since been
  made private by its owner** — as of 2026-09-11 `private: true`, and the same anonymous
  `curl` 404s, so the open window is closed. It is not undone: the strings stay in history at
  every older commit, and anyone who cloned or scraped while it was open still holds them,
  exactly as the `.gitleaksignore` rotation record says of the 588a1e35 credentials (ADR-0032).
  **Do:** rotate the staging passwords for `c3d.student@`, `c3d.teacher@`,
  `billing.clickthrough@`, `billing.recheck@`, `billing.failcard@` and the two `*.smoke@` users,
  then keep the new ones out of the repo entirely.

  ⏸ **DEFERRED by the owner 2026-09-13.** It stays under *Blocks launch* and its severity is
  unchanged — deferring is a decision about **when**, not about whether it matters. What the
  deferral actually accepts, stated so the next reader does not have to reconstruct it:
  these credentials reach **staging only**, the repo is private again so the window is closed,
  and the exposure is bounded by whoever cloned during it. It must still be done before real
  users and real money, and it cannot be done by rotating alone at that point — the strings are
  in history for good, so the new ones must never enter the repo.

  ⚠ **This is NOT the same task as unblocking the staging walk, and bundling them was my
  error.** `STATE.md` called them "one task, not two". They share a symptom — no working
  credential — but not a purpose: rotation is *security remediation* for leaked strings, while
  the walk needs *any* working login. A fresh throwaway staging account, created and never
  written down here, unblocks the walk without touching the leaked ones. That is a much smaller
  piece of work and is now independent of this deferral.

- ~~**`security` (gitleaks) skips on documentation-only changes, and root `*.md` counts as
  documentation.**~~ **FIXED 2026-09-13** (ADR-0042, meta). The `code == 'true'` clause is
  dropped from the `security` job alone; `verified != 'true'` stays, because a tree a PR
  already proved green has already been scanned. The reasoning ADR-0038 applied to the other
  six gates does not transfer to this one: a secret scan tests the BYTES of a commit, not the
  code, and a `.md` carries a credential exactly as well as a settings module does. This
  project's only two observed leaks were both root-level `.md` files — `portal-snapshot.md`,
  and the staging passwords that sat in `STATE.md` on a public `master`.

- **A deploy drops every live call (C3b).** `scripts/ship.sh` step 8 stops the old signaling
  container with `stop --timeout 30`; room membership is an in-process dict, so every call in
  progress dies with it — the 30s is a SIGTERM grace period, not a drain, and nothing waits for
  rooms to empty. The fix is a **real drain**: stop routing new joins to the old colour, wait for
  its rooms to empty, then stop it. That needs a join-routing switch which does not exist yet, so
  it is not to be attempted as a side change. Interim rule, in `docs/runbook/signaling.md`:
  **deploy between lessons.**

  *(The second half of this entry — the colour overlap splitting one room across two processes —
  was **fixed in C3c, then the fix itself caused a different bug** (`Room.signaling_url` pinned a
  room to a colour `ship.sh` later removed, making it permanently unjoinable — hit live on
  staging 2026-09-07). Both are now closed by ADR-0037: signaling is one shared, never-stopped
  replica, not one per colour, so there is no second process to split across and no colour for a
  pin to outlive. Implemented and unit-tested; **not yet verified by a live staging colour
  flip** — see the new entry below.)*

- **Traefik logs no request path for any route, and C3c did NOT make it safe to restore.**
  The token itself is fixed — since C3c it rides `Sec-WebSocket-Protocol`, not a query string.
  But the plan to then restore Traefik's dropped `RequestPath` field **does not survive contact
  with the URLconf and is withdrawn.** `config/urls.py` includes `allauth.urls`, which serves
  `/accounts/confirm-email/<key>/` and `/accounts/password/reset/key/<uidb36>-<key>/` — single-use
  **account-takeover** credentials in the **path**, not the query string. Removing the signaling
  token changed nothing about whether `RequestPath` is safe to log, and Traefik still has no
  per-router access-log config and no partial-field redaction.
  The remedy is therefore not a Traefik rollback: **give dashboard and marketing path-level
  logging from their own container access logs**, the same compensating control Django already
  has through gunicorn. Until that lands, those two surfaces have no path-level visibility at the
  gateway.

- **The gunicorn access log captures account-takeover credentials, and the compose comment
  claiming otherwise is wrong (C3b, spotted in C3c's final review).**
  `infra/docker-compose.production.yml`'s django-blue/django-green comment used to assert "safe
  to log in full: no capability token ever appears in an API URL." That is true of the video
  signaling token, but the entry directly above establishes the opposite for `allauth.urls`:
  `/accounts/confirm-email/<key>/` and the password-reset key are single-use account-takeover
  credentials carried **in the path**, and those requests go through Django, so
  `gunicorn --access-logfile -` records them in full. Pre-existing since C3b; C3c nominated that
  same compensating control as the model for dashboard and marketing to copy (the bullet above),
  which is what surfaced the contradiction. The compose comment has been corrected to say so; the
  underlying leak is not fixed here.

- **No `turns:` TLS listener, so a TLS-443-only egress filter still blocks the relay (C3c).**
  coturn listens on `3478` UDP and TCP only. Traefik owns 443 on the staging box, and a `turns:`
  listener on 5349 would need a certificate delivered to a container Traefik does not front, so
  C3c shipped without one (spec decision 3). Media is DTLS-SRTP end to end regardless and the
  credentials are ephemeral and single-user — what is missing is *reachability* for users behind
  a filter that permits only TLS on 443. Closing it needs a second IP or a dedicated TURN host.
- **The TURN DNS record publishes the origin IP (C3c).** `turn-staging.kaleem.academy` must be
  Cloudflare **DNS-only (grey cloud)** — Cloudflare cannot proxy UDP, and a proxied record breaks
  every allocation with no error a client can interpret. The consequence is that the origin IP,
  which the proxied records hide, is now published. Accepted for staging; revisit before
  production.
- **The coturn shared secret is visible in `docker inspect` and the host process list (C3c).**
  It is passed as `--static-auth-secret=` on coturn's command line because **coturn performs no
  variable expansion in its config file** — a `${VAR}` there is taken literally, which would have
  made the secret a publicly guessable constant and the relay an open proxy. The command-line
  form is the fix; the exposure is the accepted cost, and it sits inside an existing trust
  boundary (the same value is already in `.env.production` on that box, and docker socket access
  there is already root-equivalent). See `docs/runbook/turn.md`.
- ~~**`pyproject.toml`'s `precision = 1` comment describes a rounding rule coverage.py does not
  appear to follow.**~~ **WRONG DIAGNOSIS, REAL OBSERVATION. CLOSED 2026-09-13** (backend #60).
  Read from the pinned coverage 7.16.0, `should_fail_under` is in full
  `return round(total, precision) < fail_under` — it follows the documented rule exactly.
  The actual trap: `fail_under` had TWO decimals while `precision` is 1, so the total was
  rounded to one decimal and compared against a two-decimal floor, making **97.72 effectively
  97.75**. `round(97.74, 1) = 97.7 < 97.72` FAILS while the report prints a number above the
  floor — which is the behaviour that got logged. `fail_under` is now 97.8, one decimal:
  identical effective floor, but the number says what it does.
- **`semgrep`, `trivy` and `pnpm audit` still do not run anywhere.** ADR-0030 wired in
  `gitleaks` + `pip-audit` (blocking) and Lighthouse (nightly), so the OWASP-Top-10 SAST
  pass, the container-image CVE scan, and the JS dependency audit are what remains of the
  original "nothing scans anything" entry. Each needs its own triage budget — a SAST tool
  adopted with 200 findings gets muted within a week.
- **Submodule git *histories* are unscanned for secrets.** The `security` job scans the
  meta history plus the checked-out tree (submodules included); a secret committed and
  then removed inside `backend`/`dashboard`/`marketing` is caught only by that repo's
  pre-commit hook, on a machine that has pre-commit installed. (ADR-0030, stated gap.)
- **Production environment does not exist.** Staging only. Prod hosts (`app.` / `api.` /
  apex + `www`), the `www` redirect, and a prod VPS are all deferred per ADR-0019.
- **First production deploy must start from an empty DB.** `migrate` orders `identity`
  (the custom `AUTH_USER_MODEL`) before `account` (allauth); any environment whose
  `account` migrations were applied first hits `InconsistentMigrationHistory` and the
  deploy aborts. This bit staging once (2026-06-10, fixed by recreating the DB). Either
  start prod empty or write the documented repair step first.
- **`deploy-staging` `needs:` every check, so a red required check makes the deploy
  *silently skip*** — the PR looks merged but nothing shipped. That bit us on #88. Add a
  deploy gate or status so a skipped deploy is visible rather than looking like success.
  (The squash-divergence half of this entry is **resolved** by ADR-0028: no `develop`, and
  merge commits for anything carrying submodule pointers.)
- **GDPR operational obligations.** ADR-0023 fixed the by-design engineering rule and the
  email leaks; these are the heavier operational duties, all still missing: a data-retention
  policy, a DSAR / right-to-erasure flow (export + delete a user's data), a cookie/consent
  decision for the marketing site, and a Records-of-Processing (RoPA) document.
- ~~**No security-alert email on password change or reset.**~~ **FIXED 2026-09-13**
  (backend #53). Both paths now alert the primary address, with one body for both: the
  reader's question is "did I do this?", and the answer does not depend on which route was
  taken. It says RESET rather than "change your password" — by the time it is read in anger
  the old password no longer works. `confirm_password_reset` also activates a CHILD, whose
  primary address is unverified until they follow the link, so the verified state is read
  BEFORE the row is updated and a first-time activation stays silent; that guard is
  mutation-checked. Adding two actions also forced the `else` fallback below to become an
  exhaustive match that raises.
- **allauth templates still echo an email address in the body** —
  `account_already_exists_message.txt`, `unknown_account_message.txt`,
  `email_changed_message.txt` (ADR-0023 violation). Currently unreachable: `RegisterView`
  raises `ValidationError` for duplicates and we do not use allauth's native signup/change
  flows. **Override these before enabling any allauth-native signup or social-auth path.**
- **The staging VPS filled its disk and a deploy died mid-swap (2026-09-12).**
  Root cause and all three code defects are FIXED (infra `ship.sh`, PR #11): no disk
  precheck, a non-atomic state write that left `.active-color` EMPTY rather than stale,
  and the state recorded AFTER the old colour was torn down. The host was remediated by
  hand — pruned 73G/0-free to 7.5G/65G-free, `.active-color` restored to `green`.
  **What remains open:** (a) nothing monitors disk on that host, so the next capacity
  problem is also found by a failed deploy; (b) `docker image prune` now runs only on a
  SUCCESSFUL deploy, so a run of consecutive failures still accumulates images; (c) the
  prune keeps 24h of images, which after this incident's `prune -a` means there is
  currently NO local rollback target — `restore_signaling()` and a rollback would have to
  re-pull from GHCR. Worth a cheap disk alarm before it bites in production.
- **EN 301 549 clause 7: no captions or audio description for live lessons.** ADR-0040
  adopts EN 301 549, and for the design system its delta over WCAG 2.2 AA is ~zero
  (clause 9 incorporates WCAG by reference). **Clause 7 is the one with real teeth** and
  kaleem cannot currently meet it: the call carries no captioning. Belongs to the call
  feature, needs its own spec, deliberately out of scope for the design-system work.
  Logged here rather than left unstated so "EN 301 549 conformant" is never claimed flat.
- **Throwaway users in the staging DB.** `stg.smoke@example.com`, `ses.smoke@example.com`,
  and `c0.subjects.check@example.com` (a child of `billing.clickthrough@`, created
  2026-09-05 while verifying C0 and left unverified — it cannot log in). Clear via
  Django admin or on the next staging DB reset.
- **The nightly dunning harness exercises `basil`-shaped webhook payloads, but production
  receives `dahlia`-shaped ones.** `stripe listen` forwards events at the Stripe
  **account default** API version and cannot be told to forward at an arbitrary pin — it
  offers only the account default or `--latest`. This account's default is
  `2025-06-30.basil` (verified 2026-09-04 off three live events), while the production
  webhook endpoint `we_1UBdRwCavwnriKDQ2ygx6z2V` is pinned to `2026-08-26.dahlia`. Both
  shapes parse today, because `_subscription_period_end` and `_invoice_subscription_id`
  carry basil-vs-legacy fallbacks written for exactly this. But it means the harness does
  **not** prove the payload shape production actually meets: it proves the dunning state
  machine against the older shape. Closing this means upgrading the Stripe account's
  default API version to match the pin — a change to shared config that also affects
  staging billing, so it needs a deliberate decision and its own runbook step, not a
  drive-by. Phase B's dunning gate is closed regardless — the state machine is genuinely
  exercised end to end. What remains is narrower: the harness proves that machine against
  the older payload shape, so a `dahlia`-only regression in the parsers would not be
  caught here before real users.

## Blocks a phase close

- ~~**`/availability` scrolls sideways at phone width — SC 1.4.10 Reflow.**~~ **FIXED
  2026-09-13** (dashboard #64), and the diagnosis in this entry was wrong twice over. It was
  not the availability editor, and it was not one page: measuring PER ELEMENT instead of per
  page found the app shell's **topbar** — a non-wrapping row of hamburger + wordmark + a
  211px control cluster summing to 376px — so **every authed route** overflowed at 320px.
  The wordmark is now hidden below `sm`; it gives way because it is the only thing in that
  row carrying no function. `e2e/reflow.spec.ts` sweeps five routes at 320/360/430 and
  reports the widest element, not just the page width, so the next regression arrives as a
  diagnosis rather than a hunt.

- **The inactive colour's WebSocket hostname has no TLS certificate (C3c) — smaller than first
  thought.** Traefik issues via Let's Encrypt's HTTP challenge when a router first appears, so
  while blue was active `ws-green-staging` failed TLS verification and `ws-blue-staging` answered
  healthy. **The predicted outage on switching colours did not materialise:** the 2026-09-06
  colour flip to green was checked immediately afterwards and `ws-green-staging` already served
  `{"status":"healthy"}` over a valid certificate, with the handshake refusing a bad token 4401 as
  designed. ACME completed inside the deploy's own window. Left open because it is unproven under
  a slower ACME or a rate-limited issuance, and because the first flip to a *never-before-active*
  colour is the risky case — but do not plan work around an outage that has not been observed.

- ~~**A coturn config-only change does not restart the running relay (C3c).**~~ **FIXED
  2026-09-13** (infra #12). `ship.sh` compares a sha256 of `turnserver.conf` against a recorded
  hash and restarts **only on a real change** — an unconditional restart would trade a silent
  stale config for a guaranteed mid-call cut on every deploy, since a restart drops every relay
  allocation (the reason coturn is not in a colour profile at all). The hash is recorded only
  AFTER a successful restart, so a failure retries next deploy rather than recording a config as
  applied that is not running, and it is written atomically for the same reason `write_state` is
  (2026-09-12: a truncating write left state EMPTY, not stale).
  ⚠ No hash file exists on the VPS yet, so the FIRST deploy after this restarts coturn once.
- ~~**Sentry may capture a capability token and TURN credential as stack-frame locals
  (C3c).**~~ **FIXED 2026-09-13** (backend #54). `include_local_variables=False`, so frame
  locals do not leave the process at all. The defect was never the three names the default
  `EventScrubber` happens to miss (`credential`, `servers`, `grant`) — a name-based denylist
  cannot be kept in step with every local a future view binds. `send_default_pii=False` is now
  explicit too, because a default is exactly what an SDK upgrade is free to change. Landed
  before `SENTRY_DSN` is ever set, which is the only time this is cheap.

- **There is no `docs/architecture/scheduling.md`, and D9 asks for one every phase.** `identity`,
  `billing` and `curriculum` each have an architecture doc; `scheduling` — now the largest module
  in the codebase, spanning C0 matching inputs, C1 matching, C2 booking + quota, C3a rooms, C3b
  signaling and C3c TURN — has none. Each of those phases quietly skipped the "arch doc updated"
  line of the Definition of Done. Writing it is a phase-sized piece of work in its own right and
  must not be bolted onto whichever phase notices next: a doc covering only the latest slice
  would misrepresent the module more than its absence does. The operational half is covered by
  `docs/runbook/signaling.md` and `docs/runbook/turn.md`; what is missing is the module's own
  structure, boundaries and data model.

- ~~**Nothing ever ends a video room (C3a).**~~ **FIXED 2026-09-13** (backend #59).
  Cancelling and completing a session now end its ACTIVE room, which is what gives
  `Room.Status.ENDED` a production path at all. The local row is marked ENDED **even when the
  provider call fails**, because ACTIVE is what `_ensure_room` REUSES and reusing a room the
  provider has dropped is worse than minting a new one; that path has its own test.
- ~~**`Room.provider` is stored but never read (C3a).**~~ **FIXED 2026-09-13** (backend #59)
  by taking the second option this entry offered. A mismatch is now **refused loudly** rather
  than routed: there is no registry mapping the stored short name back to a class, and building
  one would claim we can still reach a room inside a provider we are no longer configured for.
  The operator's fix is to end the active rooms, which the `end_room` work above makes
  possible.
- ~~**The join endpoint has no throttle (C3a).**~~ **FIXED 2026-09-13** (backend #59).
  `session-join` at 30/hour in production — set for a BAD network, since a rejoin after a drop
  is normal and a lesson runs an hour — and raised in local/test settings so the e2e flows and
  CI's retry are unaffected. The test drives the real throttle rather than reading the
  attribute, because a `throttle_scope` with no matching rate silently does nothing.
- **The C3a e2e does not cover "a parent sees no Join control".** The spec lists it; it shipped
  covered at API level (403 against a real `ParentStudent` row) and at component level only.
  `seed_e2e` creates no parent↔student link, so the flow would be vacuous without seed work.

- **e2e now covers every shipped user-facing area; what remains is listed below.** The
  2026-09-04 conversion took the suite from 6 flows to 20 — availability, family, account
  and email, and the app shell all have specs, and the `CLAUDE.md` D3 table names them.
  Still uncovered, each for a stated reason: **change-password** (would rotate the shared
  seed password mid-suite — needs its own throwaway account, a small slice), the
  inbox-dependent flows below, and billing. A table that claims less than reality is
  harmless; one that claims more is how the gate stayed fictional for three months.
- **Flows the harness structurally cannot reach without more infrastructure:** anything
  needing a real inbox — registration, password reset, child activation — because CI has no
  mail-catcher wired in. That is its own slice (a mailpit service plus a way to read the
  link). Note this is *not* the same as the billing exclusion below, which is permanent.
- ~~**`WebhookEvent.stripe_customer_id` is parsed but never consumed.**~~ **FIXED 2026-09-13**
  (backend #62) — it is now recorded in the incident detail, so whoever investigates a dropped
  event finds WHOSE subscription it was in one search. Deliberately diagnostic rather than
  functional: resolving the customer to a user and adopting the subscription would grant
  entitlement from an event we cannot attribute, which is a **product decision** about
  dashboard-created subscriptions and remains open.
- ~~**The spec requires `display_amount`/`currency` "validated against the Stripe Price on
  save"; there is no `clean()`.**~~ **PARTLY FIXED 2026-09-13** (backend #62). `clean()` now
  validates the SHAPE — lowercase ISO-4217, non-zero amount — which catches what a human gets
  wrong in the admin. The Stripe cross-check is deliberately NOT in `clean()`: it would make an
  ordinary admin edit fail whenever Stripe is slow, for a field that is a display mirror and
  never the charge source of truth. Its right home is the nightly reconciler, which already
  talks to Stripe on a schedule and can raise an incident on drift. **That remains an owner
  decision**, and the docstring says so.
- ~~**`TeacherProfile.availability` is a dead JSONField.**~~ **FIXED 2026-09-13**
  (backend #55). The check this entry asked for came first: no serializer exposes it, no admin
  form lists it, and the only references in the tree were the model line, its creating
  migration and one default assertion — so every row held `[]` and the drop lost nothing. The
  migration's docstring records that, since the next reader of a `RemoveField` on a JSON
  column will want to know whether data went with it.
- **Dashboard zod validation messages are not i18n'd** — they render English regardless of
  locale (`registerSchema`'s birthdate refine, plus zod's defaults on every form). zod runs
  outside React so `t()` cannot be called in the schema. Breaks ar parity for validation copy
  (ADR-0020). Fix repo-wide via a locale-aware resolver wrapper or per-field `setError`.
- ~~`test_checkout_completed_..._unknown_user_is_ignored` would still pass if the `get_user`
  check were deleted.~~ **FIXED 2026-09-13** (backend #56) — the `caplog` assertion on
  `reason=unknown_user` is in, and **mutation-checked both ways**: green with the guard removed
  before, red with it removed now.
- The `canceled`-but-paid-through mirror of the documented `past_due` divergence: such a row
  is entitled, yet `get_current_subscription` returns `None`, so the UI reads "no
  subscription" while the user can still book, and an overlapping purchase is permitted
  during the paid-through window. Only the `past_due` direction is documented.
- `/billing` nav shows for every student; a linked child gets a server-side typed 403 at
  checkout rather than a hidden nav entry. Refine once `/me` exposes whether a student has
  a parent.
- A parent cannot edit an existing **child's** learning preferences (time slots / teacher
  gender) — they are only set at child creation (`POST children/`). Needs its own endpoint
  and UI.
- Plan/Price creation is manual in Stripe; no programmatic sync (B1 scope).
- Dunning UX beyond mirroring `past_due` (retry/notice flow) is deferred.

## Someday

- **One failed `getUserMedia` tap writes TWO `calldiagnostic` rows, so the table
  over-counts failures (spotted during the per-kind split fix, dashboard #71).** `acquire`
  coalesces a request that arrives mid-flight into `pendingAcquireRef` and runs
  `acquireOnce` again after the first settles; each run reports independently. Session 7's
  staging rows show the signature plainly -- pairs ~150-300ms apart (`12:26:05.605` /
  `.818`, `12:24:39.203` / `.627`), which is one tap, not two. Nothing is *wrong* in the
  app; the diagnostics table simply reads roughly double on any failing device, which
  matters because that table is the only thing this phase is verified by. There is also no
  dedup or rate limit on reporting, so a person mashing "Try again" writes a row per
  attempt (ten in 13 seconds on 2026-09-07). Fix is probably "report a code at most once
  per session per mount", but that trades away the ability to see retry volume -- decide
  which of the two the table is for before changing it.

- **The weekly-slot picker names a time and nothing else.** `SlotOption` carries only
  `weekday`/`start_time`/`starts_at`, so the cards a student chooses their standing weekly
  time from cannot show the teacher, the subject or the duration — there is nothing on the
  wire to show. Found in the C6 audit; closing it needs an API change, which put it out of
  that spec's scope. **Do:** add teacher/subject to the slot-options payload, then put them
  on the card.
- **No speaker/output-device selection anywhere in the call.** A student whose audio is
  routed to the wrong output has no control in kaleem at all. `setSinkId` would cover it on
  Chromium and is unsupported on the browser that needs it most. Found in the C6 audit and
  left out as a feature rather than a fix.
- **`CallSettingsMenu` and `DevicePickerButton` are hand-rolled popovers.** Near-identical
  focus/dismiss logic in two files, neither trapping focus, while `CancelSessionDialog`
  three directories away uses Radix correctly. C6 fixed their behavioural gaps (touch
  dismissal, focus restore) and deliberately left the structural rewrite alone per D10.
- **The schedule is a forward-only list with a history disclosure, not a calendar.** C6
  made past lessons reachable, which was the defect; a week or month view is a feature and
  needs its own spec.
- **Availability entry is still one range at a time.** A weekday 9–5 schedule is ~20
  interactions through 96-option selects. C6 added a confirmed copy-to-all and a weekly
  total; a drag-select grid is its own spec.
- ~~**Two `deploy-staging` jobs can run at once on `master`.**~~ **FIXED 2026-09-13.** The
  group is now `${{ github.workflow }}-${{ github.head_ref || github.ref }}`, so all master
  runs share one. **`cancel-in-progress` is deliberately OFF for pushes** — the entry above
  asked whether cancelling was right for a deploy, and it is not: `ship.sh` has a window
  where the old colour is down and the new one is not yet up, and killing a run inside it is
  the exact shape of the 2026-09-12 incident that left `.active-color` empty. Pushes queue;
  pull requests still cancel superseded runs.

- ~~**The shared `Button`'s `sm` size is 40px, under the 44pt touch guidance.**~~ **CLOSED
  2026-09-13** (ADR-0040 decision (c), implemented in phase 7 P8). The ink stays 40px and the
  TARGET is 44px via a pseudo-element, because SC 2.5.8 measures the region that accepts a
  pointer, not the painted box — so dense table rows keep their density. `Checkbox` got the
  same treatment (20px ink, 24px target) after the sweep found it genuinely under the
  minimum. Verified by hit-testing in `e2e/touch-targets.spec.ts`, not by measuring geometry.

- **The call's idle screen tile relies on a laid-out-but-invisible `<video>` continuing to
  decode, and that is not spec-guaranteed.** C4b gates the shared-screen tile on frames
  (`useVideoFrames`), which means the `<video>` must be mounted and decoding before anyone
  shares. It is kept as a 1px fully transparent box (`CallStage.IDLE_SCREEN_TILE`) rather
  than `display: none` precisely because an element generating no box is the case a browser
  is free to stop decoding — measured in Chromium, where BOTH spellings kept decoding
  (`videoWidth: 1280` through a real share), but nothing in the spec promises it. Residual
  risk: on an engine that stops decoding a zero-area or fully transparent video, a shared
  screen would silently never appear for the watcher — no error, no fallback. **This project
  cannot test that**: there is no Apple device here and Playwright's WebKit on Linux is not
  iOS Safari (standing D9 deviation). **Do:** when an Apple device or a real WebKit lane
  exists, drive one share end to end on it; if it fails, the fix is a real "screen share
  started/stopped" signalling message, which is the same thing the stop-detection gap below
  needs.
- **Nothing tells the watcher when a screen share STOPS.** Measured on the built app: 12s
  after the sharer clicked Stop, the receiving `<video>` still reported `videoWidth: 1280`,
  `currentTime` frozen, `track.muted` still `false`, and neither `resize` nor `emptied` ever
  fired. So `useVideoFrames` latches `true` and the frozen last frame keeps the main tile.
  C4b ships a viewer-side escape (the "Hide the shared screen" control in the layout
  popover, which outranks `mainIsScreen` in every layout) so nobody is trapped, but that is
  a manual workaround, not detection — and because a NEW share is equally undetectable, a
  viewer who hides a stale screen must ask for the next one back by hand. **Do:** an
  explicit screen-share started/stopped signalling message (the relay contract changes), or
  receiver-stats polling. `usePeerConnection`'s own comment above `setRemoteScreen` names
  both.

- **The CI cost model (ADR-0038) has never met an invoice.** Every dollar figure in
  `docs/superpowers/specs/2026-09-08-ci-cost-optimization-design.md` is run-count times
  measured per-job minutes times the published per-minute rate — the billing API needs
  `admin:org`, which this project's token does not have. Read one real month's Actions bill
  and correct the spec against it.
- ~~**The artifact-miss path in the CI cost guard is unproven on a real push (ADR-0038).**~~
  **PROVEN ON A REAL PUSH 2026-09-13**, by itself, exactly as this entry predicted ("or after
  `master` moves underneath its PR"). No deliberate artifact deletion was needed.
  What happened: meta#228 went green and recorded its tree, then `master` moved underneath it
  while it sat in CI (#227, `c0de39f` and #229 landed from a concurrent session). The merge
  therefore produced a tree nobody had verified — push tree `0391c7c7` against the PR head tree
  `0380a8e6` — `triage` found no matching `verified-tree-<hash>` artifact, and **the full gate
  set re-ran on the push** instead of skipping. All ten green, `deploy-staging` SUCCESS, four
  endpoints 200.
  So the guard fails in the safe direction under the condition that actually occurs in practice:
  a busy trunk, not a week-old branch. The mechanical check this entry distrusted (a `gh api`
  query against a name that does not exist returning 0) turns out to have been right — but it is
  no longer the only evidence.
- **Dependabot PRs now report green with nothing tested (ADR-0038).** The seven gate jobs and
  `deploy-staging` all skip for `github.actor == 'dependabot[bot]'` rather than failing at
  checkout as before — cheaper and no less honest about what was tested, but GitHub counts a
  skipped required check as satisfied, so this would look mergeable if branch protection is
  ever enabled. Three real Dependabot PRs are open: #182 (`setup-python` 5→7), #183
  (`upload-artifact` 4→7), #184 (`setup-node` 6→7). `ci.yml` pins `upload-artifact@v4`, so
  #183 is a real version upgrade this repo hasn't taken — review it deliberately rather than
  merging on a green tick that verified nothing.
- **Staging carries throwaway fixtures from the Phase B and C live checks.** Moved here from
  `STATE.md` when it was trimmed 303 → 71 lines on 2026-09-08 — these are live artefacts on a
  shared environment, and losing the record does not remove them, it just means the next person
  meets them with no context. **Passwords are deliberately NOT recorded here: this repository is
  public.** They were in `STATE.md` on `master` in plaintext until this commit; see the
  credential-exposure entry under *Blocks launch*.
  - **C3d call-check accounts:** `c3d.student@example.com` / `c3d.teacher@example.com`,
    with a matched Arabic assignment and a recurring slot. **Session
    id 3 is a permanently joinable lesson** — it was repositioned to `now` on 2026-09-07 09:20
    so a live check could reach the Lobby, and nothing has moved it back. Clear on the next
    staging DB reset, or reuse for a future call check rather than rebuilding the fixture.
  - **Billing click-through accounts:** `billing.clickthrough@` (id 7), `billing.recheck@`
    (id 8), `billing.failcard@` (id 9), plus two older `*.smoke@` users. Clear on the next
    staging DB reset.
  - **The 2026-09-13 walk account:** `walk.2026w37@example.com` (id 19), verified, with all
    three profiles so the full nav renders. Created for the authenticated staging walk after
    the rotation was deferred — proving the walk never needed the leaked credentials, only a
    working login. **Its password is deliberately not recorded here** (this file is in a repo
    that was public once); regenerate or delete the user rather than trying to recover it.
    Clear on the next staging DB reset.
  - **One throwaway `CallDiagnostic` row**, written by the 2026-09-07 live check: session 3,
    `autoplay-blocked`, a synthetic iPhone-Safari `User-Agent` and hand-built redacted stats.
    Evidence the diagnostics pipeline works, not real user data. Delete on the next staging DB
    reset, or leave it — the 90-day purge job takes it on 2026-12-06 either way.
- **The session UI redesign's class-string unit tests are weak proxies for real layout
  (`SessionCard.test.tsx`, `CallStage.test.tsx`/`SelfView.test.tsx`, `Lobby.layout.test.tsx`).**
  They assert things like `toHaveClass("sm:flex-row")` or a logical-property regex match, which
  proves the string is present, not that anything reflows, reorders or mirrors under RTL. jsdom
  has no layout engine, so nothing about actual media-query behaviour can be exercised at the
  unit level at all. The only real evidence is the session-ui-redesign e2e flows added in Task
  16, and those run in Chromium only — no coverage of any other browser or of viewport sizes the
  flows don't hit.
- **The session-ui-redesign e2e flows ran against the dev-server/HMR topology, not CI's
  build-then-preview topology.** Task 16 executed them locally against `docker-compose` +
  `pnpm dev`, not the `pnpm build` + `pnpm preview` pair CI uses. Unlikely to matter for
  Tailwind-class-driven layout, but it is asserted rather than verified — this project has
  already hit a case (C3d's `call.spec.ts`) where a flow passed locally and could never have
  passed in CI because the two environments differed in a way nobody had checked. CI's own run
  on this branch is the actual proof; watch it rather than assuming the local result carries over.

- **Whether a real browser reports the "camera turned off mid-call" case `useVideoFrames`
  exists for is unverified (C4b).** The hook returns to `false` when the video element's
  reported size drops to zero (a `resize`/`emptied` event with `videoWidth === 0`), which is
  proved against a fake element whose `videoWidth` the unit test sets directly. Whether a real
  `<video>` actually fires such an event when a connected peer's camera stops mid-call is not
  measured: browsers commonly freeze a `<video>` on its last frame and keep reporting that
  frame's intrinsic size, in which case nothing would fire and the tile would stay on a frozen
  frame instead of returning to the peer's initials. `call-no-permission.spec.ts` only proves
  the "never had a camera" case (a real browser refusing `getUserMedia` up front), not a camera
  that was live and then turned off. Needs a real two-peer e2e case that starts with video,
  stops the track mid-call, and asserts the initials return.
- **Headset auto-takeover depends on `groupId`, which iOS Safari may not populate (C3e-b).** The
  device-swap rule only adopts a newly-arrived default when the in-use track and the candidate both
  report a `groupId` and the two differ — deliberately failing closed, since the alternative
  interrupted working calls on every unrelated `devicechange`. But `track.getSettings().groupId` is
  not guaranteed on Safari, the browser this phase exists for. If Safari omits it, auto-takeover
  silently never fires there and the Lobby picker is the only route. Unverifiable here: no Apple
  device. Watch whether `device-lost` rows ever arrive from Safari user agents.
- **The `100vh` guard scans two directories, not the whole tree (C3e-b).** `viewport-units.test.ts`
  walks `src/routes` and `src/features/call`. `src/features/shell/AppShell.tsx` and
  `src/ui/auth-layout.tsx` also establish page height and sit outside that scan — both correct
  today. The "a container nobody pointed the check at" failure is narrowed, not eliminated; the
  root container that defeated the original fix was exactly this class.

- **The deploy's file sync now downloads its own binary, unchecksummed.** `appleboy/scp-action`
  v1 is a composite action: instead of running a pinned Docker image, it `curl`s the `drone-scp`
  binary onto the runner at deploy time (default v1.8.0, GitHub releases, no checksum). The action
  tag is pinned, the thing it fetches is not. This is the step that carries `turnserver.conf` to
  the VPS, so a compromised or substituted binary is a path to an unfenced relay. Closing it means
  either pinning `version:` and verifying a hash, or vendoring the binary — neither is a 15-second
  change, and the same exposure exists in `appleboy/ssh-action`, which is built the same way.

- **A signaling socket that never opens and never closes leaves the room saying "Connecting…"
  forever (C3d).** `useSignaling` only begins counting failures from a close event, so it reaches
  `MAX_RECONNECT_ATTEMPTS` and the `lost` state only if the socket *opened and then dropped*. A
  relay that is unreachable from the start — DNS gone, certificate rejected, a silently blackholed
  connection — produces no `onclose`, so nothing ever surfaces. The other half of this finding (a
  socket that opens and later dies) IS handled, with copy and a retry control. Closing this needs a
  connect-timeout with a chosen value and a test; it was deliberately not bolted on untested during
  the C3d fix wave.
- **Retrying a failed connection silently reverts the chosen camera and microphone (C3d).**
  `RoomPage.handleRetryConnection` calls `localMedia.retry()`, which re-acquires with
  `DEFAULT_CONSTRAINTS` rather than the `deviceId` the person picked in the lobby. So someone who
  chose their good camera, hit a connection failure and clicked "Try again" gets the default one
  back with no indication. Only reachable now that the retry path and the device wiring both exist.
  Fix: have `retry()` reuse the current selection.

- ~~**Signaling reads only the first `Sec-WebSocket-Protocol` header line (C3c).**~~ **FIXED
  2026-09-13** (backend #58) — `getlist()` joins them. Tested against the PARSER, and the test
  says why: neither a browser nor Starlette's TestClient can produce the repeated form, so the
  assumption was untestable through the front door. That is how it stayed invisible.
- ~~**A reversed subprotocol offer is treated as no offer (C3c).**~~ **FIXED 2026-09-13**
  (backend #58). Still REFUSED — the order is part of the contract — but the refusal now
  carries 4401 instead of a generic handshake error. The close-code vocabulary exists so a
  client can tell auth failure from a network fault.
- ~~**`stuns:` URLs would be given a TURN credential (C3c).**~~ **FIXED 2026-09-13**
  (backend #58) — pinned BEFORE the `turns:` work adds the first such URL, which is the only
  time it is cheap.
- **`.env.production.example` had a stale comment referring to `WS_DOMAIN` (C3c), now doubly
  stale.** It used to say the variable "was retired and replaced by
  `WS_BLUE_DOMAIN`/`WS_GREEN_DOMAIN`" — backwards as of ADR-0037, which collapsed signaling back
  to a single shared `WS_DOMAIN` and retired the per-colour pair instead. Fixed as part of the
  shared-signaling change; flagging here in case any other doc still has the C3c-era phrasing.

- **On a phone, the session card's Join stretches full-width but Cancel does not.** Verified on
  staging 2026-09-08 at 390x844: the actions container stacks correctly (96px tall vs 44px in a
  row at 1280px), but `JoinButton` carries `w-full sm:w-auto` while `CancelSessionDialog`'s
  trigger has no width class, so it renders 81px wide under a 324px-wide Join. Reads as
  unbalanced rather than deliberate. Either give Cancel the same treatment or drop it from Join.
  Cosmetic only — no test can see it, which is why it took a human-style look to find.

- **`GET /api/v1/scheduling/slots/` and `/quota/` return 404, not 403, for a student with no
  subscription.** Both routes exist (confirmed against the deployed URLconf), so the 404 is the
  view expressing a business state as "not found". Every schedule page load for such a student
  logs two console errors, which is noise in its own right and a red herring for anyone
  debugging a real routing problem later. Pre-existing, unrelated to the session UI redesign;
  observed 2026-09-08. Adjacent to the entry above about these queries firing for the wrong
  audience.

- **Changing `WS_DOMAIN` on the VPS strands any `ACTIVE` `Room` (ADR-0037).** `Room.signaling_url`
  is pinned at creation and `_ensure_room` reuses an `ACTIVE` row forever, so an operator who edits
  `WS_DOMAIN` without first ending active rooms leaves those sessions permanently unjoinable —
  same failure class ADR-0037 fixed for deploys, reopened for this one operator action. Documented
  as a required step in `docs/runbook/signaling.md`, not fixed in code: a recurring deploy-time
  room-ending job is exactly the "treat the symptom on a schedule" design ADR-0037 rejected.

- **`mypy` is red and nothing notices — and it is bigger than this entry used to say.**
  Re-measured 2026-09-13: **14 errors in 5 files**, not the one in `config/settings/local.py`
  this entry named (that line has also moved, 61 -> 80). The spread:
  `tests/stripe_clock/test_renewal_dunning.py` 8 (mostly `datetime | None` arithmetic),
  `tests/stripe_clock/conftest.py` 2, and one each in `config/settings/local.py`,
  `config/settings/test.py` and `kaleem/scheduling/tests/test_diagnostics_api.py` (the settings
  three are all the same root cause: `LOGGING`/`REST_FRAMEWORK` imported from `base` are typed
  `object`, so subscripting or unpacking them errors).
  Still red in neither `ci.yml` nor pre-commit nor `just lint` — it is a manual command.
  **The choice is unchanged and is an owner decision, not a drive-by:** fixing the 14 has no
  durable value unless mypy also enters the merge path, because nothing would stop the 15th;
  and putting it in the merge path is a standing cost on every PR. Fix AND gate, or stop
  calling it a gate. Measured here so the decision has real numbers.

- ~~**`docs/runbook/deploy.md` still calls the deploy script `scripts/deploy.sh`.**~~ **FIXED
  2026-09-13** — every reference now says `scripts/ship.sh`, so the commands survive a
  copy-paste.
- **The C3a e2e is time-bombed on seed age.** `seed_e2e_matching` puts the joinable session at
  `now`, and its window closes 75 minutes later. A suite run long after seeding would find the
  button still enabled but the POST returning 409. Fine in CI, which seeds immediately.
- **`call.spec.ts`'s "the lobby has a way back" measures 44px with zero tolerance, and it is
  runner-sensitive.** Failed on meta#221 at **43** (initial run AND the automatic retry, so
  stable within the job), then **passed in 1.6s on a fresh runner at the identical commit**.
  Ruled out as a code cause first: the same test passed on the previous run, the diff between
  the two dashboard SHAs is seven files touching curriculum queries, the invite card and two
  locale strings — nothing in the call UI or any global CSS — and the built CSS is correct
  (`.h-11{height:calc(var(--spacing) * 11)}` with `--spacing:.25rem` = 44px).
  **The assertion is stricter than the standard it cites.** SC 2.5.8 requires **24**px; 44 is
  the Apple HIG preference, so a 43px render fails this gate while violating nothing. And
  `expect(Math.round(box.height)).toBeGreaterThanOrEqual(44)` on an `h-11` element leaves no
  room for any sub-pixel factor on a given runner.
  **Do:** make it hit-test the way `touch-targets.spec.ts` does — which exists precisely
  because `boundingBox()` returns the PAINTED box and a geometry gate misjudges correct
  components — or state a tolerance and say why. Deliberately NOT changed in passing:
  loosening a merge gate's threshold inside a PR about something else is how a gate quietly
  stops meaning anything.

- **`availability.spec.ts` failed once in local e2e (2026-09-05), then passed on a clean re-run.**
  The failing run overlapped a manual browser session signed in as `e2e.teacher` against the same
  database, which is the likely cause rather than a defect in the spec — but it is unproven, and a
  shared-account suite has no isolation to fall back on. Watch for it in CI.
- **The transactional-test reseed fixture is a hand-maintained mirror of two data migrations.**
  Still true and still un-enforced. **One half was fixed 2026-09-13** (backend #63): the fixture
  was SESSION-scoped, so it repaired the seeded rows for the next RUN and not between tests
  within one — which held only while the suite had exactly ONE transactional test. Adding a
  second exposed it, and which test broke depended on collection order. Now function-scoped and
  idempotent at both ends. The hand-mirroring of the migrations, and the missing link between
  them, is unchanged.
- ~~**`RoomAdmin` blocks adding but not deleting.**~~ **FIXED 2026-09-13** (backend #56),
  with the test for the read-only intent this entry noted was missing. Deleting a room severs a
  lesson from the only record of where it happened; rooms END, they do not disappear.
- **The 409 copy on a closed room says "not open yet".** `isOutsideJoinWindowError` maps every
  409 to the not-yet-open message, so leaving the schedule open past a lesson's end and clicking
  Join tells the user the room has not opened when it has closed. The client knows `starts_at`
  and `duration_minutes` and could pick the right copy without a machine-readable error code.

### Phase C2 (booking + quota) — deferred findings

Logged 2026-09-05 from C2's task reviews, its browser pass and its final whole-branch review.
None blocks the phase; each was reviewed and consciously deferred.

**Blocks launch — read this one before touching billing:**

- ~~**`Session.cycle_end` is matched by exact `DateTimeField` equality, so a mid-cycle rewrite
  of `current_period_end` would silently zero a student's usage.**~~ **FIXED 2026-09-13**
  (backend #52). The test this entry named was written first and went red in exactly the
  predicted shape: moving `current_period_end` forward by **one second** on a four-lesson plan
  generated **four extra lessons**. A session now counts if EITHER its stored `cycle_end` is
  the one billing reports now, OR that instant has not yet passed. The second clause absorbs
  the rewrite and is strictly more inclusive than equality, so the failure it replaces —
  handing out units already spent — is not reachable through it; a cycle that has ENDED stops
  counting on its own, which is what still returns a student's allowance on renewal (covered
  by its own test in the opposite direction). Keying on a derived cycle id was the other
  candidate and is the larger change: `Subscription` mirrors no `current_period_start`, so
  there is no second bound to derive an id from without a billing migration.

**The C2 scoping cluster — one root cause, three symptoms:**

- `claim_slot(actor, weekday, start_time)` carries **no parameter naming the student or the
  subject**. Consequently: a student with two subjects cannot book at all (refused loudly rather
  than guessing which subject a lesson belongs to); a **parent cannot claim or end** a weekly time
  or see a quota counter; and `GET /slots/` had to be narrowed to students. Adding that parameter
  is the single fix for all three.

**The rest:**

- **A future `end_assignment` will strand an ACTIVE slot.** Generation filters on an ACTIVE
  assignment, so an ended one stops generating — but its slot stays ACTIVE and keeps the teacher's
  time blocked by `unique_active_teacher_slot` forever. Unreachable today (nothing writes
  `TeacherAssignment.Status.ENDED`); a trap for whoever adds that path.
- **The concurrent-claim 409 is reasoned, not tested.** The delivered test is sequential; the lock
  argument is sound, but nothing would catch `select_for_update` being removed. Same shape as C1's
  untested accept race — both want a `TransactionTestCase` with two threads.
- **A Family plan's per-child allowance holds by construction but has no two-sibling test.**
- **Dialog styling is now inconsistent within one feature.** `ClaimSlotCard` uses
  `w-full max-w-sm`; `SessionList` and billing's `CancelSubscriptionDialog` still use
  `w-[min(90vw,24rem)]` with transform centring. Unify all three. Related: **no `overlay`/scrim
  token exists**, so `bg-black/40` is hardcoded in several dialogs.
- **`claim_slot` duplicates `slot_options`' fitting and conflict computation** rather than reusing
  it — fewer queries, two places to keep in step.
- **`isNoActiveSlotError` is byte-identical to `isNoEntitlementError`**, justified by semantic
  distinctness; they could silently diverge if either endpoint's status changes.
- ~~**`NotFoundError("Recurring slot", request.user.id)` echoes the user id.**~~ **FIXED
  2026-09-13** (backend #56). `identifier` is now optional: the slot does not exist, so there is
  no id to name, and the user-visible body no longer reads a USER id under a slot's noun.
- **The multi-subject 400 detail renders the server's raw English string**, unlocalised — matching
  the existing claim-mutation pattern. Wants an i18n pass.
- **Feature naming diverges across repos:** the backend puts booking inside `scheduling`; the
  dashboard adds `features/booking/` beside an existing `features/scheduling/`.
- Smaller: a teacher-and-parent sees their own name echoed on rows they teach; the seed prints
  "Opened 2 request(s)" though one is immediately accepted; a tautological fixture assertion; e2e
  name assertions use `.first()`; the inside-24h cancellation copy is unit-tested but never
  verified in a browser; sequenced queries show two consecutive spinners.


### Phase C1 (matching) — deferred findings

Logged 2026-09-05 from C1's task reviews and its final whole-branch review. None blocks the
phase; each was reviewed and consciously deferred rather than missed.

**Worth doing sooner than the rest:**

- ~~**The accept race's lock is unproven by any test.**~~ **FIXED 2026-09-13** (backend #63) —
  two threads, a barrier, and a slow eligibility check holding the window open.
  ⚠ **The first version of that test was ALSO worthless**, and the mutation check is the only
  reason it is not in the repo: asserting "the loser got a typed error" PASSES with the lock
  deleted, because without it both threads reach the INSERT and the unique index refuses one —
  which `accept_offer` now converts into a `ConflictError` too. Same type, different mechanism.
  The MESSAGE separates them, and the assertion names which one refused when it fails.
- **`/account` overflows horizontally in Arabic** — `scrollWidth` 1162 vs `innerWidth` 1018
  (144px); clean at 1003/1018 in English. Traced to the "Preferred teacher gender" radio group's
  visually-hidden inputs using a physical `left:-159px` instead of a logical inset. This is a
  WCAG 1.4.10 Reflow (AA) failure on a page C1 adds a card to. Belongs to identity/curriculum.
- ~~**N+1 in the teacher inbox.**~~ **FIXED 2026-09-13** (backend #57). Measured at **23
  queries for five offers**, now **7 and constant**: the teacher's own availability was re-read
  per row, and the student read and preference lookup were a query each. Batched via new
  `identity.services.get_users` / `get_student_preferences` and `to_utc_intervals_for`, which
  shares its conversion with the singular form so the two cannot drift. The test asserts
  CONSTANCY (two rows vs six must cost the same) rather than a budget, and is mutation-checked:
  reverting the hoist reports `11 for 2 offers, 19 for 6`.
- ~~**`is_eligible` and `list_offers_for` assemble the same three filters separately.**~~
  **FIXED 2026-09-13** (backend #57). Both now call `_passes_hard_filters`, which takes VALUES
  rather than objects so the bulk path and the single path share one rule without it knowing
  the difference. A test asserts set-equality between the two over every open request, so it
  fails whichever side drifts — the exact failure this entry predicted.
- **Withdrawing a subject interest never closes the open match request.** Nothing writes
  `MatchRequest.Status.CANCELLED`, yet the enum member exists and `MyMatchRequestsView`
  `.exclude()`s it as though something did. A student who un-ticks Quran stays broadcast for it.
  Ruled out of C1 scope (the spec's cancellation story is OQ-C1-2: staff act in Django admin).
- **A rematched student can see "Your teacher:" with a blank name.** After staff end an
  assignment, the old `MATCHED` request survives while the name is joined only from *ACTIVE*
  assignments.
- ~~**The `unique_active_assignment` backstop would surface as a 500.**~~ **FIXED 2026-09-13**
  (backend #61). Now a `ConflictError`: the user-visible outcome should not depend on which
  layer noticed, and the identical situation one line earlier already reported a 409.
- ~~**A teacher who declined an offer can still accept it.**~~ **CLOSED AS INTENDED 2026-09-13**
  (backend #61) — the entry's actual complaint was that "nothing says so", and now something
  does. Pinned by a test that argues the case: a teacher who declines and changes their mind has
  no other route back to a student who is still waiting, so declining means "not now, hide it",
  not a promise the platform enforces against the person who made it. Turning it into a real
  prohibition is now a deliberate decision rather than a silent behaviour change.
- **`_today()` uses `timezone.localdate()`,** correct only because `TIME_ZONE` is `"UTC"`; the
  overlap engine is UTC-instant-based and does not consult Django's zone.
- **`MatchOfferAcceptView` rebuilds the assignment projection by hand** rather than reusing
  `list_assignments_for`'s shape — a second place to keep in sync.
- **The reconciler's per-read cost grows with students who never subscribe** — an unentitled
  student's pair is never taken and never open, so it costs a `get_user` + `is_entitled_to` on
  every inbox and `/account` load, forever.
- **Zod schemas in the dashboard are defined but never `.parse()`d** anywhere — a repo-wide
  pattern, so the runtime-validation value of using zod is currently unrealised.
- **`SubjectsCard`'s whole-card loading gate exists partly for the e2e harness's benefit**, and
  introduces a layout shift (loading and empty both render nothing, then the card appears).
  `dirtyRef` also never clears on a net-zero edit.
- **Arabic copy wants a native-speaker pass** — `نحن نبحث لك عن معلم` is grammatical but less
  idiomatic than `نحن نبحث عن معلم لك`.
- **Pre-existing pytest warnings**: 7 in `scheduling`, 155 backend-wide. Test output should be
  pristine.

### Lighthouse findings on staging (nightly, `lighthouse.yml`)

Measured 2026-09-04 by the first run (ADR-0030). The floors in `.lighthouserc.json` sit
just below these, so none of them is red today — each is what stops a category reaching
100.

- **`app-staging` performance sits ON its floor.** Measured 2026-09-12: 0.94 / 0.95 / 0.95
  across three runs against a 0.95 floor. The assertion passes on the median, but one run in
  three is already under it — one regression from a flaky nightly. The cause is known and
  unaddressed: a single 862 KB JS chunk, warned about at every build.
- ~~**Marketing SEO should now measure higher than its floor.**~~ **DONE 2026-09-13.**
  Marketing now measures **1.00 on all four categories**. The floors are global across both
  URLs, so they can only rise to the *lower* of the two: best-practices 0.75 → **0.96** and
  SEO 0.80 → **0.82**, both limited by `app-staging`. Performance is deliberately NOT raised —
  it measured 0.94/0.95/0.95 and is the one noisy category. Raising a global floor to
  marketing's own 1.00 needs per-URL assertions (`assertMatrix`), which is a config change
  worth making only if the two sites' scores keep diverging.
- ~~**Marketing has no type-check in CI.**~~ **ALREADY FIXED — entry was stale, verified
  2026-09-13.** `marketing-build` runs a `Type-check` step (`pnpm check` → `astro check`) ahead
  of the build; it landed with design-system v2's gate G7.
- ~~**`app-staging` login page: colour contrast fails** (a11y 96).~~ **CLOSED 2026-09-12.**
  Re-measured after the design-system v2 palette deployed: accessibility is **1.00** on both
  `app-staging.kaleem.academy/login` and `staging.kaleem.academy`, 3 of 3 runs each. The
  `.lighthouserc.json` a11y floor is raised 0.95 → **1.00** accordingly (ADR-0026 ratchet).
  ⚠ A floor of 1.00 has no headroom by construction: any new Lighthouse a11y finding turns the
  nightly red immediately. That is the intent — the floor was raised to the measured value,
  not to something comfortable.
  ⚠ **Lighthouse 1.00 is not a clean bill of health.** It is a weighted subset of automated
  audits, run against the DEFAULT theme. A real-browser axe sweep of the same pages on the same
  day found a live 1.4.3 failure on `text-primary` links in dark mode (see "Blocks launch")
  that Lighthouse scored 1.00 straight through.
- **`app-staging`: the console "errors" are EXPECTED, and this is now settled.** Read from
  the 2026-09-13 report: both entries are `403` from `GET /api/v1/identity/me/` on the login
  page. That is the app's own `redirectIfAuthed` probe asking "is this visitor already signed
  in?", and 403 is the right answer for an anonymous caller. A browser logs every failed
  request and JavaScript cannot suppress it, so `errors-in-console` cannot pass while the
  probe exists. **Not a defect.** Changing the endpoint to answer 200 with
  `{authenticated:false}` would silence it at the cost of a worse API contract — don't,
  unless something else wants that shape. `robots.txt` for an authed app remains a real
  decision nobody has made.
- ~~**Both sites: `deprecations` fails** (best-practices).~~ **STALE — no longer failing.**
  Checked in the 2026-09-13 report, which is what the entry asked for: marketing scores 1.00
  with nothing failing, and `app-staging`'s only best-practices failures are
  `errors-in-console` and `valid-source-maps` (both below). Whatever the deprecated API was,
  a dependency upgrade removed it.
- **`app-staging`: missing source maps for large first-party JS — still a DECISION, not an
  oversight.** Confirmed 2026-09-13: `valid-source-maps` fails on the one large first-party
  bundle. Three options, and the difference is who can read the source:
  (a) `build.sourcemap: true` — serves maps publicly, passes the audit, makes the app's
  source readable by anyone;
  (b) `sourcemap: "hidden"` — generates maps with no `sourceMappingURL` comment, so browsers
  never fetch them; upload them to Sentry to get readable stack traces. **The audit still
  fails**, because there is nothing for Lighthouse to follow;
  (c) leave it.
  (b) is almost certainly what is wanted — it buys the Sentry traces, which is the part that
  has real value — but it means accepting that this audit stays red, so the
  best-practices floor cannot rise past 0.96 until (a) is chosen. Needs an owner decision.

### Stripe dunning harness (nightly, `stripe-clock.yml`)

Surfaced by the final review of the harness on 2026-09-04. None affects what the harness
proves; all are robustness of an unattended job.

- **`process.stdout.readline()` in the CLI readiness scan blocks unboundedly.** The deadline
  is only checked between lines, so a `stripe listen` that emits nothing hangs until the
  30-minute job cap — losing the named 60s diagnostic *and* skipping the `finally`, which
  leaks the test clock. A reader thread or non-blocking pipe would fix it.
- **No stale-clock sweep.** Any hard kill (the above, or the job timeout) skips both
  `finally` blocks and leaks a clock plus its customer with no signal. A "delete clocks named
  `kaleem-dunning-harness`" step at job start would make the leak self-healing.
- **The delivery probe asserts only `StripeEventLog.count() > before`.** `stripe listen`
  forwards *all* account events and the account is shared with staging, so a concurrent
  staging event could satisfy it. Delivery and signature verification are still genuinely
  proven; the assertion is just looser than it reads.
- **The Stripe API key is passed on argv** (`stripe listen --api-key …`), so it is visible in
  the runner's process table. `STRIPE_API_KEY` in the environment would be tighter. Log
  exposure is already covered — GitHub masks the secret.

### Backend

- Email security alerts dispatch via `send_email_message.delay(...)` *inside*
  `@transaction.atomic` (`identity.services.add_email_address` / `set_primary_email`). In
  prod the worker can pick the task up before commit. The clean fix is
  `transaction.on_commit(...)`, but that breaks pytest-django's non-committing test
  transactions. Decide deliberately (e.g. `on_commit` + `django_capture_on_commit_callbacks`).
  Low harm today — the alert only fires after all validation passes.
- ~~`identity.services._send_email_security_alert` picks the body with an `else` fallback.~~
  **FIXED 2026-09-13** (backend #53) — it matches `action` exhaustively and raises on an
  unknown one, with a test. Adding the two password actions is what made it urgent: a typo at
  a new call site would have told every user the wrong reason for a change to their own
  credentials.
- `/me/emails/` `@extend_schema` documents success responses only, not the 400/404 shapes.
  Worth a sweep across the identity module.
- ~~`billing.services.get_current_subscription` lacks `select_related("plan")`.~~ **FIXED
  2026-09-13** (backend #56).
- ~~`WeeklyAvailability.weekday` is only service-validated (0..6), not DB-constrained.~~
  **FIXED 2026-09-13** (backend #56) — a `CheckConstraint`, because the database is the only
  place a rule holds for every writer, a Django shell included.
- **tz-awareness is partial:** availability is stored/edited in the owner's timezone and
  `to_utc_intervals` converts for a reference week, but DST exactness and multi-tz-per-user
  are out of scope (documented in the spec). Revisit when the matching feature lands.

### Dashboard

- ~~**The touch-target sweep does not model SC 2.5.8's *inline* exception.**~~ **FIXED
  2026-09-13** (dashboard #65) — and the fix reversed the finding. The sweep now implements
  the exception structurally (inline-level, with non-target text in the parent), then was
  pointed at the four real auth routes, where it reported the standalone links as failures
  anyway. **It was right and this entry was wrong:** those links are the SOLE content of
  their own paragraph, so no non-target text constrains their height and the exception does
  not apply — which is precisely when 2.5.8 requires the target to be enlarged. All are now
  19px of ink inside a 25px target via `inlineTapTarget`, the same pseudo-element technique
  as `Button size="sm"` and `Checkbox`.

- **`/design-preview`'s LIGHT panels inherit the app's theme, so with the app in dark mode
  the page shows dark x4.** Only the dark panels carry a wrapper class (`.dark`); the light
  ones rely on `:root` being light, and `@kaleem/tokens` defines `:root` + `.dark` with no
  `.light` scope to opt back in. Measured on staging 2026-09-13 with the app in dark mode:
  `preview-light-ltr` resolved `--background: #191c1b` and `--primary-text: #9fd0bc` —
  byte-identical to the dark panel.
  **CI is NOT affected and the gate already knows:** `e2e/design-preview.spec.ts`'s "each mode
  panel renders in the theme and direction it claims" asserts ground luminance per panel
  (<0.3 dark, >0.7 light), so a dark-themed run turns red rather than passing quietly. The gap
  is the HUMAN case — someone opening the page on staging to review the palette gets no signal
  that half of what they are looking at is the wrong theme, which is exactly what happened
  during the 2026-09-13 walk. **Do:** either add a `.light` scope to the token package (a
  release + re-pin, which is why it was not done in passing) or render an in-page warning when
  `:root` is dark. The portal caveat beside it — Radix dialogs escaping the scoped wrapper —
  is already documented in the route's own header comment and is working as described.

- **No `Sheet` primitive.** `AppShell`'s mobile drawer is the only side-panel in the app, so
  design-system v2 P2b deliberately left it on raw Radix rather than inventing a primitive for
  one call site. It takes the shared `bg-overlay` scrim token; only its layout is its own. If a
  second drawer ever appears, that is the moment to extract one — not before.
- **`DeviceCheckDialog`'s elevated treatment is either right for every dialog or wrong for this
  one.** P2b converged it onto the shared `Dialog` and dropped its unargued divergences
  (`rounded-2xl`, `bg-popover`, `shadow-xl`, a ring instead of a border). The one difference with
  a stated reason — a blurred scrim, because live video behind it keeps moving through any
  opacity — survived as the `scrimBlur` prop. Decide whether the elevated look should become a
  `Dialog` variant, or stay gone.
- ~~**`focusRing` has no `secondary` surface.**~~ **ALREADY FIXED — entry was stale, verified
  2026-09-13.** `FocusSurface` carries `"secondary"` and the contrast manifest asserts `ring`
  against it.
- **P9 — the 20 raw `<button>` elements outside the primitive.** Explicitly NOT swept by
  design-system v2 (audit, don't sweep): many are legitimate in-place icon controls. Audit them
  opportunistically, one at a time, when already in the file.

- ~~`/availability` has no in-component teacher gate.~~ **FIXED 2026-09-13** (dashboard #70).
  Gated inside the page rather than at the route, so it is testable without a router and so
  `useAvailability` can be called DISABLED — hooks cannot be conditional, but the request can
  be. A bare 403 reads as the app being broken rather than the page not being yours.
- `parseApiError` lives in `features/identity/api.ts`; promote it to `src/lib` so other
  features don't cross-import identity.
- ~~The child-create/preferences payload still sends `time_preferences: []` (harmless).~~
  **WRONG, and the reality was silent data loss. FIXED 2026-09-13** (dashboard #69).
  `EditChildPreferencesDialog` rendered a FULL preferred-times editor — fieldset, day/start/end
  selects per slot, remove buttons, an Add slot button, per-slot validation with translated
  messages. The endpoint reads **only** `teacher_gender_preference` and the column was dropped
  in identity migration 0006, so a parent could add slots, watch them validate, save
  successfully, and have every one discarded. Nothing failed, so nobody was told.
  **Two existing tests drove that editor and asserted the payload contained the slots** — they
  passed, and they encoded the illusion as correct behaviour. That is the third time today a
  green test was protecting nothing. The control is gone, because one that accepts input and
  throws it away is worse than none: the parent believes the times are set. Editing a child's
  real availability remains a genuine missing feature with its own entry.
- `TimezoneBar` picker has no Escape-to-close, and its listbox `aria-label` reuses the search
  label.
- `WeeklyAvailabilityEditor` pill React key collides on two identical ranges in one day
  (cosmetic; the backend merges them on save).
- ~~Two buttons on `/family` share the accessible name **"Add child"**.~~ **WRONG, and the
  measurement found a real defect underneath it. FIXED 2026-09-13** (dashboard #66). The two
  buttons never coexist: the disclosure is REPLACED by the form, so exactly one is in the DOM
  at a time (counted, then pinned by a test). Renaming the submit — what this entry asked for —
  would have changed user-visible copy for no accessibility benefit at all.
  What the same probe DID find: because the button the user just activated is removed,
  `document.activeElement` falls to `<body>`, so a keyboard or screen-reader user is dropped at
  the top of the document with no signal that a form appeared — **twice per add**, once on open
  and once when success unmounts the form. That is **SC 2.4.3 Focus Order** and it was logged
  nowhere. `/account`'s add-email card had the identical shape and the identical defect; this
  entry asked for it to be checked, and it was. Both now autofocus the first field on the way
  in (safe here precisely because the form only ever mounts on the user's own click) and
  restore focus to the disclosure on the way out.
  **The lesson is about this file, not that card:** a D10 entry records a symptom and a guess
  in 15 seconds, and the guess is often wrong — this is the second one today, after the reflow
  bug that was blamed on the availability editor and turned out to be the topbar. Probe before
  trusting an entry.
- Shell CSS padding drift: `UserMenu` uses logical `ps-/pe-`, `AppSidebar` uses symmetric
  `px-` (both RTL-safe). Unify on logical.
- Topbar brand wordmark is a plain `<span>`, not a `<Link to="/">`. Make it and the
  auth-layout span links in one pass.
- `features/identity/schemas.ts` has two near-identical child shapes — `ChildSummary` (the
  `/me`-embedded one) and `Child` (the `/children/` list shape). Unify once the child surface
  settles.
- ~~`InviteCard`'s copy button calls `navigator.clipboard.writeText(...)` with no `.catch`.~~
  **FIXED 2026-09-13** (dashboard #68). Accurate as written, and reproduced before fixing —
  the new test went red with vitest reporting the unhandled rejection itself. There were two
  failures, not one: the unhandled rejection, and a button that silently STAYED on "Copy", so
  the user could not tell a failed copy from a slow one. The message now says to select the
  code by hand, because the code is still on screen and reporting only "failed" would leave
  the user stuck beside a working alternative.
- `StudentPreferencesCard`: the per-row validation message is a sibling `<p role="alert">`,
  not `aria-describedby`-linked to the offending input, and the time inputs carry no
  `aria-invalid`. Also the "required times" message anchors on `end_time` even when
  `start_time` is the empty one. And it hand-rolls a `SELECT_CLASS` string replicating the
  shadcn `Input` classes — replace when a `Select` primitive lands in `@/ui`.
- ~~`verify-email.tsx`: the `started` ref and a vestigial `onVerified` prop.~~ **ALREADY FIXED
  — entry was stale, verified 2026-09-13.** No `onVerified` exists anywhere in `src`.
- ~~`?checkout=cancelled` never clears from the URL.~~ **FIXED 2026-09-13** (dashboard #69).
  What to render is frozen at first render BEFORE the URL is cleared — without that the banner
  would vanish the instant it appeared, since the param is what renders it.
- ~~Dead i18n keys after the billing promotion.~~ **FIXED 2026-09-13** (dashboard #69) —
  `billing.subscribed`, `modules.billing`, plus the nine `prefs.*` time-slot keys the deleted
  child editor was the only consumer of. Each verified at zero call sites first.
- Arabic `_few`/`_many`/`_other` plural categories for the plan-session copy are verified via
  `Intl.PluralRules` but only the dual (`_two`) has a rendered test.
- `SubscriptionCard`'s history list includes the current subscription as its first row and is
  hidden entirely for a lapsed user; `useDateFormatter` builds a fresh `Intl.DateTimeFormat`
  per call.
- ~~The cancel dialog's `bg-black/40` overlay is a non-token colour.~~ **ALREADY FIXED — entry
  was stale, verified 2026-09-13.** `grep -rn "bg-black/" dashboard/src` returns nothing; the
  per-theme `--overlay` token landed with the `Dialog` primitive and was confirmed rendering as
  `#191c1b8c` light / `#000000ad` dark during the staging walk.
- **A `secondary` button is nearly invisible as a SURFACE against the page.**
  `--secondary` on `--background` measures **1.09:1** in light (it was 1.13:1 on
  v0.1.1, so this is pre-existing and only marginally worse, not a v2 regression);
  dark is 1.75:1. `Button variant="secondary"` carries no border, so on a page
  background the control has no identifiable boundary — arguably SC 1.4.11, which
  wants 3:1 for a UI component boundary. Text contrast is fine (11:1+), and axe does
  NOT catch this: its colour-contrast rule is text-only. On `--card` it reads better.
  **Do:** decide between giving `secondary` a border and darkening the token — a
  decision about the scale, not a sweep. (Spotted 2026-09-12 in the /design-preview
  visual pass.)
- **`StatusChip tone="warning"` paints `bg-destructive`.** A chip literally named
  "warning" renders in the destructive colour, while the `--warning` token — which
  passes AA at 4.74:1 in light — goes completely unused. Colour conveying the wrong
  severity. Pre-existing (`src/ui/status-chip.tsx`); visible now that the preview
  route renders all three tones side by side. Trivial fix, but it changes what users
  see, so it is a decision not a drive-by. (Spotted 2026-09-12.)
- **20 raw `<button>` elements live outside the `Button` primitive.** Audit, do not sweep:
  many are legitimate in-place icon controls that are not `Button` variants, and a blanket
  conversion is the D10 refactoring spree. Convert only true duplicates, opportunistically,
  when already in the file. The clearest real duplicate is `ExitToSchedule.tsx:33`, a
  fully hand-rolled pill (h-11, rounded-full, own ring, own focus recipe).
  (Spotted 2026-09-12 during the design-system v2 audit; deliberately left out of that plan.)
- ~~The room route (C3d) has two `<h1>`s at once during the Lobby state.~~ **ALREADY FIXED —
  entry was stale, verified 2026-09-13.** C6 demoted `Lobby`'s heading to `<h2>` and pinned it
  with a test (`Lobby.test.tsx`, "is a section of the room, not a second page") that also
  asserts no `level: 1` heading remains. Closed on reading the code rather than on trusting
  the entry — the fourth stale-or-wrong entry found today.
- **A rejected `sender.replaceTrack()` is swallowed, not reported (C3e-b).** The rejection is
  now caught (an unhandled rejection would fail `call.spec.ts`'s `pageerror` listener on a
  lesson that is still running), but nothing is recorded: no diagnostic code fits, and the
  vocabulary is deliberately closed (adding one needs a backend enum change and would fail the
  e2e contract test that pins the client's code list to the backend's). Accepted: a failed swap
  leaves the previously negotiated track in place — degraded, not broken — and narrower than the
  swap failing to happen at all, which is what the fix's own test proves does not occur.
- **A microphone-only device swap also re-acquires video, so plugging in a headset briefly
  blinks the camera (C3e-b).** The hot-swap path re-runs `getUserMedia` for both kinds even
  when only one changed. Cosmetic — the camera track is the same track afterwards — the
  correctness half (the microphone actually swaps) is handled.
- **The e2e gate cannot see the relay path (C3d).** `call.spec.ts`'s two flows run with no
  coturn in CI, so they only prove host-candidate peer-to-peer connectivity with fake media.
  The relay path (real NAT traversal, real audio/video) is covered by C3c's one-time live
  verification on staging, not by anything that runs on every merge. See the D3 table row in
  `CLAUDE.md` and `docs/runbook/video-call.md`.
- **`call.spec.ts`'s `pageerror` assertion is a stopgap, not a durable guard (C3d).** It only
  catches the single-offerer regression because nothing currently `.catch`es the rejection
  `sendOffer`/`sendAnswer` throw on misuse (both are fire-and-forget IIFEs). A future tidy-up
  that adds a `.catch` anywhere in that chain would silently blind this assertion with no edit
  to the spec itself to flag the coverage change. The durable pin is the unit-level call-count
  tests in `usePeerConnection.test.ts`; treat the e2e `pageerror` check as a bonus, not the
  guard.

---

## Known-good gotchas (not bugs — read before panicking)

- **Dashboard tests look catastrophically broken under memory pressure.** During the billing
  build, agents running full suites plus throwaway Postgres containers concurrently saw ~55
  failures across 16 files, all `localStorage`/`window` undefined in jsdom 29
  (`src/ui/toggles.test.tsx` and others) — the jsdom environment failing to initialise, not a
  code defect. Re-verified twice on a clean tree: green. If it reappears on a loaded CI runner
  or a busy dev box, suspect resources (or cap `poolOptions.threads.maxThreads`) before
  suspecting the tests.
- **`.gitleaksignore` is not empty, and must not be emptied.** The credentials it
  fingerprints were rotated 2026-09-05, but rotation makes a credential *dead*, not
  *absent* — the strings are still in git history, so deleting the lines makes gitleaks
  report them again and turns CI red on every branch. ADR-0030 said to remove a line once
  rotated; **ADR-0032 amends that**. The file is a rotation record now. Only a history
  rewrite could empty it legitimately, and that is rejected.

- **The Stripe API version is now pinned explicitly, and it must stay that way.**
  `DJANGO_STRIPE_API_VERSION=2026-08-26.dahlia` is set on staging, and the webhook endpoint
  `we_1UBdRwCavwnriKDQ2ygx6z2V` was created at that same version (2026-09-03). Do the same in
  every new environment — **production included** — or the two sides drift.

  This is not theoretical. Watched live on 2026-09-03: the SDK's default moved from
  `2026-07-29.dahlia` to `2026-08-26.dahlia` **between two deploys on the same day**, because
  `requirements/base.txt` allows `stripe>=15.5,<16.0` and the rebuild picked up 15.6.1. Left
  to the SDK default, the inbound payload shape is a function of Stripe's release calendar
  and whenever you last rebuilt. The explicit env var is what stops that.

  Note `api_version` is **create-only** on a webhook endpoint — changing it means creating a
  new endpoint and rotating `DJANGO_STRIPE_WEBHOOK_SECRET`. Cheap to get right up front,
  annoying afterwards.

- ~~**A teacher-only account page always fires a forbidden request for student subjects.**~~
  **FIXED 2026-09-13** (dashboard #67). Hooks cannot be conditional, so `SubjectsCard` must
  CALL both queries and `audience` only picked which result it rendered. Both hooks now take
  `enabled` (default `true`, so no other caller changes) and the card passes
  `isTeacher` / `!isTeacher`. The framing that made it worth fixing: the server refusing was
  the system working — **asking at all** was the defect, and it cost a round trip on every
  `/account` load plus a console error that is a red herring for anyone debugging a real 403.

- **The dashboard unit suite flakes: jsdom intermittently crashes creating a Window.**
  Roughly 1 run in 4 on a loaded machine, `vitest` reports an unhandled
  `SyntaxError: Invalid or unexpected token` from `jsdom/living/interfaces.js`
  `installInterfaces` -> `createWindow`, one test *file* is dropped from the run, and the
  process exits non-zero with every test that did run passing. The counts move between runs
  (782, 779, 778 on the same tree). **It is not caused by the session UI redesign** —
  confirmed 2026-09-07 by running the suite four times on the pre-branch base `00f8581`,
  where run 3 dropped a file the same way (96/97 files, 718 tests). It predates the branch
  and is invisible until you read the file count rather than the pass count. This is a
  merge gate, so a spurious red costs a re-run every time it fires; worth pinning the
  jsdom/vitest pair or capping `poolOptions` concurrency and seeing if it stops.

- **A user with no full name is greeted "Assalamu alaikum," and gets a blank account menu.**
  The home heading interpolates an empty `full_name` and leaves the comma stranded, and the
  header's account-menu trigger renders no visible text at all (its `aria-label` is intact,
  so this is visual, not an a11y failure). Registration does not require a name and nothing
  backfills one, so this is the default state for every account created through the API or
  the admin, not an edge case. Confirmed on staging 2026-09-06. Wants a fallback — the
  local-part of the email, or a nameless greeting — decided once and used in both places.
