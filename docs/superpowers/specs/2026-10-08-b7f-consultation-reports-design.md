# Slice B7f — Consultation reports — Design

**Date:** 2026-10-08
**Status:** Self-approved after an independent spec review (PO-3). Spec-only mode (ledger D45).
**Phase:** B7, slice f (`2026-10-08-b7-add-on-sales-design.md` §3).
**Requires:** B7c, and B7d (whose online payments the report counts). Nothing from other phases beyond
merged work (`etqan.platform.csv`, `billing.services.payments_queryset`).
**Evidence:** P1 CONS-002 header actions "تصدير تقرير" (export report) and "تصدير هوامش ربح المعلمين"
(export teacher profit margins); EXP-002 lists both, with columns UNKNOWN. The formula is B7-11
`[assumed]`.

## 1. Goal

The office exports the consultation requests list, and sees and exports what each teacher earned from
consultations and what the academy kept, per currency, over a date range.

## 2. Decisions

| # | Decision | Source |
|---|---|---|
| F-1 | **The requests report** is the B7c request list as CSV, with the list's filters, through `etqan.platform.csv.CSVExportMixin` (`?format=csv`, only while `export` is on, Plan 13 §5.3). Columns: reference, created at, product, teacher, person name, email, WhatsApp, timezone, start (academy time), start (person's time), delivery mode, request status, session status, student attendance, teacher attendance, paid method, billing method, amount, fee, currency, transaction number, paid on, self-booked. Every cell passes through `safe_cell`. **The CSV is office-only.** The list view answers `?format=csv` only to callers passing `HasCode` (`consultation_request.view_any`). A teacher, who may read the list (B7c C-12), gets 403 for the CSV, so the payment fields and emails never leave through it. | P1 CONS-002, EXP-002 · [assumed] columns |
| F-2 | **Earnings rows.** One row per **completed** request with `completed_at` in `[from, to]`, compared in academy dates (both ends included). The request must carry a payment whose billing status is `completed`, read in one query, `billing.services.payments_queryset().filter(id__in=…).values("id", "status")`; completed means `Payment.Status.COMPLETED`. Any other status, including a later wallet `credited` (D36), is excluded. A refunded or deleted payment, or an unpaid request, is left out, and the "Excluded" count shows how many were. The amount is the request's `amount_minor` without the fee: the fee is the academy's, B3-8. The teacher's share is `round_half_up(amount_minor × teacher_share_bp / 10 000)` per request, from the share snapshot taken at completion (B7c C-8). The margin is amount − share, labelled **"margin before fees"**. The report also shows a fee column (the request's `fee_minor`), so amount + fee reconciles with revenue (D16). | B7-11; ledger D5, D16 · [assumed] |
| F-3 | **The profit-margin report** groups F-2's rows by teacher and currency: completed count, amount, teacher share and academy margin. It is never summed across currencies (B3-4). An optional estimate line makes one `finance.services.convert_estimate(lines)` call per total column (amount, fee, share, margin) and is labelled an estimate. It shows only when all four are non-null; otherwise it shows nothing, which includes `exchange_rates` being off (D24, D31). The filters are the date range (default: the current academy month), teacher and product. CSV: one row per teacher and currency, plus a detail CSV with one row per request (`?detail=1`). | P1 CONS-002; ledger D24, D31 · [assumed] |
| F-4 | **Service for B4** (B7-11, D52): `consultations.services.teacher_earnings(*, since: date, until: date, teacher_user_id: int \| None = None) -> list[TeacherEarning(teacher_user_id, currency, count, amount_minor, share_minor, margin_minor)]`. It returns F-3's rows with a fixed number of queries. | ledger D52 |
| F-5 | **Access.** Both reports need `consultation_request.view_any`. Margins add a new verb on the same resource, `export_margins` ("Export profit margins" / "تصدير هوامش الربح"), so a clerk can list requests without seeing the money split. This follows the `session.supervise` precedent in `access/registry.py`: the resource declares `verbs=(*ALL_VERBS, "export_margins")`, and a module constant `EXPORT_MARGINS` joins `VERB_LABELS` with its labels. `VERB_LABELS` is a shared global outside the phase markers, so that line goes in under a one-commit ledger claim. The `in_use` list is updated. | P1 §5.3, CONS-002; `access/registry.py` SUPERVISE · [assumed] |

## 3. API and screens

| Route | Methods | Codes |
|---|---|---|
| `requests/?format=csv&…` | GET | `consultation_request.view_any` (F-1) |
| `reports/margins/?from=&to=&teacher=&product=[&format=csv][&detail=1]` | GET | `consultation_request.export_margins` |

**Screen.** `/scheduling/consultations` gains an "Export" button (when `export` is on) and a **Profit
margins** tab (`export_margins`), showing the table of F-3 with currency subtotals, the excluded count,
the optional estimate line, and the CSV buttons.

## 4. Tests

- **Earnings rules.** Completed-in-range only, with both ends included in academy dates. Refunded, deleted
  and unpaid requests excluded and counted. The fee left out. Rounding half up. Share snapshots stable
  after a product's share changes. Per currency, never summed. The estimate shown only when complete.
- **`teacher_earnings`.** The teacher filter and its query count.
- **CSV.** Columns. `safe_cell` on a name starting with `=`. 404 for `format=csv` when `export` is off,
  on both the requests list and the margins report. A teacher gets 403 for the CSV. `?detail=1` uses its
  own columns (`csv_columns` as a property).
- **Access.** `view_any` without `export_margins` gives 403 on margins. Teachers, students and parents
  get 403.
- **Dashboard.** The margins tab, its filters and the CSV links.
- **e2e:** folded into `b7-consultations-office.spec.ts`. After completion, the margins tab shows the
  demo teacher's share.
