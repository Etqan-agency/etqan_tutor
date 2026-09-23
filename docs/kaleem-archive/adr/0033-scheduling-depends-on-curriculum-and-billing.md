---
number: 0033
title: Scheduling may depend on curriculum and billing
status: accepted
date: 2026-09-05
---

## Context

Phase C1 matches a student to a teacher. To do that, `scheduling` must read two things it is
currently forbidden to import:

- **Subject** (`curriculum`) — a teacher's taught subjects and a student's interests are the
  first hard filter of a match. ADR-0031 put them in a new `curriculum` module and stated
  plainly that C1 would need this arrow and that it would get **its own ADR when C1 was
  specced**. This is that ADR.
- **Entitlement** (`billing`) — a match request is raised for a student who is *covered*, so
  `scheduling` calls `billing.services.is_entitled_to`. The roadmap describes this dependency in
  prose — `billing` "does not do anything with sessions/bookings (that is `scheduling`, which
  asks billing for entitlement)" — but the import-linter contract written for the availability
  spec forbids `kaleem.billing` to `scheduling`, because availability needed no entitlement.

So one arrow is a genuine deviation from the roadmap's module graph, and the other is a
contract catching up with a dependency the roadmap always described. Both widen a boundary, and
a widened boundary is exactly the kind of change that must not arrive inside an implementation
PR.

## Decision

**`scheduling` may import `curriculum` and `billing`, through their public APIs only.**

The `scheduling imports no business modules except identity` contract becomes *except identity,
curriculum and billing*. Every other business sibling — `assessment`, `content`, `messaging`,
`notifications`, `engagement`, `analytics` — stays forbidden.

Two new contracts mirror the identity one, so the widening does not reopen the hole it was
written to close: `scheduling` may not import `kaleem.curriculum.models` or
`kaleem.billing.models` directly. Both use `allow_indirect_imports` (services legitimately
import their own models) and the standard tests exemption.

Subject foreign keys from `scheduling` are declared **by string label**
(`FK("curriculum.Subject")`), the same device C0 used for `AUTH_USER_MODEL`. A string FK creates
a database relation without an import, so the boundary is enforced where it matters — in code —
while the schema stays relational.

**Both new contracts are verified by breaking them** before C1's code lands: a probe direct
model import must turn `lint-imports` red, and green once removed.

## Alternatives considered

**Copy the subject slug into `scheduling` and avoid the arrow.** Denormalise a `subject_slug`
string onto the request. No new dependency, no contract change. Rejected: it puts the taxonomy
in two places with nothing keeping them in step, and a renamed or deactivated subject silently
diverges. It also does nothing for the `billing` half of the problem.

**Put matching in `curriculum` instead.** Matching reads subjects heavily, so it could live
where the subjects are. Rejected: matching's real subject matter is availability and
assignments, both of which are `scheduling`'s. This would move the module boundary to follow one
of matching's three inputs and break it against the other two.

**Ask `identity` to broker both reads.** `scheduling → identity` already exists, so identity
could re-export subjects and entitlement. Rejected: it makes `identity` depend on `curriculum`
and `billing` — precisely the inversion ADR-0031 rejected — and turns the one module every other
module depends on into a pass-through for everything.

**Introduce an event bus / read model now.** The roadmap has one for `analytics` later.
Rejected as premature: it is real infrastructure, and it does not remove the dependency, only
launders it.

## Consequences

**Good.**

- C1 can be written, and reads its inputs from the modules that own them rather than from
  copies.
- The dependency graph now matches what the roadmap said in prose about entitlement, instead of
  a contract that quietly contradicted it.
- The widening is narrow: two named modules, public APIs only, with the direct-model-import
  mirrors written at the same time — not retrofitted after a hole is found, which is what
  happened to this same module in September.

**Bad, or at least owed.**

- `scheduling` now depends on three business modules. It is the most connected module in the
  system, and that is a real cost when any of the three changes shape.
- The roadmap's module graph is now two arrows out of date; the roadmap document is not amended
  by this ADR — the discrepancy is recorded here and in the C1 spec.
- Every future `scheduling` change carries a slightly weaker boundary guarantee, so the
  break-it-first verification is not a one-off ritual: a contract nobody watches fail is not
  known to work.
