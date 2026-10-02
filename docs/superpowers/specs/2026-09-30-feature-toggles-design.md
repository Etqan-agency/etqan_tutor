# Plan 13 — Per-Academy Feature Toggles — Design

**Date:** 2026-09-30
**Status:** Approved in brainstorming (sections 1–3), pending written-spec review.
**Phase:** B1 (accounts & access), plan 4 of 4 (10 profile depth → 11 families → 12 roles, permissions and supervision → **13 feature toggles**).

**Builds on:**
- Plan 1: `etqan.tenants.Academy`, the tenant in the public schema, and the platform admin on the bare base domain.
- Plans 3–12b: every feature this spec can switch, and the route table in `access/tests/test_routes.py`.
- Plan 8: the notifications scanner, which runs `for_each_academy`.
- Plan 12b: `supervision_enabled`, the first feature switch.

**Evidence:** `docs/PHASE_1_SYSTEM_AUDIT.md` SYS-002 (34 flags), §16.3 (flag dependencies), BR-50 ("disabling one removes its UI"); `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md` SYS-002 (37, with paid tiers) and gap row 901. Roadmap rule R4 applies.

## 1. Goal

Etqan can switch whole parts of the product on or off for each academy, the way TutorHamster's developer settings do. A switched-off feature disappears from that academy's API, dashboard and background jobs; switching it back on restores everything. The academy's admin sees what is on but cannot change it, which leaves room to sell add-ons later.

## 2. Decisions

| # | Decision |
|---|---|
| FT-1 | **Etqan sets, the admin sees (owner decision).** Only Etqan staff change an academy's switches, in the platform admin. The academy admin sees a read-only list. |
| FT-2 | **The full TutorHamster list, all live (owner decision).** Every flag is a stored, editable switch now. The eight features that exist take effect now; the others take effect when their phase is built, and that phase's plan wires the switch in. |
| FT-3 | **A registry in code, values on the academy (approach A).** No third-party flag library; no per-feature columns. |
| FT-4 | **Turning off hides, never deletes.** Turning back on restores the same data. |
| FT-5 | **Business rules stay academy settings.** "An absence consumes a session", "an excused absence consumes a session" and "auto-invoice new subscriptions" remain in the academy's own settings. General supervision moves into the switchboard. |
| FT-6 | Out of scope: priced plans or tiers and billing Etqan's customers; academies switching their own features; building the unbuilt features themselves. |

## 3. The feature registry (`etqan.platform.features`, defined once in code)

Each feature has: a `code`, `label_ar`, `label_en`, a `group` (`people · teaching · money · communication · content · platform`), a `default`, `built` (whether any code checks it yet) and `requires` (the codes it depends on).

### 3.1 Built features (take effect now; default on unless noted)

| Code | TH flag | Default |
|---|---|---|
| `families` | نظام حسابات العائلات | on |
| `parents` | نظام اولياء الامور | on |
| `supervision` | نظام الاشراف العام | **off** |
| `session_reports` | نظام تقارير الحصص | on |
| `invoices` | نظام الفواتير والايصالات | on |
| `auto_notifications` | نظام الاشعارات التلقائي | on |
| `teacher_attendance` | the teacher records attendance | on |
| `export` | نظام تصدير اكسيل (our CSV exports) | on |

### 3.2 Unbuilt features (stored and editable now; default off)

levels · file uploads · URL redirects · AI assistant · payment links · verified certificates · incentives & deductions · free sessions for subscribers · homework · internal chat · recorded courses · articles · per-country pricing · consultations · study groups · balances · per-student teacher rate · donations · AI reports · contracts · subscription archive · session archive · report deductions (`requires: session_reports`) · fixed teacher salary · student registration waiting list · payment receipt records · Zoom API · public links.

That is 28, so the registry has 36 entries. TutorHamster's vendor-specific "Olovix internal" is left out. The plan names each code; each gets Arabic and English labels.

### 3.3 Effective value

A feature is **on** when its stored value (or, with none stored, its default) is on **and** every feature in `requires` is on. An unknown code in storage is ignored. The platform admin shows a feature that is switched on but held off by a prerequisite.

## 4. Data

- `Academy.features` (public schema): a JSON map from code to boolean, `db_default` `{}`. A missing key means the default.
- A data migration copies each academy's `AcademySettings.supervision_enabled` into `features["supervision"]`. The setting then stops being written; its column is removed in a later release (the standing blue/green warning).
- No tenant-schema change is needed.

## 5. Behaviour

### 5.1 Reading a switch

`features.enabled(code) -> bool` reads the current academy (`connection.tenant`, already loaded for the request, so no extra query). Background jobs call it inside `for_each_academy`. An unknown code is a programming error and raises.

### 5.2 Routes

- A view declares `feature = "<code>"` (or a per-method map), next to `permission_codes`.
- One DRF permission class checks it after `HasCode`: a switched-off feature answers **404**, the same order supervision uses today.
- The route table gains a feature column. A test fails when a route belonging to a built feature does not declare it, or declares a code the registry lacks.

### 5.3 Effects of each built feature when off

| Feature | Effect |
|---|---|
| `families` | The families routes and the students bulk family actions 404; student payloads drop `family` and `account_type`; the payer rule skips the family payer. |
| `parents` | The parents and guardianship routes 404; the payer rule skips guardians; parent accounts cannot sign in ("Parent access is not enabled for this academy.", 403 at login); `me/` omits `children`. |
| `supervision` | As Plan 12b's switch today (fields hidden, routes 404). |
| `session_reports` | The report routes and the missing-reports list 404; the scanner sends no `report.missing` notices. |
| `invoices` | The billing routes 404; subscriptions create no invoice, whatever the auto-invoice setting; the scanner sends no invoice notices. |
| `auto_notifications` | The scanner skips the academy entirely; the bell still shows notices already sent. |
| `teacher_attendance` | A teacher's attendance routes 403 with a message naming the feature; office staff still mark attendance. |
| `export` | Every `?format=csv` answers 404. |

### 5.4 `me/`

`me/` gains `features`: the codes that are effectively on, in registry order.

### 5.5 The platform admin (Etqan staff, the bare base domain)

- The Academy change page gains a **Features** section: checkboxes grouped by `group`, each labelled in English with its Arabic name. Unbuilt ones are marked "takes effect when built", and a checked feature held off by a prerequisite shows why.
- An admin action, **Copy features from another academy**.
- Every change is recorded in Django admin's history.
- Nothing in the tenant API writes `Academy.features`.

### 5.6 The academy admin

`GET /api/v1/academy/features/` (admins only; no staff code, as with `people/admins/`): every feature with `code, label_ar, label_en, group, on, built, held_by`. The dashboard's **Settings → Features** shows it read-only, marked "Managed by Etqan". The academy settings form's General supervision switch becomes read-only, showing the feature's state.

## 6. Dashboard (`/app/`, en/ar, RTL, phone width)

- A `hasFeature(code)` helper, fed by `me/.features`, next to `can(code)`.
- Nav items, route `staticData` and action buttons declare `feature` next to `permission`. A switched-off feature hides them. A route opened directly shows "This feature isn't enabled for your academy."
- Settings → Features, read-only, grouped, with "Takes effect when built" on unbuilt ones.
- Every string in en and ar.

## 7. Seeds

- `demo`: every built feature on, including `supervision`, so the Plan 12b journey still works.
- `other`: the defaults (supervision off).
- Idempotent: a re-run never overrides a switch Etqan changed.

## 8. Testing

- **Registry:** unique codes; labels in both languages; `requires` names real codes and has no cycles; the defaults match §3.
- **Effective value:** a missing key falls back to the default; a prerequisite switched off holds a feature off; unknown stored codes are ignored.
- **Routes:** every route of a built feature 404s when it is off, after the permission check; the route-table test fails on a feature route left undeclared.
- **Each built feature switched off,** per §5.3, including the payer rule, parent sign-in, the scanner and automatic invoices.
- **Restore:** switching back on shows the same data.
- **Migration:** existing academies keep today's behaviour; `supervision_enabled` carries over.
- **Isolation:** one academy's switches never affect another's (requests and the scanner), with `until_pk_exceeds`.
- **Platform admin:** Etqan staff edit and copy switches; no tenant API can change them.
- **Dashboard:** hidden nav and screens, the "not enabled" page, and Settings → Features, in unit tests.
- **e2e:** Etqan switches family accounts off for `demo` in the platform admin; the academy admin no longer sees Families and a direct link shows "not enabled"; switching it back on restores the families.

## 9. Risks

| Risk | Mitigation |
|---|---|
| A route stays reachable while its feature is off | Each route declares its feature; the route-table test enforces it |
| A background job ignores a switch | Feature checks sit inside `for_each_academy`, with a test per built feature |
| Switching off loses data | Off only hides; a restore test |
| An academy changes on deploy | Defaults keep today's behaviour; the migration preserves supervision |
| An unbuilt feature's switch is set but does nothing | Marked "takes effect when built" in both admin views |

## 10. Out of scope

See FT-6.
