---
title: "Self-registration"
---

Lets a public visitor create their own account on an academy's site. There are two paths:

- an **adult learner** (18 or older) registers themselves as a student
- a **parent** registers themselves and one to five children

The visitor confirms their email. The accounts then become active, either straight away or after an admin approves them when the academy keeps a waiting list. Registration codes let chosen visitors skip that waiting list. Admins, and staff with `registration.*` codes, review registrations under People → Registrations.

## Concepts

All tables are in the academy schema (`etqan.registration`, in `TENANT_APPS`).

| Model | Purpose |
|---|---|
| `Registration` | `kind` (`adult` / `parent`), `registrant` (FK `User`), `students` (M2M `User`: the adult themselves, or the children), scheduling preferences (`start_on`, `hours_per_week` 1–40, `preferred_days` Mon=0…Sun=6, `intro_call_at` UTC, `teacher_gender`), optional `code`, `consented_at`, `status`, `reject_reason`, `decided_by` / `decided_at`. |
| `Registration.status` | `unconfirmed`, then `pending` (waiting list) or `approved`. From `pending` it can become `approved` or `rejected`. A registration still `unconfirmed` after 7 days becomes `expired`. |
| `RegistrationCode` | `code` (6–32 characters, stored lower-case, can't be changed), `label`, `uses_left` (null means unlimited), `expires_at`, `is_active`. |

People are always created through `identity.services.register_person`, as **inactive** `User` rows with the person's own validated password. Children are created without an email or password, so they have no login.

## How it works

1. **The register page** reads `GET identity/sign-in-options/` to learn whether to show the form (`self_registration`), the code field (`waitlist`) and the parent path (`parent_registration` = `self_registration` and `parents` both on).

2. **Submitting** (`POST registration/`, `registration/services.py:register`):
   - **Limits** (`registration/limits.py`):
     - 10 attempts per IP per hour, counting every attempt.
     - 3 accepted registrations per email per day. Refused attempts give their slot back.
     - Either limit answers 429 with `Retry-After`.
   - **Honeypot:** a non-empty `website` field gets a fake `201` and nothing is created.
   - **Checks** (`_check_everything`) run before anything is written:
     - names
     - an adult must be 18 or older; a parent needs one to five children, each under 18
     - consent
     - `es` only while `spanish` is on
     - preferences
     - every person passes `identity.services.check_person` (including the password validators)
     - any code given must be live
   - **Taken email:** if the email is already used, the answer is the same `201 {"status": "received"}` and nothing is created. The owner of the address gets one "someone tried to register" email per day (`notify_taken`).
   - **Creation:** the registrant, the children (if any) and the `Registration` are created. A code's use is spent atomically.
     - If Google already confirmed this email in the session (the Google prefill, see [sign-in.md](sign-in.md)), the address is marked verified and confirmation runs immediately.
     - Otherwise allauth sends a confirmation email.

3. **Email confirmed** (`on_email_confirmed`, connected to allauth's `email_confirmed` signal in `RegistrationConfig.ready`):
   - Only the registrant's primary address counts, and nothing happens in the public schema.
   - If `registration_waitlist` is on and no code was used, the status becomes `pending` and a "received" email goes out.
   - Otherwise the status becomes `approved`, the accounts are activated (`_activate`) and a welcome email goes out.
   - Either way, every active admin gets an "admin_new" email linking to `/app/people/registrations`.

4. **Activation** (`_activate`):
   - Every person in the registration is activated.
   - For a parent registration, each child is linked as the parent's ward (`link_guardian`).
   - If `families` is on, a family named "<parent>'s family" is created with the parent as payer.

5. **Decisions** (`approve`, `reject`):
   - Allowed only while the status is `pending`. Otherwise the answer is 409 `registration.not_pending`.
   - Approving also needs a verified registrant email (`registration.unconfirmed`).
   - Rejecting stores the reason, emails it to the registrant and releases the addresses (`identity.release_emails`). The users stay, inactive and without an email.

6. **Sign-in while waiting:** registration registers `inactive_reason` with identity's sign-in. When a registrant enters the right password, sign-in answers 403 with `identity.email_unverified`, `registration.pending` or `registration.rejected` instead of "Invalid credentials".

7. **Handing off to scheduling:** `registration.services.preferences(registration_id)` returns the scheduling preferences plus the registrant's timezone, for trial intake.

## API

All paths are under `/api/v1/registration/`, and every route needs the `self_registration` switch (404 when it is off).

| Method | Path | Who | Purpose |
|---|---|---|---|
| POST | `` (the base path) | anyone | Register; always `201 {"status":"received"}` unless the input is invalid (400) or a limit is hit (429) |
| GET | `google-prefill/` | anyone | Email and name Google confirmed in this session, else 404 |
| GET | `registrations/` | `registration.view_any` | List (`?status=`), paged, with `pending_count` |
| GET | `registrations/<id>/` | `registration.view` | Detail |
| POST | `registrations/<id>/approve/` | `registration.update` | Approve a pending registration |
| POST | `registrations/<id>/reject/` | `registration.update` | Reject with an optional `reason` |
| GET, POST | `codes/` | `registration_code.view_any` / `registration_code.create` | List / create codes |
| PATCH | `codes/<id>/` | `registration_code.update` | Change label, uses, expiry, active (the code itself is fixed) |

`POST` body fields:

- **Both paths:** `kind`, `email`, `full_name`, `phone`, `password`, `password_confirm`, `country`, `timezone`, `language`, `consent`, preferences, `code`, `website` (honeypot).
- **Adult:** `date_of_birth`, `gender`.
- **Parent:** `children[]` (`full_name`, `date_of_birth`, `gender`). Children inherit the parent's country.

## Dashboard

- `/register` (`routes/register.tsx`, which redirects signed-in users): `features/registration/RegisterPage.tsx` and `RegisterForm.tsx`. `?google=1` fills the form from `google-prefill/`.
- `/people/registrations`: `features/registration/admin/RegistrationsPage.tsx`, `RegistrationDetail.tsx` and `RejectDialog.tsx`. It has status tabs through `?status=` (default `pending`), and the nav shows a pending-count badge.
- `/settings/registration-codes`: `CodesPage.tsx` and `CodeDialog.tsx`.
- The login page links to registration when `sign-in-options` allows it.

## Background jobs

- `registration.expire_unconfirmed`: Celery beat, daily at 03:15 (`CELERY_BEAT_SCHEDULE` in `config/settings/base.py`). It runs `services.expire_unconfirmed` in every academy through `platform.tenancy.for_each_academy`. Registrations still `unconfirmed` after 7 days become `expired`, and their addresses are released.
- All emails (received, welcome, rejected, taken, admin_new) are queued after commit through `identity.services.send_notice` and then `integrations.services.queue_email`. Templates are in `email/registration/<kind>.<lang>.txt` (en/ar/es; anything missing falls back to English).

## Configuration

- **Switches:**
  - `self_registration` (default off)
  - `registration_waitlist` (requires `self_registration`)
  - `parents` (enables the parent path)
  - `families` (creates a family on activation)
  - `spanish` (lets registrants choose `es`)
  - `google_sign_in` (feeds the Google prefill)
- **Constants** in `registration/services.py`: `ADULT_AGE = 18`, `MAX_CHILDREN = 5`, `EXPIRY_DAYS = 7`, `HOURS = (1, 40)`, `CODE_LENGTH = (6, 32)`.

## Code map

- `backend/etqan/registration/models.py`, `services.py`, `limits.py`, `tasks.py`, `apps.py`
- `backend/etqan/registration/api/urls.py`, `views.py`, `serializers.py`
- `backend/etqan/identity/services.py`: `check_person`, `register_person`, `email_in_use`, `release_emails`, `google_prefill`
- `backend/etqan/identity/signin.py`: `register_inactive_reason`, `options`
- `dashboard/src/features/registration/` (public form) and `dashboard/src/features/registration/admin/`
- `dashboard/src/routes/register.tsx`, `routes/_authed/people.registrations.tsx`, `settings.registration-codes.tsx`

## Design history

- [B9c registration](../superpowers/specs/2026-10-03-b9c-registration-design.md) and [plan 28](../superpowers/plans/2026-10-04-plan-28-registration.md): R-1…R-8 (paths, confirmation, waiting list, codes, abuse limits, refusal reasons). The same slice also built code reset and Google sign-in, which are documented in [sign-in.md](sign-in.md).
- [B9d languages](../superpowers/specs/2026-10-04-b9d-languages-design.md): Spanish emails and the `es` language rule.
- [People & catalogue design](../superpowers/specs/2026-09-24-people-catalogue-design.md) P3-2 said accounts are created by admins only. B9c superseded that for students and parents through this API. allauth's own sign-up is still closed (`CeleryAccountAdapter.is_open_for_signup`).
