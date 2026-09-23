---
number: 0032
title: Rotated credentials keep their gitleaks fingerprints
status: accepted
date: 2026-09-05
---

## Context

ADR-0030 introduced `gitleaks` as a merge gate and allowlisted the known historical leaks
by fingerprint in `.gitleaksignore`. Its clause 2 ends:

> Removing a line is how a rotated credential gets recorded as dealt with.

`.gitleaksignore`'s own header says the same, more strongly: *"an empty file is the goal."*

On 2026-09-05 the credentials from `588a1e35` were rotated — the `sk_live_` Stripe key, the
AWS access key and secret, the Django `SECRET_KEY`, and the Postgres and Flower passwords.
Acting on the documented rule would mean deleting their eleven fingerprint lines.

**That would turn CI permanently red.** Rotation makes a credential *dead*; it does not make
it *absent*. The strings are still in git history and still on GitHub — verified directly:
`git show 588a1e35:kaleem/.envs/.production/.django` still prints them. `gitleaks` scans
history, so it would report them on the very next run, on every branch, forever. The only
way to make the file legitimately empty is to rewrite history, which ADR-0030 rejects in the
same clause — it would break every submodule pointer and every SHA quoted across `docs/`,
and would not un-leak anything already pushed.

So ADR-0030 contains a rule that cannot be followed without breaking the gate it created.
The two halves of clause 2 contradict each other.

## Decision

**A rotated credential keeps its fingerprint in `.gitleaksignore`. The line is re-annotated,
not removed.** An empty `.gitleaksignore` is no longer the goal, and would be a symptom of
history rewriting rather than of good hygiene.

Each block carries the rotation date and states plainly that the values are dead. The
allowlist's purpose shifts from *"this is an outstanding exposure"* to *"this is a known,
remediated leak whose text is permanently in history"* — still legible, still one annotated
line per finding, still never used to silence something new.

This amends **ADR-0030 clause 2**. Everything else in ADR-0030 stands: fingerprints not rule
disabling, no history rewrite, and never a new line for a new finding.

## Alternatives considered

**Delete the lines as written, and let CI go red.** Rejected: it breaks every merge for a
remediation that is already complete. A gate that is red for a resolved issue is a gate
people learn to bypass — the exact failure ADR-0026 and ADR-0030 were written against.

**Rewrite history so the file can genuinely be emptied.** Rejected for the reasons ADR-0030
already gives, which have not changed. It also cannot un-leak what is already public.

**Add the paths to `gitleaks`' config as a global path exclusion.** Rejected: it suppresses
by *location* rather than by *specific finding*, so a genuinely new secret added to
`kaleem/.envs/` later would be silently ignored. Fingerprints stay specific.

**Say nothing and quietly leave the lines in place.** Rejected. The next person to read
`.gitleaksignore` would find a header instructing them to empty it, do so, and break CI — or
worse, conclude the rotation never happened. A rule that is wrong should be fixed where it
is written.

## Consequences

**Good.**

- CI keeps working after a remediation, which is the point of doing the remediation.
- `.gitleaksignore` still says exactly what leaked, when, and that it was dealt with. The
  file becomes a rotation record rather than a to-do list.
- The specific-fingerprint discipline survives: a new secret in a new commit still fails.

**Bad, or at least owed.**

- `.gitleaksignore` is now permanent, so it will accrete. It needs an occasional read to
  confirm every block still describes something rotated, and a line whose rotation cannot be
  confirmed should be treated as an open exposure again.
- "Empty file is the goal" was a clean, checkable target. Its replacement — "every block is
  annotated with a rotation date" — needs a human to read it, and suppression lists rot, as
  ADR-0030 itself notes.
- Rotation is recorded here and in `.gitleaksignore` only. It is not independently verifiable
  from the repo: confirming an AWS key is deactivated means looking at AWS. The dates are a
  claim by whoever rotated, not evidence.
