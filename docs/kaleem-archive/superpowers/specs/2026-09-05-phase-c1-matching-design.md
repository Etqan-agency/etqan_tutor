---
name: phase-c1-matching
phase: C
modules: [scheduling, curriculum, billing, identity]
status: draft
created: 2026-09-05
closed: null
---

## Goal

Given an entitled student who has stated what they want to study, put a teacher in front of
them. C0 created the inputs — `TeacherProfile.gender`, `Subject`, `TeacherSubject`,
`StudentSubjectInterest` — on top of the `WeeklyAvailability` that Phase B's availability spec
already shipped. C1 is the first spec that reads all of them.

The match is a **broadcast, first-to-accept**: every eligible teacher sees the request, and the
first one to accept becomes the student's teacher. The result is a durable
`TeacherAssignment` — an ongoing 1-on-1 relationship, not a single session. C2 books sessions
against that assignment; C1 does not book anything.

**Out of scope, restated up front so the plan does not drift:** sessions, booking, quota, video
(C2/C3), the `notifications` module, email of any kind, trials, and subject proficiency levels.

## Decisions taken

Settled during brainstorming, recorded so the plan does not relitigate them:

1. **Broadcast, first to accept.** Not a ranked list the parent picks from, not admin
   assignment, not auto-assign. The teacher chooses to take the student.
2. **The unit is an ongoing `TeacherAssignment`**, not a per-session match. 1-on-1 continuity
   is the product.
3. **The trigger is entitlement, not a button.** A student who is covered by a subscription and
   has stated a subject gets a match request without asking for one.
4. **Offers are delivered in-app only.** A teacher-facing page, nothing else. `notifications`
   does not exist and C1 does not open it.
5. **All three inputs are hard filters**; the score orders the inbox and decides nothing.
6. **An unmatched request stays open indefinitely**, visible to staff, and is re-evaluated
   whenever the pool changes. No expiry, no timer, no Celery beat.

## Data model delta

All three models are new and live in `scheduling`.

```text
scheduling.MatchRequest                       (new)
    student        FK AUTH_USER_MODEL
    subject        FK "curriculum.Subject"     # by string label, no import
    status         OPEN | MATCHED | CANCELLED
    created_at / matched_at
    partial-unique (student, subject) WHERE status = OPEN

scheduling.TeacherAssignment                  (new)
    student        FK AUTH_USER_MODEL
    teacher        FK AUTH_USER_MODEL
    subject        FK "curriculum.Subject"
    status         ACTIVE | ENDED
    source_request FK MatchRequest
    created_at / ended_at
    partial-unique (student, subject) WHERE status = ACTIVE

scheduling.MatchDecline                       (new)
    request        FK MatchRequest
    teacher        FK AUTH_USER_MODEL
    created_at
    unique_together (request, teacher)
```

**Offers are not rows, and that is the load-bearing decision here.** A teacher's inbox is
computed live: every `OPEN` request they are currently eligible for, minus the ones they
declined. Materialising an offer per eligible teacher would mean a fan-out table that goes
stale the moment a teacher adds a subject, declares a gender, or edits availability — and
"the request stays open and is re-evaluated when the pool changes" would then need a job to
re-fan-out. Computed live, re-evaluation is a property of the query rather than a thing to
maintain. Rows exist only for the three facts that must outlive a request cycle: the request,
the assignment, and a decline.

`TeacherAssignment` is many-over-time (rule #7): reassigning a student writes a new row and
ends the old one. It is never a `OneToOneField`, and a student's history is readable.

## Eligibility and rank

A teacher is **eligible** for an `OPEN` request when all three hold:

1. **Subject** — a `TeacherSubject` row for that request's subject.
2. **Gender** — C0's rule, inherited verbatim: a teacher whose `gender` is `""` (undeclared) is
   **excluded** when the student expressed a `teacher_gender_preference`, and **eligible** when
   the student expressed no preference. A declared gender must equal the preference when one
   was expressed.
3. **Availability overlap** — at least one minute of overlap between the teacher's and the
   student's `WeeklyAvailability`, computed in UTC through the existing `to_utc_intervals`.

Failing any one of these means the teacher never sees the request.

**Rank** orders the inbox and nothing else: overlap minutes descending, tie-broken by oldest
request first. It does not gate eligibility and it does not decide who wins — with
first-to-accept, whoever accepts first wins regardless of rank.

Note what rank is *not*. An earlier draft tie-broke on the teacher's active-assignment count,
which is incoherent here: an inbox ranks **requests for one teacher**, so that teacher's own
load is constant down the whole list and the tie-break could never fire. Load is a property of
a teacher, and the only sound use for it is a capacity cap — which is OQ-C1-1, not a ranking
input. Longest-waiting-first is the tie-break that actually means something to the student.

## The trigger, without inverting a dependency

Entitlement lives in `billing`; `billing` must not know `scheduling` exists. So the arrow points
the way the roadmap draws it — scheduling asks billing — and requests are **reconciled**, not
pushed:

`scheduling.services.sync_match_requests()` opens a `MatchRequest` for every
(student, subject) where the student is entitled (`billing.is_entitled_to(user,
Capability.BOOK_SESSION)`), has a `StudentSubjectInterest` in that subject, has no `ACTIVE`
`TeacherAssignment` for it, and has no `OPEN` request for it already. It is idempotent by
construction — the partial-unique index is the backstop.

**It gates on the existing `BOOK_SESSION` capability rather than adding a `MATCH` one.** Every
capability today resolves to the same subscription check, so a second name would be a
distinction the code cannot make; and being matched to a teacher you cannot book is not a state
worth building. If matching and booking ever diverge in entitlement, adding the capability is
one enum member.

It runs lazily at the top of the two read endpoints (the teacher inbox and the student's own
status) and is exposed as a management command for staff. **No event bus and no Celery beat**:
both are real machinery, and neither is needed to make a reconciler correct on a roster this
size. If the reconcile ever becomes too expensive to run per-read, moving it to a periodic task
is a change of schedule, not of design.

## API delta

All under `/api/v1/scheduling/` via `config.api_router` (ADR-0029).

| Method | Path | Who | Shape |
| --- | --- | --- | --- |
| `GET` | `/match-offers/` | teacher | ranked open requests they are eligible for |
| `POST` | `/match-offers/{request_id}/accept/` | teacher | → the created assignment |
| `POST` | `/match-offers/{request_id}/decline/` | teacher | 204; hides it from that teacher only |
| `GET` | `/match-requests/mine/` | student / parent | per subject: pending, or the assigned teacher |
| `GET` | `/assignments/` | any | role-aware: teacher → their students, student → their teacher, parent → their children's |

**Accept is where the whole race lives.** It takes `select_for_update` on the `MatchRequest`,
re-checks eligibility inside the transaction, moves `OPEN → MATCHED` and writes the
`TeacherAssignment` atomically. A second accepter gets a typed 409 (rule #8 — a typed exception
mapped to a real status, never a stringified bare `Exception`). The partial-unique index on
`(student, subject) WHERE status = ACTIVE` makes the invariant true at the database level as
well, so a bug in the service layer cannot produce two live teachers for one student-subject.

**An offer exposes the student's first name, the subject, and a human summary of the overlap —
never an email address** (ADR-0023). `/assignments/` is symmetric: each side sees the other's
display name, not their email.

## Frontend

- **`/match-requests`, teacher-only** — the inbox. Each row: student first name, subject, when
  their times overlap, and Accept / Decline. Ranked. Empty, loading, error and "already taken"
  states, the last of which is reachable in normal use, not an edge case: a request can be
  claimed between render and click, so a 409 must read as *"another teacher took this"*, not as
  a failure. Role-aware nav entry; this replaces a scaffold route.
- **Student / parent panel** on the existing `/account` page, following C0's precedent: these
  are role-conditional profile-adjacent panels and that page already renders exactly that
  shape. Per subject, either
  "we're looking for a teacher" or the assigned teacher's name. With no expiry, the pending
  state can persist for days — the copy must be honest about that rather than implying
  imminence.
- en + ar, RTL verified, values from tokens (never hardcoded), WCAG 2.2 AA.

## Module boundaries — and the ADR this owes

C1 needs **two** cross-module arrows that `pyproject.toml` currently forbids to `scheduling`:

- **`scheduling → curriculum`** — the one ADR-0031 promised would be recorded when C1 was
  specced. Subject FKs are by string label; reads go through `curriculum.services`; no
  `curriculum.models` import.
- **`scheduling → billing`** — needed for `is_entitled_to`. The roadmap describes this
  dependency in prose ("scheduling asks billing for entitlement") but the contract written for
  the availability spec forbids it, because that spec needed no entitlement. This is a contract
  catching up with the roadmap rather than a new deviation, but it is a widened boundary and it
  is recorded, not slipped in.

Both are recorded in **ADR-0033**, which lands with this spec. The contract edits are:

- `scheduling imports no business modules except identity` → *except identity, curriculum and
  billing*; every other sibling stays forbidden.
- Two new mirrors of the identity contract — `scheduling` may not import
  `kaleem.curriculum.models` or `kaleem.billing.models` directly, with `allow_indirect_imports`
  and the usual tests exemption.

**Both new contracts are verified by breaking them** before the code lands: a probe
`from kaleem.curriculum.models import Subject` in `scheduling/services.py` must turn the run
red, and green once removed. A contract nobody has watched fail is not known to work — that is
precisely how scheduling's own identity hole survived until 2026-09-04.

## Test plan

TDD throughout (D3). Backend floor 97, dashboard 92/87/84 — raise them if this slice lifts
coverage.

**Backend — eligibility**
- Subject mismatch, gender mismatch, and zero availability overlap each exclude a teacher,
  independently.
- The undeclared-gender rule, both ways: excluded when the student stated a preference,
  eligible when they did not.
- Overlap is computed in UTC across a timezone difference, not on naive local times.
- Rank orders by overlap minutes, then by oldest request — asserted as an order, not as a score
  value.

**Backend — the race and the invariants**
- Two teachers accepting the same request: exactly one assignment exists, the loser gets a
  typed 409, and the request is `MATCHED` once.
- The partial-unique index rejects a second `ACTIVE` assignment for one (student, subject) even
  when the service layer is bypassed.
- A teacher accepting a request they are no longer eligible for (availability edited after the
  page rendered) is refused inside the transaction.
- Decline hides the request from that teacher only, and does not affect anyone else's inbox.

**Backend — the reconciler**
- An unentitled student raises no request; entitlement via a parent's family plan does.
- Idempotent: running it twice opens one request.
- A student with an `ACTIVE` assignment for a subject gets no new request for that subject, and
  does for a second subject they are interested in.
- A request with no eligible teacher stays `OPEN` and becomes visible to a teacher who later
  adds the subject — the pool-change re-evaluation, asserted rather than assumed.

**Backend — plumbing**
- Each endpoint 403s for a caller without the right profile; `/assignments/` returns the right
  rows for each of the three roles.
- No response body contains an email address.
- `test_api_versioning_is_enforced` still passes.
- `lint-imports` verified by breaking both new contracts, as described above.

**Dashboard** — inbox renders ranked; accept round-trips; a 409 renders as "another teacher took
this" rather than an error; decline removes the row; the empty state; the student pending and
matched states; Arabic renders RTL.

**e2e** (D3 requires it for a user-facing area) — a teacher sees an eligible request, accepts it,
and the student's side shows the teacher after a reload; a second teacher's inbox no longer
shows it. `seed_e2e` gains a teacher and a student whose subjects, genders and availability
overlap by construction, and the accounts must be safe to mutate repeatedly.

## Risks

- **First-to-accept rewards the fastest checker, not the best match.** With an in-app-only
  inbox and no email, that means whoever opens the page most often. Acceptable while the roster
  is small and every teacher is eligible for few students; it stops being acceptable at scale,
  and the fix is a delivery channel (notifications) plus possibly a rank-weighted release, not a
  change to this data model.
- **A pending request has no deadline.** By decision — but nothing tells staff a request has sat
  for a week. Django admin shows it; nothing pushes it.
- **The reconciler runs per read.** Fine at this size, and it is a scheduling change if it stops
  being fine.

## Open questions

None blocking. Two to answer while building, neither of which changes the data model:

- **OQ-C1-1.** Should a teacher have a capacity cap (max active assignments)? Today load only
  breaks rank ties. A cap is a fourth hard filter and one field on `TeacherProfile`.
- **OQ-C1-2.** Can a parent reject a match they dislike? Ending an assignment exists in the
  model (`ENDED`) but has no endpoint or UI in C1 — staff do it in Django admin.
