# Email Verification & Login Integrity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An unverified email can never grant access, and the `/verify-email` landing page always resolves to a clear success/error state.

**Architecture:** Two bug fixes over the shipped Phase A identity flow. Backend: the login verification gate checks the *submitted* email's verification, not "any verified email"; plus a tiny CSRF-cookie endpoint. Frontend: the verify-email page fetches a CSRF token before confirming and resolves to a deterministic terminal state (no flaky auto-redirect timer).

**Tech Stack:** Django + DRF + django-allauth (backend); React 19 + TanStack Router/Query + axios + vitest + jest-axe (dashboard).

## Global Constraints

- **TDD, failing test first** — every code change starts with a test that fails for the right reason (D3).
- **100% coverage (line + branch)** in each repo's CI; no blanket exclusions.
- **Backend:** business logic in `services.py`, never on models; module boundaries enforced (`lint-imports` green); `ruff` + `mypy` clean. CSRF middleware stays ENABLED.
- **Backend commits:** run with `PIP_CONFIG_FILE=/dev/null git commit …` (a dead pip proxy otherwise breaks the pre-commit hook). Never `--no-verify`.
- **Dashboard:** API base URL from `VITE_API_URL` (never hardcode); en + ar with full RTL; `jest-axe` clean; `tsc` + `biome` clean.
- **Git-flow (ADR-0014):** backend work on `feat/login-verification-gate` → `main`; dashboard work on `feat/verify-email-fix` → `main`; meta docs/pointers on a `feat/…` → `develop`. No direct commits to a trunk.
- **Login policy (decided):** any *verified* email may be used to sign in; an *unverified* email is always rejected with `400 "Email address is not verified."`

---

## Repo: `backend/` — branch `feat/login-verification-gate`

### Task 1: Per-email login verification gate (#9 + #1 lock-in)

**Files:**
- Modify: `backend/kaleem/identity/api/views.py` (`_email_is_verified` helper + `LoginView.post`)
- Test: `backend/kaleem/identity/tests/test_api_auth.py` (extend `TestEmailVerification`)

**Interfaces:**
- Consumes: `LoginSerializer.validated_data` already contains both `"email"` (the submitted address) and `"user"` (the authenticated user).
- Produces: `_email_is_verified(user, email: str) -> bool` — True only when an `EmailAddress` for `user` matching `email` (case-insensitive) has `verified=True`.

- [ ] **Step 1: Write the failing tests**

Add to `backend/kaleem/identity/tests/test_api_auth.py`, inside `class TestEmailVerification`:

```python
    def test_login_with_unverified_secondary_email_blocked(
        self, api, mandatory_verification
    ):
        user = User.objects.create_user(
            email="primary@example.com",
            password="sup3r-secret-pw",
            full_name="P",
        )
        EmailAddress.objects.create(
            user=user, email="primary@example.com", primary=True, verified=True
        )
        EmailAddress.objects.create(
            user=user, email="second@example.com", primary=False, verified=False
        )
        resp = api.post(
            "/api/v1/identity/login/",
            {"email": "second@example.com", "password": "sup3r-secret-pw"},
            format="json",
        )
        assert resp.status_code == 400, resp.data
        assert resp.data["non_field_errors"][0] == "Email address is not verified."

    def test_login_with_verified_secondary_email_allowed(
        self, api, mandatory_verification
    ):
        user = User.objects.create_user(
            email="primary@example.com",
            password="sup3r-secret-pw",
            full_name="P",
        )
        EmailAddress.objects.create(
            user=user, email="primary@example.com", primary=True, verified=True
        )
        EmailAddress.objects.create(
            user=user, email="second@example.com", primary=False, verified=True
        )
        resp = api.post(
            "/api/v1/identity/login/",
            {"email": "second@example.com", "password": "sup3r-secret-pw"},
            format="json",
        )
        assert resp.status_code == 200, resp.data

    def test_primary_login_unaffected_by_added_unverified_email(
        self, api, mandatory_verification
    ):
        user = User.objects.create_user(
            email="primary@example.com",
            password="sup3r-secret-pw",
            full_name="P",
        )
        EmailAddress.objects.create(
            user=user, email="primary@example.com", primary=True, verified=True
        )
        EmailAddress.objects.create(
            user=user, email="second@example.com", primary=False, verified=False
        )
        resp = api.post(
            "/api/v1/identity/login/",
            {"email": "primary@example.com", "password": "sup3r-secret-pw"},
            format="json",
        )
        assert resp.status_code == 200, resp.data
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd backend && pytest kaleem/identity/tests/test_api_auth.py::TestEmailVerification -v`
Expected: the new `..._secondary_email_blocked` test FAILS (it currently returns `200` because the gate only checks "any verified email exists"). The two `_allowed`/`_unaffected` tests may already pass.

- [ ] **Step 3: Implement the per-email gate**

In `backend/kaleem/identity/api/views.py`, change the helper signature:

```python
def _email_is_verified(user, email: str) -> bool:
    return EmailAddress.objects.filter(
        user=user, email__iexact=email, verified=True
    ).exists()
```

And in `LoginView.post`, pass the submitted email:

```python
    def post(self, request):
        serializer = LoginSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data["user"]
        email = serializer.validated_data["email"]
        if (
            settings.ACCOUNT_EMAIL_VERIFICATION == "mandatory"
            and not _email_is_verified(user, email)
        ):
            return Response(
                {"non_field_errors": ["Email address is not verified."]},
                status=status.HTTP_400_BAD_REQUEST,
            )
        login(request, user)
        return Response(_me_payload(user))
```

- [ ] **Step 4: Run the identity tests to verify they pass**

Run: `cd backend && pytest kaleem/identity/tests/test_api_auth.py -v`
Expected: PASS — including the pre-existing `test_login_blocked_when_email_unverified` and `test_login_allowed_once_email_verified` (they log in with the same address that carries the verified flag, so the per-email check keeps them green).

- [ ] **Step 5: Run lint + the full backend suite**

Run: `cd backend && ruff check . && ruff format --check . && mypy kaleem && lint-imports && pytest`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
cd backend
git checkout -b feat/login-verification-gate
git add kaleem/identity/api/views.py kaleem/identity/tests/test_api_auth.py
PIP_CONFIG_FILE=/dev/null git commit -m "fix(identity): gate login on the submitted email's verification

A user with a verified primary plus a freshly-added unverified email could
sign in using the unverified address, because the gate only checked whether
the user had any verified email. Check the submitted email specifically.
Any verified email still works; unverified is always rejected.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: CSRF-cookie endpoint (`GET identity/csrf/`)

**Files:**
- Modify: `backend/kaleem/identity/api/views.py` (new `CsrfView`)
- Modify: `backend/kaleem/identity/api/urls.py` (new route)
- Test: `backend/kaleem/identity/tests/test_api_auth.py` (new `TestCsrf` class)

**Interfaces:**
- Produces: `GET /api/v1/identity/csrf/` → `200`, `AllowAny`, sets the `csrftoken` cookie via `@ensure_csrf_cookie`. The dashboard's public `/verify-email` page calls this before its confirm POST so the POST carries a CSRF token on first contact.

- [ ] **Step 1: Write the failing test**

Add to `backend/kaleem/identity/tests/test_api_auth.py`:

```python
@pytest.mark.django_db
class TestCsrf:
    def test_csrf_endpoint_sets_cookie(self, api):
        resp = api.get("/api/v1/identity/csrf/")
        assert resp.status_code == 200
        assert "csrftoken" in resp.cookies
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd backend && pytest kaleem/identity/tests/test_api_auth.py::TestCsrf -v`
Expected: FAIL with `404` (route does not exist yet).

- [ ] **Step 3: Implement the view**

Add to `backend/kaleem/identity/api/views.py` (imports at top of file):

```python
from django.utils.decorators import method_decorator
from django.views.decorators.csrf import ensure_csrf_cookie
```

```python
@method_decorator(ensure_csrf_cookie, name="get")
class CsrfView(APIView):
    permission_classes = [AllowAny]

    @extend_schema(
        responses={200: OpenApiResponse(description="csrftoken cookie set.")},
        summary="Set the csrftoken cookie (for public pages that POST).",
    )
    def get(self, request):
        return Response(status=status.HTTP_200_OK)
```

- [ ] **Step 4: Wire the route**

In `backend/kaleem/identity/api/urls.py`, add the import and a path:

```python
from kaleem.identity.api.views import CsrfView
```

```python
    path("csrf/", CsrfView.as_view(), name="csrf"),
```

- [ ] **Step 5: Run the test + lint to verify pass**

Run: `cd backend && pytest kaleem/identity/tests/test_api_auth.py::TestCsrf -v && ruff check . && mypy kaleem && lint-imports`
Expected: PASS, all green.

- [ ] **Step 6: Commit**

```bash
cd backend
git add kaleem/identity/api/views.py kaleem/identity/api/urls.py kaleem/identity/tests/test_api_auth.py
PIP_CONFIG_FILE=/dev/null git commit -m "feat(identity): add GET identity/csrf/ to set the csrftoken cookie

The public /verify-email page POSTs the confirmation key, but a user
arriving fresh from an email link has no csrftoken cookie yet. This
endpoint guarantees one so the POST passes CSRF on first contact.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Repo: `dashboard/` — branch `feat/verify-email-fix`

### Task 3: Fetch a CSRF token before confirming (#6 — API layer)

**Files:**
- Modify: `dashboard/src/features/identity/api.ts` (`verifyEmail`)
- Test: `dashboard/src/features/identity/api.test.ts`

**Interfaces:**
- Consumes: `GET identity/csrf/` (Task 2).
- Produces: `identityApi.verifyEmail(key)` now issues `GET identity/csrf/` **before** `POST identity/verify-email/`, both via the shared `api` axios instance. Signature unchanged: `(key: string) => Promise<void>`.

- [ ] **Step 1: Write the failing test**

Edit `dashboard/src/features/identity/api.test.ts`. First, add these two imports to the **top** of the file (alongside the existing imports — ESM imports must be at the top):

```ts
import { api } from "@/lib/api";
import { identityApi } from "./api";
```

Then add this `vi.mock` near the top (after the imports; `vi.mock` is hoisted so placement is flexible) and the new `describe` block at the end of the file. The existing `parseApiError` tests only reference `parseApiError`, so mocking `@/lib/api` does not affect them:

```ts
vi.mock("@/lib/api", () => ({
	api: {
		get: vi.fn().mockResolvedValue({ data: {} }),
		post: vi.fn().mockResolvedValue({ data: undefined }),
	},
}));

describe("identityApi.verifyEmail", () => {
	it("fetches a CSRF token before POSTing the key", async () => {
		await identityApi.verifyEmail("the-key");
		expect(api.get).toHaveBeenCalledWith("identity/csrf/");
		expect(api.post).toHaveBeenCalledWith("identity/verify-email/", {
			key: "the-key",
		});
		const getOrder = vi.mocked(api.get).mock.invocationCallOrder[0];
		const postOrder = vi.mocked(api.post).mock.invocationCallOrder[0];
		expect(getOrder).toBeLessThan(postOrder);
	});
});
```

Add `vi` to the existing `vitest` import at the top of the file: `import { describe, expect, it, vi } from "vitest";`

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd dashboard && pnpm exec vitest run src/features/identity/api.test.ts`
Expected: FAIL — `api.get` is never called (current `verifyEmail` only POSTs).

- [ ] **Step 3: Implement the CSRF bootstrap**

In `dashboard/src/features/identity/api.ts`, change `verifyEmail`:

```ts
	verifyEmail: (key: string) =>
		api
			.get("identity/csrf/")
			.then(() => api.post("identity/verify-email/", { key }))
			.then(() => undefined),
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd dashboard && pnpm exec vitest run src/features/identity/api.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd dashboard
git checkout -b feat/verify-email-fix
git add src/features/identity/api.ts src/features/identity/api.test.ts
git commit -m "fix(identity): fetch a CSRF token before confirming an email

A user arriving at /verify-email straight from the email link has no
csrftoken cookie, so the confirm POST could fail CSRF. GET identity/csrf/
first to guarantee the cookie.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Deterministic verify-email terminal state (#6 — page)

**Files:**
- Modify: `dashboard/src/routes/verify-email.tsx` (stabilize the effect; drop the `setTimeout` auto-redirect)
- Test: `dashboard/src/routes/verify-email.test.tsx`

**Interfaces:**
- Consumes: `useVerifyEmail()` mutation (unchanged); `VerifyEmailPage({ verifyKey, onVerified })` (signature unchanged).
- Produces: a page that always lands on the success or error branch — never stuck on the spinner — and whose success state offers an explicit "Go to sign in" link (no timer-based redirect).

- [ ] **Step 1: Write the failing/regression tests**

Add to `dashboard/src/routes/verify-email.test.tsx`, inside `describe("VerifyEmailPage", …)`:

```ts
	it("settles out of the spinner and offers a sign-in link on success", async () => {
		vi.mocked(identityApi.verifyEmail).mockResolvedValue(undefined);
		renderPage("good-key");
		await waitFor(() =>
			expect(screen.getByText(/email verified/i)).toBeInTheDocument(),
		);
		// the loading copy must be gone (no perpetual spinner)
		expect(screen.queryByText(/verifying your email/i)).not.toBeInTheDocument();
		expect(screen.getByRole("link", { name: /go to sign in/i })).toBeInTheDocument();
	});

	it("calls verifyEmail exactly once", async () => {
		vi.mocked(identityApi.verifyEmail).mockResolvedValue(undefined);
		renderPage("good-key");
		await waitFor(() =>
			expect(screen.getByText(/email verified/i)).toBeInTheDocument(),
		);
		expect(identityApi.verifyEmail).toHaveBeenCalledTimes(1);
	});
```

Add an accessibility test in the same file (jest-axe is the repo baseline). Add this import at the top:

```ts
import { axe } from "jest-axe";
```

and this test inside the describe:

```ts
	it("has no a11y violations in the success state", async () => {
		vi.mocked(identityApi.verifyEmail).mockResolvedValue(undefined);
		const { container } = renderPage("good-key");
		await waitFor(() =>
			expect(screen.getByText(/email verified/i)).toBeInTheDocument(),
		);
		expect(await axe(container)).toHaveNoViolations();
	});
```

- [ ] **Step 2: Run the tests to verify the new ones pass and guard against regression**

Run: `cd dashboard && pnpm exec vitest run src/routes/verify-email.test.tsx`
Expected: the success/error/once/a11y tests PASS. (If `verifyEmail` is called more than once or the spinner persists, they FAIL — that is the regression guard for #6.)

- [ ] **Step 3: Stabilize the effect and drop the auto-redirect**

In `dashboard/src/routes/verify-email.tsx`, change the effect so it depends only on `verifyKey` (the `started` ref already guards single-fire; depending on the unstable `verify`/`onVerified` re-runs the effect on every render):

```tsx
	useEffect(() => {
		if (started.current || !verifyKey) return;
		started.current = true;
		verify.mutate(verifyKey, { onSuccess: onVerified });
		// biome-ignore lint/correctness/useExhaustiveDependencies: confirm once per key; the ref guards re-fires
	}, [verifyKey]);
```

Replace the route component so success is user-driven (no `setTimeout` redirect) and remove the now-unused `useNavigate` import:

```tsx
export const Route = createFileRoute("/verify-email")({
	validateSearch: (search: Record<string, unknown>) => ({
		key: typeof search.key === "string" ? search.key : "",
	}),
	component: function VerifyEmailRoute() {
		const { key } = Route.useSearch();
		return <VerifyEmailPage verifyKey={key} onVerified={() => {}} />;
	},
});
```

Update the top import (drop `useNavigate`):

```tsx
import { createFileRoute, Link } from "@tanstack/react-router";
```

- [ ] **Step 4: Run tests + typecheck + lint**

Run: `cd dashboard && pnpm exec vitest run src/routes/verify-email.test.tsx && pnpm exec tsc --noEmit && pnpm exec biome check src/routes/verify-email.tsx src/routes/verify-email.test.tsx`
Expected: PASS, no type errors, biome clean.

- [ ] **Step 5: Commit**

```bash
cd dashboard
git add src/routes/verify-email.tsx src/routes/verify-email.test.tsx
git commit -m "fix(identity): make /verify-email resolve deterministically

Run the confirm effect once per key (ref-guarded; deps narrowed to the key)
and drop the setTimeout auto-redirect in favour of the explicit sign-in
link, so the page always lands on a terminal success/error state.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Full-suite verification + live browser check

**Files:** none (verification + notes only).

- [ ] **Step 1: Run each repo's full suite**

Run: `cd backend && PIP_CONFIG_FILE=/dev/null pytest && cd ../dashboard && pnpm test && pnpm build`
Expected: backend suite green; dashboard `vitest run` green; `tsc && vite build` succeeds.

- [ ] **Step 2: Reproduce-then-confirm in the browser (the #6 acceptance)**

Bring up the stack: `just dev`. Then, with a registered-but-unverified user:
1. Trigger a verification email (register, or add an email on `/account`), open the link in mailpit (`http://localhost:8025`) — it points at `…/verify-email?key=…`.
2. Open that link in a fresh browser profile (no prior session/cookie). Confirm the page shows **success** (not a perpetual spinner) and a "Go to sign in" link, and the network tab shows `GET identity/csrf/` then `POST identity/verify-email/` → `200`.
3. If a hang still reproduces, apply superpowers:systematic-debugging against the live network/console before changing code — capture the failing request, then add a failing test that encodes the real cause and fix it.

- [ ] **Step 3: Verify the login gate in the browser**

On `/account`, add a new email (it is created unverified). Sign out, then attempt to sign in with the new unverified address → expect the "Email address is not verified." error. Sign in with the original (verified) address → success.

- [ ] **Step 4: Log the e2e-harness gap to ISSUES**

The dashboard has no Playwright harness yet (every slice so far ships vitest + jest-axe + a manual browser check). Add one line under `## Now` in `ISSUES.md`:

```markdown
- No Playwright e2e harness in the dashboard yet; D3/D9 e2e is currently met by a
  manual browser click-through. Stand up Playwright as its own slice so the
  verify-email + login-gate happy/failure paths run in CI. (Surfaced 2026-06-18.)
```

(Commit this with the meta-repo docs in the shipping step below.)

---

## Integration & shipping (D9)

Not TDD tasks — the close-out, all through git-flow:

1. Open PRs: backend `feat/login-verification-gate` → `main`; dashboard `feat/verify-email-fix` → `main`. Green CI on both.
2. After both merge, on a meta `feat/…` → `develop` branch: bump the `backend` + `dashboard` submodule pointers, mark this spec `status: shipped`, update `STATE.md`, and add the `ISSUES.md` line from Task 5 Step 4.
3. Promote meta `develop → master` to deploy staging; re-run the Task 5 browser checks against `app-staging` to close the slice.

## Self-review notes (coverage vs spec)

- #9 (login gate) → Task 1. #1 (change-email invariant) → locked in by Task 1's `test_primary_login_unaffected_by_added_unverified_email` (old verified email keeps working; new unverified one is rejected); no new endpoint, per the decision. #2 (frontend activation page) → already implemented in the adapter; exercised by Tasks 3–4 and the Task 5 browser check. #6 (spin/CSRF) → Tasks 2–4 + Task 5 live verification.
- No new data model or settings changes; CSRF middleware stays enabled; module stays within `identity` (no boundary changes).
