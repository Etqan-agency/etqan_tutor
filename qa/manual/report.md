# Manual test campaign: final report (all 16 areas), 2026-10-28

## Method
- **Agent 1 tested by hand in a real Chromium**, one step at a time with `tools/step.mjs`, and
  looked at every screenshot. Coverage was every screen, for every role:
  - Arabic (RTL) and English at 1440px;
  - a mobile pass at 375px.
- **Agent 2 was the only gate.** It:
  - reproduced every finding with its own screenshot;
  - dropped duplicates and non-bugs;
  - classified and filed each bug;
  - retested every fix with before/after screenshots;
  - decided each area.
- **Agent 3 fixed** P0–P2 and the easy P3s, each with a regression test.
- **Agent 1 then did a confirmation sweep**, followed by Agent 2's final gate.
- **Areas that failed their gate** got a second fix cycle. This happened to M01.

## Results: 16 / 16 PASSED
| Area | Bugs filed | Fixed + verified |
|---|---|---|
| M02 Sign-in & account | 19 | 9 |
| M03 Dashboards & navigation | 22 | 13 |
| M04 People | 29 | 16 |
| M06 Subscriptions & schedules | 19 | 12 |
| M07 Sessions & attendance | 27 | 11 |
| M08 Billing & finance | 22 | 13 |
| M09 Payroll | 26 | 12 |
| M14 Teacher portal | 31 | 19 |
| M15 Student & parent portal | 23 | 12 |
| M12 Settings | 19 | 12 |
| M05 Catalogue | 26 | 15 |
| M10 Chat & notifications | 27 | 15 |
| M11 Learning & certificates | 35 | 21 |
| M13 Website admin | 19 | 16 |
| M16 Public pages | 31 | 18 |
| M01 Etqan staff console | 31 | 20 (2 fix cycles) |
| **Total** | **406** | **234** |

- **Severity:**

  | Severity | Count | Status |
  |---|---|---|
  | P0 | 0 | — |
  | P1 | 1 | Fixed and verified (QA-800) |
  | P2 | 12 | Fixed or owner proposals |
  | P3 | 334 | — |
  | P4 | 59 | — |

- **Screenshots:** 4,935 in `qa/manual/screens/`.
- **Open:** 172 P3/P4 issues, plus the P2 proposals.
  - The gallery with screenshots is `qa/manual/gallery.html`. Open it in a browser.
  - Every open issue has its steps in `qa/bug-register.md` (QA-048 … 830).

### Most important fixes
- **QA-800 (P1).** The Etqan console's "Add user" stored the password as plain text, and the new
  staff member could never sign in.
  - Passwords are now hashed (argon2).
  - The hash is shown read-only.
  - There is a reset-password button.
- **QA-801 / QA-802.**
  - Suspend, reactivate and copy-features, and voiding an Etqan invoice, now ask for confirmation.
  - Voiding needs a reason.
- **QA-012.** View-only Etqan staff could not open an academy page (500). They now get a read-only
  view.
- **QA-700 (P2).** The academy's primary colour was never applied to its site. It now is.
- **QA-758 / QA-715 (P2).** The registration page and the inquiries inbox were wider than a phone
  screen. Both now fit.
- **QA-032, QA-450/451, QA-668, QA-314 (P2s)** are fixed. See the register.
- **Many fixes across the app:**
  - English text showing in the Arabic UI;
  - RTL order of mixed Arabic/Latin names, phones, dates and punctuation;
  - missing confirmations and toasts;
  - raw server errors;
  - double submits;
  - endless spinners;
  - phone layouts.

## Top open problems (recommended next fixes)
1. **Pickers stop at 100 people and have no search.** Students past the first 100 can't be reached
   in: new subscription (QA-202), student rates (QA-371), add session (QA-273), the honour dialog
   (QA-663) and others. The fix is one shared searchable person picker.
2. **Wide tables on phones.** The tables hide actions or key columns on: Today (QA-118, 268),
   invoices (QA-315), payslips and withdrawals (QA-369), the students filter (QA-173), the wallet
   (QA-457), homework (QA-430) and levels (QA-428). The fix is a shared "cards on phone" pattern.
3. **The public site doesn't show live courses, packages or teachers** (QA-770, P2, proposal).
   This needs new public API payloads, plus your decision on which teacher fields are public.
   Interim option: hide or label the three switches.
4. **Arabic UI: exports and pickers.**
   - CSV exports have English headers (QA-161, 271).
   - The time-zone picker shows raw English IANA names (QA-154).
5. **Subscriptions:**
   - an early renewal looks like a second subscription (QA-200, 201);
   - a duplicate invoice can be created with no warning (QA-304);
   - a session doesn't show the lessons left (QA-259).
6. **Family clarity:**
   - there is no total owed and no unpaid filter (QA-453);
   - past sessions still say "scheduled" (QA-454);
   - a paid payment link sends no receipt (QA-767);
   - the site has no sign-up link (QA-751).

## Decisions needed from Khaled
| # | Decision | Bugs |
|---|---|---|
| 1 | Shared person picker with search (the recommended fix for #1 above) | QA-202, 371, 273, 663 |
| 2 | Public courses, packages and teachers on the site; which teacher fields are public | QA-770 |
| 3 | Auto-cancel unpaid consultation holds | QA-451 |
| 4 | Auto-sync Qur'an chapters | QA-562 |
| 5 | Small API-code proposals | QA-561, QA-464 |
| 6 | Re-anchor sessions on a timezone change (Tier 1) | QA-041 |
| 7 | Early renewal: one lesson or two (Tier 1) | QA-039 |
| 8 | Deactivated people get no new sessions — confirm (Tier 1) | QA-040 |
| 9 | Review the global retry change: `QueryClient` no longer retries 403/404, so missing records stop spinning. It is app-wide and verified by Agent 2, but worth an owner look | QA-106 |

## Final verification (2026-10-28, all fixes applied)
| Check | Result |
|---|---|
| Backend pytest (full) | **10,214 passed, 0 failed** after updating one stale test (QA-813's new readable name) |
| Dashboard Vitest (full) | **3,709 passed, 0 failed** after updating one stale test (QA-255's "lesson over" rule) |
| Dashboard `tsc` | 0 errors |
| ruff | clean (one import order fixed) |
| lint-imports | 54 contracts kept |
| biome | no new findings; the 6 warnings and the schema note already exist on `main` |

Evidence is in `qa/manual/evidence/final/` and in each area's `evidence/`.

## Not covered
- **Live integrations are BLOCKED** (there are no keys): Stripe, PayPal, Stripe Connect, Zoom,
  WhatsApp, SMS, Google sign-in and web push. Their flows were only run against the simulator or
  fakes.
- **Not tested:**
  - real phones and browsers other than Chromium (Safari, iOS, Firefox);
  - the production edge over HTTPS, TLS and domains;
  - load and performance;
  - real time-based jobs such as the month-end billing run;
  - screen readers.
- **The official Etqan site** (`website/`) is out of scope. The owner's other session owns it.

## Code state: nothing committed
| Repo | Branch | Files changed |
|---|---|---|
| backend | `qa/manual-2026-10` | 54 |
| dashboard | `qa/manual-2026-10` | 480 (features, locales ar/en/es, tests) |
| marketing | `qa/manual-2026-10` | 19 (M13/M16 site fixes) |

Waiting for Khaled's go-ahead to commit and push.

## Cost
- About 21M sub-agent tokens for the 16 areas, plus final verification.
- That's roughly 1.1–1.4M per area. Screenshots are the main cost.
