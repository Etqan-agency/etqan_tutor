# etqan_tutor — TutorHamster parity roadmap

**Status:** approved in conversation 2026-09-24; supersedes the v1 spec's scope boundary (not its content).
**Owner decision:** build a full-feature equivalent of TutorHamster (Option B of `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md` §7), sequenced so the small v1 core ships first and each later phase widens it.
**Reference evidence:** `docs/PHASE_1_SYSTEM_AUDIT.md` (2026-09-15/23) and `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md`. Feature IDs below (PEOPLE-, SUB-, SCHED-, BILL-, PAY-, COMM-, …) are the audits' stable IDs.

## 1. Decisions

| # | Decision |
|---|---|
| R1 | The product goal is parity with TutorHamster's feature set, delivered as a multi-tenant SaaS (Plan 1 tenancy and Plan 2 academy sites stay as built). |
| R2 | Build order follows the audit's Option B literally: the v1 core (B0) end to end first, then phases B1–B11. Rework in later phases is accepted in exchange for a usable product sooner. |
| R3 | The v1 spec (`2026-09-23-etqan-tutor-v1-design.md`) remains the specification for **B0 only**. Its §1.2 non-goals are no longer permanent: each is re-labelled "later — phase Bx" (see §3). |
| R4 | Within B0, adopt TutorHamster's shapes wherever that costs nothing extra: field names, status values and option lists (student statuses, session and attendance statuses, package duration units, teacher payout methods), and a teacher ↔ courses link (CATALOG-001 "teachers" multi-select). B0 scope does not otherwise grow. |
| R5 | Every phase goes spec → plan → subagent-driven execution → review → merge, and leaves the product deployable. Phases may be split into several plans. |
| R6 | Design questions are answered from the audits first; the owner is asked only where TutorHamster's behaviour is unknown or a genuine business choice. |
| R7 | **Checkpoint before B2:** the owner arranges access to what the audits could not observe (teacher / parent / student panels, renewal, payroll arithmetic, generation timing — audit §4, U1–U9), via demo logins for those panels or a licensed TutorHamster instance. B0 and B1 do not depend on it. |
| R8 | TutorHamster's demo is only ever read, never modified, unless the owner explicitly consents to a specific action. Credentials are never written to files or memory. |

## 2. Phases

| Phase | Contents | Audit IDs | Depends on | Size |
|---|---|---|---|---|
| **B0 — v1 core** | v1 spec milestones 3–9: people & catalogue (Plan 3), subscriptions & weekly slots & generation, sessions & attendance & reports, invoices & manual payments, teacher payroll, notifications (in-app + email), E2E + staging deploy | v1 spec §9 | Plans 1–2 | L |
| **B1 — accounts & access** | Family accounts with a payer; study groups; student statuses, tags, XP, nationality, age group; supervisor actor; role editor with resource × verb permissions; per-academy feature toggles | PEOPLE-001…004, 007; RBAC-*; SYS-002 | B0 people | L |
| **B2 — scheduling depth** | Multi-course / multi-teacher subscriptions; group and family subscriptions with rosters; weekly-schedule entity with bulk change / move / restore; compensation (make-up) sessions; postponement window; extra sessions; trial-session pipeline; teacher availability; session statuses with in/out times; activity log with revert; archives; simplified view; student-timezone display | SUB-001/003/004/006–008; SCHED-001/003–008/012/015/017 | B1; checkpoint R7 | XL |
| **B3 — money depth** | Per-country package pricing; discount / activation / renewal codes; per-country manual payment methods; student wallet; donations; expenses and net profit; service fee; exchange rates; Stripe / PayPal gateways, payment links and webhooks | CATALOG-003; SUB-005; BILL-002…007; SYS-003 | B0 billing; B1 payer | XL |
| **B4 — payroll depth** | Per-student rates; percentage incentives; report deductions; fixed salary; teacher balance and withdrawal requests; receipt acknowledgement; salary projections; bulk rate assignment; receipts → expenses | PAY-002…013 | B2 session classes; B3 expenses | M |
| **B5 — communication** | WhatsApp (numbers, groups, per-teacher / per-course routing); 11+ editable bilingual notification templates with per-session reminder times; manual broadcast composer; per-user notification preferences; internal chat and chat groups | COMM-001…010 | B0 notifications; B2 | L |
| **B6 — learning** | Levels / sub-levels / topics with upgrade requests and student levels on subscriptions; Qur'an chapters sync; educational content; homework; session reviews; certificates and templates; honour board | CATALOG-004…007; SCHED-010/011; CERT-*; PEOPLE-007 | B2 | L |
| **B7 — add-on sales** | Recorded courses (playlists, videos, enrolment, watch tracking, comments, reviews); consultations (products, slot booking, payments, rescheduling, profit margins) | RC-*; CONS-* | B3 gateways | XL |
| **B8 — marketing extras** | Articles and categories; video library; FAQs; ads; redirects; testimonial media types; site status modes; custom code injection; extra social links; page builder | CNT-001…010 | Plan 2 | M (L with page builder) |
| **B9 — platform extras** | Two-factor auth; Google sign-in; phone + OTP login and reset; student self-registration, enhanced funnel and waiting list; quick-login links / impersonation; named themes and dark mode; file library; system-status jobs; employment contracts; Spanish | AUTH-*; LEAD-004; SYS-004…007; PEOPLE-006 | B0 | M–L |
| **B10 — AI** | Content generation (courses, articles, SEO, contracts); AI monthly student reports; AI assistant | EXP-001; SYS-010 | B6 | M (scope unknown) |
| **B11 — apps** | Mobile and desktop apps | PANEL-008/009 | B2–B5 APIs | XL (scope unknown) |

Sizes are relative (S ≤ one v1 milestone, M 1–2, L ~3, XL > 3).

## 3. v1 non-goals re-labelled

| v1 non-goal | Phase |
|---|---|
| Public academy signup; SaaS plan billing | Not a TutorHamster academy feature (vendor-side); stays out |
| Online student payments (Stripe / PayPal) | B3 |
| Built-in video | Out (TutorHamster also uses external rooms: Zoom, Jitsi, kMeet) — revisit with B11 |
| Group sessions; family accounts | B1 (accounts), B2 (subscriptions / sessions) |
| Levels / curriculum progress; homework; certificates | B6 |
| Wallets | B3 |
| Trial-session pipeline | B2 |
| Recorded courses; consultations | B7 |
| Page builder | B8 |
| Chat | B5 |
| AI features | B10 |
| Fine-grained permission editor; feature-flag system | B1 |
| WhatsApp / SMS delivery | B5 (WhatsApp); SMS / OTP with B9 |
| Mobile app | B11 |
| Data migration from existing systems | Out until a customer needs it |

## 4. Next step

Plan 3 (B0 milestone 3, people & catalogue) is specified against the v1 spec §4.1–4.3 and §6, applying R4 using the field inventories in the 2026-09-24 audit §2.1–2.2.
