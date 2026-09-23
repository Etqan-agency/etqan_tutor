# Registration polish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Collect birthdate at registration (backend + dashboard) and redirect authenticated users away from /login and /register.

**Architecture:** Backend adds a nullable `User.birthdate` + a required serializer field. Dashboard adds a date input + a `redirectIfAuthed` route guard. Spec: `docs/superpowers/specs/2026-06-19-registration-polish-design.md`.

**Tech Stack:** Django 5 / DRF / pytest-django; React 19 / TanStack Router+Query / react-hook-form / zod / vitest.

## Global Constraints

- Backend: 100% line+branch coverage; ruff + mypy + import-linter green. Business logic in `services.py`.
- **Adding a required `birthdate` to `RegisterSerializer` breaks every existing register caller.** Update ALL register payloads/helpers in the same task: `test_api_auth.py::_register_payload`, `test_api_resend_verification.py::_register`, `test_email_branding.py::_register`.
- `birthdate` is stored only; never emailed or shown to other users (ADR-0023). No age-gating in this slice.
- Dashboard: a11y/i18n baseline (en+ar, jest-axe, RTL); tsc + biome clean. `toast()`/Toaster already exist.

---

### Task 1: Backend — birthdate at registration

**Files:**
- Modify: `kaleem/identity/models.py`, `kaleem/identity/api/serializers.py`, `kaleem/identity/services.py`, `kaleem/identity/api/views.py`
- Create: `kaleem/identity/migrations/0004_user_birthdate.py`
- Test/modify: `kaleem/identity/tests/test_api_auth.py`, `test_api_resend_verification.py`, `test_email_branding.py`

**Interfaces:**
- Produces: `register_user(full_name, email, password, account_type, birthdate)`; `RegisterSerializer` with required `birthdate`.

- [ ] **Step 1: Write/adjust failing tests**

In `test_api_auth.py`, add `"birthdate": "1990-05-15"` to `_register_payload`'s default dict, and add:

```python
from datetime import date, timedelta


class TestRegisterBirthdate:
    def test_register_stores_birthdate(self, api):
        resp = api.post(
            "/api/v1/identity/register/", _register_payload(), format="json"
        )
        assert resp.status_code == 201, resp.data
        user = User.objects.get(email="ahmad@example.com")
        assert user.birthdate == date(1990, 5, 15)

    def test_register_without_birthdate_returns_400(self, api):
        payload = _register_payload()
        del payload["birthdate"]
        resp = api.post("/api/v1/identity/register/", payload, format="json")
        assert resp.status_code == 400
        assert "birthdate" in resp.data

    def test_register_future_birthdate_returns_400(self, api):
        future = (date.today() + timedelta(days=1)).isoformat()
        resp = api.post(
            "/api/v1/identity/register/",
            _register_payload(birthdate=future),
            format="json",
        )
        assert resp.status_code == 400
        assert "birthdate" in resp.data
```

Also add `"birthdate": "1990-05-15"` to the register POST bodies in
`test_api_resend_verification.py::_register` and `test_email_branding.py::_register`.

- [ ] **Step 2: Run to verify failures**

Run: `cd backend && DATABASE_URL=postgres://kaleem:kaleem@localhost:5432/kaleem python -m pytest kaleem/identity/tests/test_api_auth.py::TestRegisterBirthdate -p no:cacheprovider -q --create-db`
Expected: FAIL (no `birthdate` field/column yet).

- [ ] **Step 3: Add the model field + migration**

In `models.py`, add to `User` (after `full_name`):

```python
    birthdate = models.DateField(null=True, blank=True)
```

Create `kaleem/identity/migrations/0004_user_birthdate.py`:

```python
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("identity", "0003_set_site_name_domain")]

    operations = [
        migrations.AddField(
            model_name="user",
            name="birthdate",
            field=models.DateField(blank=True, null=True),
        ),
    ]
```

- [ ] **Step 4: Serializer field + validation**

In `serializers.py`, add to `RegisterSerializer` (after `account_type`):

```python
    birthdate = serializers.DateField()

    def validate_birthdate(self, value):
        from datetime import date, timedelta

        if value > date.today():
            raise serializers.ValidationError("Birthdate cannot be in the future.")
        if value < date.today() - timedelta(days=365 * 120):
            raise serializers.ValidationError("Birthdate is not valid.")
        return value
```

Add `birthdate = serializers.DateField()` to `RegisterResponseSerializer` (doc only).

- [ ] **Step 5: Thread through service + view**

In `services.py`, update `register_user`:

```python
@transaction.atomic
def register_user(
    full_name: str, email: str, password: str, account_type: str, birthdate=None
) -> User:
    """Create an adult user with their initial profile (student or parent)."""
    if account_type not in ACCOUNT_TYPES:
        raise ValidationError("Invalid account type.", field="account_type")
    user = User.objects.create_user(
        email=email, password=password, full_name=full_name, birthdate=birthdate
    )
    if account_type == "student":
        StudentProfile.objects.create(user=user)
    else:
        ParentProfile.objects.create(user=user)
    return user
```

In `views.py` `RegisterView.post`, add `birthdate=data["birthdate"],` to the `services.register_user(...)` call. If the response payload echoes fields, include `"birthdate": user.birthdate` so `RegisterResponseSerializer` matches (check the existing response dict; add the key in the same shape the view already returns).

- [ ] **Step 6: Run backend gate**

Run: `cd backend && DATABASE_URL=postgres://kaleem:kaleem@localhost:5432/kaleem python -m pytest kaleem/identity -p no:cacheprovider -q --create-db && ruff check . && ruff format --check . && mypy kaleem/identity && lint-imports`
Expected: all green; 100% coverage on changed lines.

- [ ] **Step 7: Commit**

```bash
cd backend && git add -A && git commit -m "feat(identity): collect birthdate at registration"
```

---

### Task 2: Dashboard — birthdate field on RegisterForm

**Files:**
- Modify: `src/features/identity/schemas.ts`, `src/features/identity/components/RegisterForm.tsx`, `src/locales/en/common.json`, `src/locales/ar/common.json`
- Test: `src/features/identity/components/RegisterForm.test.tsx`

- [ ] **Step 1: Update the test**

In `RegisterForm.test.tsx`, in the successful-submit test, fill the birthdate input
(`screen.getByLabelText(/birth/i)` → `userEvent.type(..., "1990-05-15")` or `fireEvent.change`)
and assert the mocked `register` API was called with `birthdate: "1990-05-15"`. (Use
`userEvent` directly, not `.setup()`.)

- [ ] **Step 2: Run to confirm failure**

Run: `cd dashboard && node_modules/.bin/vitest run src/features/identity/components/RegisterForm.test.tsx`
Expected: FAIL.

- [ ] **Step 3: Schema + form field + i18n**

In `schemas.ts`, add to `registerSchema`:

```ts
	birthdate: z
		.string()
		.min(1)
		.refine((v) => !Number.isNaN(Date.parse(v)) && new Date(v) <= new Date(), {
			message: "Enter a valid birthdate.",
		}),
```

In `RegisterForm.tsx`, add after the password Field:

```tsx
			<Field
				id="birthdate"
				label={t("auth.birthdate")}
				error={errors.birthdate?.message}
			>
				<Input type="date" {...register("birthdate")} />
			</Field>
```

Add `"birthdate": "Date of birth"` to `en/common.json` `auth`, and `"birthdate": "تاريخ الميلاد"` to `ar/common.json` `auth`.

- [ ] **Step 4: Run + typecheck**

Run: `cd dashboard && node_modules/.bin/vitest run src/features/identity/components/RegisterForm.test.tsx && node_modules/.bin/tsc --noEmit`
Expected: PASS / clean.

- [ ] **Step 5: Commit**

```bash
cd dashboard && git add -A && git commit -m "feat(identity): birthdate field on registration form"
```

---

### Task 3: Dashboard — redirect authed users from /login + /register

**Files:**
- Modify: `src/features/identity/queries.ts`, `src/routes/login.tsx`, `src/routes/register.tsx`
- Test: `src/features/identity/queries.test.tsx` (or a new `redirect-if-authed.test.ts`)

**Interfaces:** Produces `redirectIfAuthed(qc: QueryClient): Promise<void>` (throws a router `redirect` when authed).

- [ ] **Step 1: Write the failing test**

In `src/features/identity/queries.test.tsx` (create if absent), add:

```tsx
import type { QueryClient } from "@tanstack/react-query";
import { expect, test, vi } from "vitest";
import { redirectIfAuthed } from "./queries";

test("redirectIfAuthed throws a redirect when the session is valid", async () => {
	const qc = {
		ensureQueryData: vi.fn().mockResolvedValue({ id: 1 }),
	} as unknown as QueryClient;
	await expect(redirectIfAuthed(qc)).rejects.toMatchObject({ to: "/" });
});

test("redirectIfAuthed resolves (no redirect) when unauthenticated", async () => {
	const qc = {
		ensureQueryData: vi.fn().mockRejectedValue(new Error("401")),
	} as unknown as QueryClient;
	await expect(redirectIfAuthed(qc)).resolves.toBeUndefined();
});
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd dashboard && node_modules/.bin/vitest run src/features/identity/queries.test.tsx`
Expected: FAIL (no `redirectIfAuthed`).

- [ ] **Step 3: Implement the helper**

In `queries.ts`, add `redirect` to the router import and append:

```ts
import { redirect } from "@tanstack/react-router";

// Inverse of ensureAuthed: used by /login + /register beforeLoad. If the session
// is valid, bounce to the app home; otherwise let the page render.
export async function redirectIfAuthed(qc: QueryClient): Promise<void> {
	try {
		await ensureAuthed(qc);
	} catch {
		return;
	}
	throw redirect({ to: "/" });
}
```

- [ ] **Step 4: Wire the route guards**

In `routes/login.tsx` and `routes/register.tsx`, change the `createFileRoute(...)` call to add a `beforeLoad`:

```tsx
import { redirectIfAuthed } from "@/features/identity/queries";
// …
export const Route = createFileRoute("/login")({
	beforeLoad: ({ context }) => redirectIfAuthed(context.queryClient),
	component: LoginPage,
});
```

(Analogously for `/register`.)

- [ ] **Step 5: Full dashboard gate**

Run: `cd dashboard && node_modules/.bin/vitest run && node_modules/.bin/tsc --noEmit && node_modules/.bin/biome check src`
Expected: all green/clean.

- [ ] **Step 6: Commit**

```bash
cd dashboard && git add -A && git commit -m "feat(identity): redirect authed users away from login/register"
```
