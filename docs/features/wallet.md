# Student wallet (balances)

`etqan.wallet` holds money for a student: one balance per student and currency. The balance is
kept as an append-only ledger of entries.

- The office tops it up by hand, adjusts it, moves an invoice payment into it, reverses a top-up,
  and credits compensation for a missed session.
- Students and parents see the balance, pay invoices from it, and top it up online.

The money side always goes through billing payments, so revenue is counted once, when money comes
in.

## Concepts

| Model | What it is |
| --- | --- |
| `Wallet` | `(student, currency)` unique, created on its first credit. `balance_minor` ≥ 0 is a cache of its entries' sum, written only by the services in the entry's transaction. |
| `WalletEntry` | One movement, never updated or deleted. Fields: `kind`, signed `amount_minor`, `balance_after_minor` ≥ 0, plain ids `payment_id`/`invoice_id`/`session_id`, optional `top_up`, `note`. |
| `TopUp` | An online top-up request (student, currency, amount ≤ 100 000 000 minor), `pending` → `paid`. It is the checkout's `reference_id`. |

Entry kinds and their sign (enforced by a DB constraint):

| Kind | Sign | Comes from |
| --- | --- | --- |
| `topup` | + | manual top-up or online top-up, each with a `wallet_topup` payment |
| `refund` | + | an invoice payment moved into the wallet (payment becomes `credited`) |
| `compensation` | + | a session the student did not get; one per session |
| `spend` | − | an invoice paid from the wallet (`wallet` payment) |
| `reversal` | − | a top-up given back (its payment becomes `refunded`) |
| `adjustment` | ± (not 0) | a correction with a reason; no payment, never revenue |

Constraints:

- Money kinds (`topup`, `refund`, `spend`, `reversal`) need a `payment_id`.
- `(kind, payment_id)` is unique.

## How it works

All in `services/ledger.py` unless noted. Lock order is the wallet first, then billing's invoice
or payment (E-6).

- **Manual top-up** (`top_up`): a manual method only. It creates a standalone `wallet_topup`
  payment (`billing.record_topup_payment`) and a `topup` entry. That payment is revenue.
- **Adjustment** (`adjust`): any non-zero amount with a 1–500 character reason. A negative
  adjustment must be covered by the balance.
- **Pay an invoice** (`pay_invoice`):
  1. The invoice is read as billing scopes it (`invoice_for`). A family member must also be the
     student or the student's parent (`reads.py:may_use`).
  2. The wallet in the invoice's currency is locked.
  3. The amount defaults to `min(balance, invoice balance)`.
  4. Billing records a `wallet` payment (`record_wallet_payment`), and a `spend` entry is written.

  Wallet payments are not revenue.
- **Move to wallet** (`move_to_wallet`): a completed invoice payment of any method is credited to
  the invoice student's wallet, in that payment's currency (`billing.credit_payment` marks it
  `credited`). The fee stays revenue and is not credited. Moving a `wallet` payment undoes a
  spend.
- **Reverse a top-up** (`reverse_topup`): the balance must cover it. Billing marks the payment
  `refunded`, so its revenue and fee leave together.
- **Online top-up** (`services/online.py:start_top_up`, then `services/topup_purpose.py`):
  1. A `TopUp` row is reused or created.
  2. `gateways.start_checkout("wallet_topup", …)` starts the checkout. The academy's fee switch
     applies.
  3. On completion, `complete` records the top-up payment with its fee and writes the `topup`
     entry. It does this even while `balances` is off, because money received is never dropped.
  4. A mismatch or duplicate becomes checkout attention.
- **Compensation** (`services/compensation.py:compensate`):
  - Scheduling claims the session (`claim_session_for_balance`).
  - The wallet in the subscription's currency is credited. The suggested amount is
    `price_minor // sessions_total`.
  - It cannot be undone; correct it with an adjustment.
- **Top-up currencies** (`reads.py:topup_currencies`): the academy currency first, then the
  currencies of the student's wallets and non-void invoices.
- **Who may use a wallet:** the student themself or their parent. A sibling who pays an invoice
  sees the invoice but not the wallet. The office is checked by permission codes.
- Billing refuses to refund or delete wallet money directly (`refuse_reserved_money`). Only these
  services undo it.

## API

All routes are under `/api/v1/wallet/` and need the `balances` feature. "Not quick-login" means
`NotImpersonating`.

| Method | Path | Who | Purpose |
| --- | --- | --- | --- |
| GET | `/api/v1/wallet/mine/` | student, parent | Each of the caller's students: balances and top-up currencies |
| GET | `/api/v1/wallet/students/<user_id>/` | `wallet.view_any`; family read | A student's balances |
| GET | `/api/v1/wallet/students/<user_id>/entries/` | `wallet.view_any`; family read | Statement, paginated, `?currency=` |
| POST | `/api/v1/wallet/students/<user_id>/top-ups/` | `wallet.create`, not quick-login | Manual top-up |
| POST | `/api/v1/wallet/students/<user_id>/adjustments/` | `wallet.create` + `wallet.update`, not quick-login | Adjustment |
| POST | `/api/v1/wallet/invoices/<id>/pay/` | `wallet.update` or student/parent, not quick-login | Pay an invoice from the balance |
| POST | `/api/v1/wallet/payments/<id>/move/` | `wallet.update`, not quick-login | Move a payment into the balance |
| POST | `/api/v1/wallet/payments/<id>/reverse/` | `wallet.update`, not quick-login | Reverse a top-up |
| GET, POST | `/api/v1/wallet/compensations/` | `wallet.create` | `?session=` facts; credit compensation |
| GET | `/api/v1/wallet/top-ups/options/` | student, parent | `?student=&currency=&amount_minor=` → `{currencies, providers}` |
| POST | `/api/v1/wallet/top-ups/` | student, parent, not quick-login | Start an online top-up (non-atomic) |

Some routes also need `invoices` or `online_payments`. When that second feature is off they answer
404 (`_need`).

## Dashboard

- **Family:** `routes/_authed/learning.wallet.tsx` shows `FamilyWalletPage`, with `Statement` and
  `OnlineTopUpDialog`.
- **Invoice pages:**
  - `PayFromWallet` on the office and family invoice pages;
  - `MoveToWallet` on each payment row of the office invoice page.
- **Office cards:**
  - `StudentWalletCard` (with `TopUpDialog`, `AdjustDialog`) on `people.students.$personId`;
  - `SessionWalletCard` (compensation) on `scheduling.sessions.$sessionId`.
- Feature folder: `dashboard/src/features/wallet/`.

## Background jobs

None.

## Configuration

- **Feature:** `balances` (built, off by default, requires nothing). Online top-up also needs
  `online_payments`.
- **Limit:** `MAX_TOPUP_MINOR = 100_000_000` per top-up or adjustment.

## Code map

- `backend/etqan/wallet/models.py`
- `backend/etqan/wallet/services/`: `ledger.py`, `online.py`, `topup_purpose.py`,
  `compensation.py`, `reads.py`
- `backend/etqan/wallet/api/`
- Billing side: `backend/etqan/billing/services/payments.py` (`record_wallet_payment`,
  `credit_payment`, `refund_topup_payment`), `billing/services/records.py:record_topup_payment`
- `dashboard/src/features/wallet/`

## Design history

- [B3 phase design](../superpowers/specs/2026-10-03-b3-money-depth-design.md): B3-11 ("a ledger,
  never a stored balance"). Refined by B3e E-3, which keeps `balance_minor` as a cache written
  with each entry.
- [B3e student wallet](../superpowers/specs/2026-10-06-b3e-student-wallet-design.md): the full
  design, including Part B compensation (E-23).
- Plan: [Plan 40 student wallet](../superpowers/plans/2026-10-06-plan-40-student-wallet.md).
- Teacher balances are a separate feature (`etqan.payroll`, B4c) and are not covered here.
