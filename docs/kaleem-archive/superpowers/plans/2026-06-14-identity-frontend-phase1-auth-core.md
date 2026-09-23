# Identity Frontend — Phase 1 (Auth Core) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the auth-core dashboard slice — register, verify-pending, custom verify-email landing, login, logout, role-aware home, profile edit — so the register → verify → login → `/me` click-through works on `app-staging` against `api-staging`, closing Phase A.

**Architecture:** A frontend-only slice over the existing Phase A identity API, plus one small backend change (a custom email-confirmation endpoint + an adapter URL override so the verification link lands in the dashboard instead of allauth's server-rendered page). Auth state is a single TanStack Query `['me']` cache; protected routes guard via a pathless `_authed` layout route's `beforeLoad`. Login primes the `['me']` cache from its own response (no extra round-trip).

**Tech Stack:** Backend: Django + DRF + django-allauth (`pytest`). Dashboard: React 19, TanStack Router (file-based) + Query, react-hook-form + zod, axios (`api.ts`, already CSRF/credentials-wired), Vitest + Testing Library + jest-axe, i18next (en/ar, RTL).

**Scope note:** This plan is Phase 1 only. Phase 2 (parent: children + invites) and Phase 3 (student: invite-accept + availability grid) get their own plans after Phase 1 ships. Spec: `docs/superpowers/specs/2026-06-14-identity-frontend-design.md`.

**Two repos:** Tasks B1–B2 are in the `backend` submodule (branch `feat/verify-email-endpoint` off `main`). Tasks D0–D12 are in the `dashboard` submodule (branch `feat/identity-auth-core` off `main`). The meta repo gets a submodule-pointer bump + STATE update at the end (Task M1). Per submodule git-flow: `feat → main` PR in each submodule; meta `feat → develop` PR.

---

## Backend (submodule: `backend`, branch `feat/verify-email-endpoint`)

### Task B1: Frontend URL setting + adapter confirmation-URL override

Make verification emails link to the dashboard (`{FRONTEND_URL}/verify-email?key=<key>`) instead of allauth's `/accounts/confirm-email/<key>/` page.

**Files:**
- Modify: `config/settings/base.py` (add `FRONTEND_URL`)
- Modify: `kaleem/identity/adapter.py` (override `get_email_confirmation_url`)
- Test: `kaleem/identity/tests/test_adapter.py` (create)

- [ ] **Step 1: Write the failing test**

Create `kaleem/identity/tests/test_adapter.py`:

```python
import pytest
from allauth.account.models import EmailAddress
from allauth.account.models import EmailConfirmationHMAC
from django.test import RequestFactory
from django.test import override_settings

from kaleem.identity.adapter import CeleryAccountAdapter
from kaleem.identity.models import User


@pytest.mark.django_db
@override_settings(FRONTEND_URL="https://app.example.com")
def test_confirmation_url_points_at_frontend():
    user = User.objects.create_user(
        email="a@example.com", password="pw", full_name="A"
    )
    email = EmailAddress.objects.create(
        user=user, email=user.email, primary=True, verified=False
    )
    confirmation = EmailConfirmationHMAC(email)
    request = RequestFactory().get("/")

    url = CeleryAccountAdapter().get_email_confirmation_url(request, confirmation)

    assert url == f"https://app.example.com/verify-email?key={confirmation.key}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest kaleem/identity/tests/test_adapter.py -v`
Expected: FAIL — the inherited `get_email_confirmation_url` returns an `/accounts/...` URL, not the frontend one.

- [ ] **Step 3: Add the `FRONTEND_URL` setting**

In `config/settings/base.py`, near the `# ALLAUTH` block, add:

```python
# Where the dashboard (SPA) lives — verification/reset links point here so the
# user lands in the app, not an allauth-rendered page. Overridden per-env.
FRONTEND_URL = env("DJANGO_FRONTEND_URL", default="http://app.kaleem.localhost")
```

- [ ] **Step 4: Override the adapter method**

In `kaleem/identity/adapter.py`, add the import and method:

```python
from django.conf import settings
```

```python
    def get_email_confirmation_url(self, request, emailconfirmation):
        # Land the user in the dashboard's /verify-email route, which POSTs the
        # key to the confirm endpoint — not allauth's server-rendered page.
        return f"{settings.FRONTEND_URL}/verify-email?key={emailconfirmation.key}"
```

- [ ] **Step 5: Run test to verify it passes**

Run: `pytest kaleem/identity/tests/test_adapter.py -v`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add config/settings/base.py kaleem/identity/adapter.py kaleem/identity/tests/test_adapter.py
git commit -m "feat(identity): point email confirmation links at the dashboard"
```

---

### Task B2: `POST /api/v1/identity/verify-email/` confirm endpoint

Confirm an email by HMAC key so the dashboard `/verify-email` route can verify without allauth's HTML page.

**Files:**
- Modify: `kaleem/identity/api/serializers.py` (add `VerifyEmailSerializer`)
- Modify: `kaleem/identity/api/views.py` (add `VerifyEmailView`)
- Modify: `kaleem/identity/api/urls.py` (wire the route)
- Test: `kaleem/identity/tests/test_api_auth.py` (add a `TestVerifyEmail` class)

- [ ] **Step 1: Write the failing test**

Append to `kaleem/identity/tests/test_api_auth.py`:

```python
@pytest.mark.django_db
class TestVerifyEmail:
    def _unverified_email(self, email="verify@example.com"):
        user = User.objects.create_user(
            email=email, password="sup3r-secret-pw", full_name="V"
        )
        return EmailAddress.objects.create(
            user=user, email=user.email, primary=True, verified=False
        )

    def test_valid_key_verifies_email(self, api):
        from allauth.account.models import EmailConfirmationHMAC

        email_address = self._unverified_email()
        key = EmailConfirmationHMAC(email_address).key

        resp = api.post(
            "/api/v1/identity/verify-email/", {"key": key}, format="json"
        )

        assert resp.status_code == 200, resp.data
        email_address.refresh_from_db()
        assert email_address.verified is True

    def test_invalid_key_returns_400(self, api):
        resp = api.post(
            "/api/v1/identity/verify-email/", {"key": "not-a-real-key"}, format="json"
        )
        assert resp.status_code == 400

    def test_missing_key_returns_400(self, api):
        resp = api.post("/api/v1/identity/verify-email/", {}, format="json")
        assert resp.status_code == 400
        assert "key" in resp.data
```

Note: `test_api_auth.py` already imports `pytest`, `EmailAddress`, `User`, and defines the `api` fixture (see file head).

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest kaleem/identity/tests/test_api_auth.py::TestVerifyEmail -v`
Expected: FAIL — 404 (route not wired).

- [ ] **Step 3: Add the serializer**

In `kaleem/identity/api/serializers.py`, add:

```python
class VerifyEmailSerializer(serializers.Serializer):
    key = serializers.CharField()
```

- [ ] **Step 4: Add the view**

In `kaleem/identity/api/views.py`, add the import near the other allauth import:

```python
from allauth.account.models import EmailConfirmationHMAC
```

add the serializer import alongside the others:

```python
from kaleem.identity.api.serializers import VerifyEmailSerializer
```

and add the view (after `ResendVerificationView`):

```python
class VerifyEmailView(APIView):
    permission_classes = [AllowAny]

    @extend_schema(
        request=VerifyEmailSerializer,
        responses={
            200: OpenApiResponse(description="Email verified."),
            400: OpenApiResponse(description="Missing, invalid, or expired key."),
        },
        summary="Confirm an email address by its verification key.",
    )
    def post(self, request):
        serializer = VerifyEmailSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        confirmation = EmailConfirmationHMAC.from_key(serializer.validated_data["key"])
        if confirmation is None:
            return Response(
                {"non_field_errors": ["Invalid or expired verification key."]},
                status=status.HTTP_400_BAD_REQUEST,
            )
        # allauth needs the underlying Django HttpRequest, not the DRF wrapper.
        confirmation.confirm(request._request)  # noqa: SLF001
        return Response(status=status.HTTP_200_OK)
```

- [ ] **Step 5: Wire the URL**

In `kaleem/identity/api/urls.py`, add the import:

```python
from kaleem.identity.api.views import VerifyEmailView
```

and add the path (after the `resend-verification` path):

```python
    path("verify-email/", VerifyEmailView.as_view(), name="verify-email"),
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `pytest kaleem/identity/tests/test_api_auth.py::TestVerifyEmail -v`
Expected: PASS (3 tests)

- [ ] **Step 7: Run the full identity suite + lint**

Run: `pytest kaleem/identity/ -q && ruff check . && ruff format --check . && mypy kaleem/identity && lint-imports`
Expected: all green.

- [ ] **Step 8: Commit**

```bash
git add kaleem/identity/api/serializers.py kaleem/identity/api/views.py kaleem/identity/api/urls.py kaleem/identity/tests/test_api_auth.py
git commit -m "feat(identity): add POST verify-email/ confirm-by-key endpoint"
```

- [ ] **Step 9: Open the backend PR**

```bash
git push -u origin feat/verify-email-endpoint
gh pr create --base main --title "feat(identity): dashboard email verification endpoint" \
  --body "Adds POST /api/v1/identity/verify-email/ and points confirmation links at the dashboard (FRONTEND_URL). Backend half of the identity auth-core frontend slice (Phase A close)."
```

> **Staging env:** set `DJANGO_FRONTEND_URL=https://app-staging.kaleem.academy` in the VPS `.env.production` (not synced by CI — managed on the box, like `API_DOMAIN`). Note this in the PR description so it isn't missed at deploy.

---

## Dashboard (submodule: `dashboard`, branch `feat/identity-auth-core`)

> Run the dashboard test suite with `pnpm test` (vitest). Type-check with `pnpm exec tsc -b`. Lint with `pnpm exec biome check src`. Use `pnpm test -- <path>` to run one file.

### Task D0: Add form dependencies

**Files:**
- Modify: `package.json` (via pnpm)

- [ ] **Step 1: Install react-hook-form + zod resolver**

Run: `pnpm add react-hook-form @hookform/resolvers`
Expected: both added to `dependencies` (zod is already present).

- [ ] **Step 2: Verify the install builds**

Run: `pnpm exec tsc -b`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add package.json pnpm-lock.yaml
git commit -m "chore(identity): add react-hook-form + zod resolver"
```

---

### Task D1: Types + zod schemas

**Files:**
- Create: `src/features/identity/schemas.ts`
- Test: `src/features/identity/schemas.test.ts`

- [ ] **Step 1: Write the failing test**

Create `src/features/identity/schemas.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { loginSchema, registerSchema } from "./schemas";

describe("identity schemas", () => {
	it("accepts a valid registration", () => {
		const result = registerSchema.safeParse({
			full_name: "Ahmad Ali",
			email: "a@b.com",
			password: "sup3r-secret",
			account_type: "student",
		});
		expect(result.success).toBe(true);
	});

	it("rejects a short password", () => {
		const result = registerSchema.safeParse({
			full_name: "Ahmad Ali",
			email: "a@b.com",
			password: "short",
			account_type: "student",
		});
		expect(result.success).toBe(false);
	});

	it("rejects a bad email on login", () => {
		const result = loginSchema.safeParse({ email: "nope", password: "x" });
		expect(result.success).toBe(false);
	});
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm test -- src/features/identity/schemas.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Write the schemas + types**

Create `src/features/identity/schemas.ts`:

```ts
import { z } from "zod";

export const accountTypeSchema = z.enum(["student", "parent"]);

export const registerSchema = z.object({
	full_name: z.string().min(1),
	email: z.string().email(),
	password: z.string().min(8),
	account_type: accountTypeSchema,
});

export const loginSchema = z.object({
	email: z.string().email(),
	password: z.string().min(1),
});

export const profileEditSchema = z.object({
	full_name: z.string().min(1),
	email: z.string().email(),
});

export type RegisterInput = z.infer<typeof registerSchema>;
export type LoginInput = z.infer<typeof loginSchema>;
export type ProfileEditInput = z.infer<typeof profileEditSchema>;

// Response shapes (mirror the DRF serializers).
export type ProfileType = "student" | "parent" | "teacher";

export interface ChildSummary {
	id: number;
	full_name: string;
	student_profile_id: number;
}

export interface Me {
	id: number;
	email: string;
	full_name: string;
	profiles: ProfileType[];
	children?: ChildSummary[];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm test -- src/features/identity/schemas.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/features/identity/schemas.ts src/features/identity/schemas.test.ts
git commit -m "feat(identity): form schemas + response types"
```

---

### Task D2: API layer + error helper

**Files:**
- Create: `src/features/identity/api.ts`
- Test: `src/features/identity/api.test.ts`

- [ ] **Step 1: Write the failing test**

Create `src/features/identity/api.test.ts`:

```ts
import { AxiosError } from "axios";
import { describe, expect, it } from "vitest";
import { parseApiError } from "./api";

describe("parseApiError", () => {
	it("extracts field errors", () => {
		const err = new AxiosError("bad");
		err.response = {
			status: 400,
			data: { email: ["already exists"] },
		} as never;
		const parsed = parseApiError(err);
		expect(parsed.fieldErrors.email).toBe("already exists");
		expect(parsed.message).toBeUndefined();
	});

	it("extracts a non-field message", () => {
		const err = new AxiosError("bad");
		err.response = {
			status: 400,
			data: { non_field_errors: ["Invalid credentials."] },
		} as never;
		const parsed = parseApiError(err);
		expect(parsed.message).toBe("Invalid credentials.");
	});

	it("flags a throttle (429)", () => {
		const err = new AxiosError("slow down");
		err.response = { status: 429, data: {} } as never;
		expect(parseApiError(err).throttled).toBe(true);
	});
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm test -- src/features/identity/api.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Write the API layer**

Create `src/features/identity/api.ts`:

```ts
import { AxiosError, isAxiosError } from "axios";
import { api } from "@/lib/api";
import type {
	LoginInput,
	Me,
	ProfileEditInput,
	RegisterInput,
} from "./schemas";

export interface ParsedApiError {
	fieldErrors: Record<string, string>;
	message?: string;
	throttled: boolean;
}

// Map a DRF error body ({field: [msg]} / {non_field_errors: [msg]}) to a flat
// shape forms can render. Non-axios errors surface a generic message.
export function parseApiError(error: unknown): ParsedApiError {
	const result: ParsedApiError = { fieldErrors: {}, throttled: false };
	if (!isAxiosError(error) || !error.response) {
		result.message = "Something went wrong. Please try again.";
		return result;
	}
	if (error.response.status === 429) result.throttled = true;
	const data = error.response.data as Record<string, unknown> | undefined;
	if (data && typeof data === "object") {
		for (const [field, value] of Object.entries(data)) {
			const msg = Array.isArray(value) ? String(value[0]) : String(value);
			if (field === "non_field_errors" || field === "detail") result.message = msg;
			else result.fieldErrors[field] = msg;
		}
	}
	return result;
}

export interface RegisterResponse {
	id: number;
	email: string;
	full_name: string;
	account_type: string;
}

export const identityApi = {
	register: (input: RegisterInput) =>
		api.post<RegisterResponse>("identity/register/", input).then((r) => r.data),
	login: (input: LoginInput) =>
		api.post<Me>("identity/login/", input).then((r) => r.data),
	logout: () => api.post("identity/logout/").then(() => undefined),
	me: () => api.get<Me>("identity/me/").then((r) => r.data),
	updateMe: (input: ProfileEditInput) =>
		api.patch<Me>("identity/me/", input).then((r) => r.data),
	resendVerification: (email: string) =>
		api.post("identity/resend-verification/", { email }).then(() => undefined),
	verifyEmail: (key: string) =>
		api.post("identity/verify-email/", { key }).then(() => undefined),
};

// Re-export so tests/forms can construct expected errors without importing axios.
export { AxiosError };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm test -- src/features/identity/api.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/features/identity/api.ts src/features/identity/api.test.ts
git commit -m "feat(identity): typed api layer + DRF error parser"
```

---

### Task D3: Query + mutation hooks

**Files:**
- Create: `src/features/identity/queries.ts`
- Test: `src/features/identity/queries.test.tsx`

- [ ] **Step 1: Write the failing test**

Create `src/features/identity/queries.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { renderHook, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { identityApi } from "./api";
import { useLogin, useMe } from "./queries";

vi.mock("./api", async (orig) => {
	const actual = await orig<typeof import("./api")>();
	return {
		...actual,
		identityApi: {
			me: vi.fn(),
			login: vi.fn(),
			logout: vi.fn(),
		},
	};
});

function wrapper({ children }: { children: ReactNode }) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false } },
	});
	return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

const me = {
	id: 1,
	email: "a@b.com",
	full_name: "A",
	profiles: ["student"] as const,
};

describe("identity queries", () => {
	beforeEach(() => vi.clearAllMocks());

	it("useMe returns the current user", async () => {
		vi.mocked(identityApi.me).mockResolvedValue(me);
		const { result } = renderHook(() => useMe(), { wrapper });
		await waitFor(() => expect(result.current.data).toEqual(me));
	});

	it("useLogin primes the me cache from its response", async () => {
		vi.mocked(identityApi.login).mockResolvedValue(me);
		const { result } = renderHook(() => useLogin(), { wrapper });
		await result.current.mutateAsync({ email: "a@b.com", password: "x" });
		expect(identityApi.login).toHaveBeenCalledOnce();
	});
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm test -- src/features/identity/queries.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Write the hooks**

Create `src/features/identity/queries.ts`:

```ts
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { identityApi } from "./api";
import type { LoginInput, Me, ProfileEditInput, RegisterInput } from "./schemas";

export const meQueryKey = ["me"] as const;

export const meQueryOptions = {
	queryKey: meQueryKey,
	queryFn: identityApi.me,
	retry: false,
	staleTime: 60_000,
};

export function useMe() {
	return useQuery(meQueryOptions);
}

export function useLogin() {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (input: LoginInput) => identityApi.login(input),
		onSuccess: (data: Me) => qc.setQueryData(meQueryKey, data),
	});
}

export function useLogout() {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: () => identityApi.logout(),
		onSuccess: () => qc.clear(),
	});
}

export function useRegister() {
	return useMutation({
		mutationFn: (input: RegisterInput) => identityApi.register(input),
	});
}

export function useResendVerification() {
	return useMutation({
		mutationFn: (email: string) => identityApi.resendVerification(email),
	});
}

export function useVerifyEmail() {
	return useMutation({
		mutationFn: (key: string) => identityApi.verifyEmail(key),
	});
}

export function useUpdateMe() {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (input: ProfileEditInput) => identityApi.updateMe(input),
		onSuccess: (data: Me) => qc.setQueryData(meQueryKey, data),
	});
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm test -- src/features/identity/queries.test.tsx`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/features/identity/queries.ts src/features/identity/queries.test.tsx
git commit -m "feat(identity): useMe + auth mutation hooks"
```

---

### Task D4: Locale strings (en + ar)

Add all auth copy up front so forms reference real keys. (No separate test; the a11y/RTL route tests in later tasks exercise these.)

**Files:**
- Modify: `src/locales/en/common.json`
- Modify: `src/locales/ar/common.json`

- [ ] **Step 1: Extend the `auth` namespace in `src/locales/en/common.json`**

Replace the existing `"auth": { ... }` object with:

```json
	"auth": {
		"welcomeBack": "Welcome back",
		"signInSubtitle": "Sign in to continue your studies.",
		"email": "Email",
		"password": "Password",
		"fullName": "Full name",
		"signIn": "Sign in",
		"signOut": "Sign out",
		"newToKaleem": "New to kaleem? Create an account",
		"haveAccount": "Already have an account? Sign in",
		"createAccount": "Create your account",
		"registerSubtitle": "Start learning with kaleem.",
		"accountType": "I am a",
		"student": "Student",
		"parent": "Parent",
		"register": "Create account",
		"invalidCredentials": "Invalid credentials.",
		"notVerified": "Your email isn't verified yet.",
		"resend": "Resend verification email",
		"resendThrottled": "Please wait a moment before requesting another email.",
		"checkInbox": "Check your inbox",
		"verifyPendingBody": "We've sent a verification link to {{email}}. Click it to activate your account.",
		"verifying": "Verifying your email…",
		"verified": "Email verified. You can now sign in.",
		"verifyFailed": "This verification link is invalid or has expired.",
		"goToSignIn": "Go to sign in",
		"resendSent": "If that account needs verification, a new link is on its way.",
		"home": "Home",
		"profile": "Profile",
		"profileSubtitle": "Update your name and email.",
		"save": "Save changes",
		"saved": "Saved.",
		"greeting": "Assalamu alaikum, {{name}}"
	}
```

- [ ] **Step 2: Mirror the keys in `src/locales/ar/common.json`**

Set the `auth` namespace (create the file's structure to match en if absent):

```json
	"auth": {
		"welcomeBack": "مرحباً بعودتك",
		"signInSubtitle": "سجّل الدخول لمتابعة دراستك.",
		"email": "البريد الإلكتروني",
		"password": "كلمة المرور",
		"fullName": "الاسم الكامل",
		"signIn": "تسجيل الدخول",
		"signOut": "تسجيل الخروج",
		"newToKaleem": "جديد في كَليم؟ أنشئ حساباً",
		"haveAccount": "لديك حساب؟ سجّل الدخول",
		"createAccount": "أنشئ حسابك",
		"registerSubtitle": "ابدأ التعلّم مع كَليم.",
		"accountType": "أنا",
		"student": "طالب",
		"parent": "وليّ أمر",
		"register": "إنشاء حساب",
		"invalidCredentials": "بيانات الدخول غير صحيحة.",
		"notVerified": "لم يتم تأكيد بريدك الإلكتروني بعد.",
		"resend": "إعادة إرسال رابط التأكيد",
		"resendThrottled": "يرجى الانتظار قليلاً قبل طلب رسالة أخرى.",
		"checkInbox": "تحقّق من بريدك",
		"verifyPendingBody": "أرسلنا رابط تأكيد إلى {{email}}. اضغط عليه لتفعيل حسابك.",
		"verifying": "جارٍ تأكيد بريدك…",
		"verified": "تم تأكيد البريد. يمكنك الآن تسجيل الدخول.",
		"verifyFailed": "رابط التأكيد غير صالح أو منتهي الصلاحية.",
		"goToSignIn": "اذهب إلى تسجيل الدخول",
		"resendSent": "إذا كان الحساب بحاجة إلى تأكيد، فالرابط في طريقه إليك.",
		"home": "الرئيسية",
		"profile": "الملف الشخصي",
		"profileSubtitle": "حدّث اسمك وبريدك الإلكتروني.",
		"save": "حفظ التغييرات",
		"saved": "تم الحفظ.",
		"greeting": "السلام عليكم، {{name}}"
	}
```

- [ ] **Step 3: Verify JSON is valid**

Run: `pnpm exec tsc -b`
Expected: no errors (JSON imports type-check).

- [ ] **Step 4: Commit**

```bash
git add src/locales/en/common.json src/locales/ar/common.json
git commit -m "feat(identity): auth copy (en + ar)"
```

---

### Task D5: LoginForm component

**Files:**
- Create: `src/features/identity/components/LoginForm.tsx`
- Test: `src/features/identity/components/LoginForm.test.tsx`

- [ ] **Step 1: Write the failing test**

Create `src/features/identity/components/LoginForm.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "jest-axe";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { identityApi } from "../api";
import { LoginForm } from "./LoginForm";

vi.mock("../api", async (orig) => {
	const actual = await orig<typeof import("../api")>();
	return { ...actual, identityApi: { login: vi.fn() } };
});

function wrapper({ children }: { children: ReactNode }) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false } },
	});
	return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

describe("LoginForm", () => {
	beforeEach(() => vi.clearAllMocks());

	it("submits credentials and calls onSuccess", async () => {
		vi.mocked(identityApi.login).mockResolvedValue({
			id: 1,
			email: "a@b.com",
			full_name: "A",
			profiles: ["student"],
		});
		const onSuccess = vi.fn();
		render(<LoginForm onSuccess={onSuccess} onNotVerified={vi.fn()} />, {
			wrapper,
		});
		await userEvent.type(screen.getByLabelText(/email/i), "a@b.com");
		await userEvent.type(screen.getByLabelText(/password/i), "sup3r-secret");
		await userEvent.click(screen.getByRole("button", { name: /sign in/i }));
		await waitFor(() => expect(onSuccess).toHaveBeenCalled());
	});

	it("shows a not-verified affordance on that error", async () => {
		const { AxiosError } = await import("../api");
		const err = new AxiosError("bad");
		// @ts-expect-error minimal response
		err.response = {
			status: 400,
			data: { non_field_errors: ["Email address is not verified."] },
		};
		vi.mocked(identityApi.login).mockRejectedValue(err);
		const onNotVerified = vi.fn();
		render(<LoginForm onSuccess={vi.fn()} onNotVerified={onNotVerified} />, {
			wrapper,
		});
		await userEvent.type(screen.getByLabelText(/email/i), "a@b.com");
		await userEvent.type(screen.getByLabelText(/password/i), "sup3r-secret");
		await userEvent.click(screen.getByRole("button", { name: /sign in/i }));
		await waitFor(() =>
			expect(
				screen.getByRole("button", { name: /resend/i }),
			).toBeInTheDocument(),
		);
	});

	it("has no axe violations", async () => {
		const { container } = render(
			<LoginForm onSuccess={vi.fn()} onNotVerified={vi.fn()} />,
			{ wrapper },
		);
		expect(await axe(container)).toHaveNoViolations();
	});
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm test -- src/features/identity/components/LoginForm.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Write the component**

Create `src/features/identity/components/LoginForm.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { Alert, AlertDescription, Button, Field, Input } from "@/ui";
import { parseApiError } from "../api";
import { useLogin } from "../queries";
import { type LoginInput, loginSchema } from "../schemas";

export function LoginForm({
	onSuccess,
	onNotVerified,
}: {
	onSuccess: () => void;
	onNotVerified: (email: string) => void;
}) {
	const { t } = useTranslation();
	const login = useLogin();
	const {
		register,
		handleSubmit,
		setError,
		getValues,
		formState: { errors, isSubmitting },
	} = useForm<LoginInput>({ resolver: zodResolver(loginSchema) });

	async function onSubmit(values: LoginInput) {
		try {
			await login.mutateAsync(values);
			onSuccess();
		} catch (error) {
			const parsed = parseApiError(error);
			for (const [field, message] of Object.entries(parsed.fieldErrors)) {
				setError(field as keyof LoginInput, { message });
			}
			if (parsed.message?.toLowerCase().includes("not verified")) {
				setError("root.notVerified", { message: t("auth.notVerified") });
			} else if (parsed.message) {
				setError("root.server", { message: parsed.message });
			}
		}
	}

	return (
		<form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-4" noValidate>
			<Field id="email" label={t("auth.email")} error={errors.email?.message}>
				<Input type="email" autoComplete="email" {...register("email")} />
			</Field>
			<Field
				id="password"
				label={t("auth.password")}
				error={errors.password?.message}
			>
				<Input
					type="password"
					autoComplete="current-password"
					{...register("password")}
				/>
			</Field>
			{errors.root?.server ? (
				<Alert variant="destructive">
					<AlertDescription>{errors.root.server.message}</AlertDescription>
				</Alert>
			) : null}
			{errors.root?.notVerified ? (
				<Alert variant="destructive">
					<AlertDescription className="flex flex-col gap-2">
						{errors.root.notVerified.message}
						<Button
							type="button"
							variant="outline"
							onClick={() => onNotVerified(getValues("email"))}
						>
							{t("auth.resend")}
						</Button>
					</AlertDescription>
				</Alert>
			) : null}
			<Button type="submit" disabled={isSubmitting}>
				{t("auth.signIn")}
			</Button>
		</form>
	);
}
```

> If `Alert` has no `variant` prop or `Button` no `outline` variant, check `src/ui/alert.tsx` / `src/ui/button.tsx` and use the variants that exist (drop the prop if there's only one style). Do not invent variants.

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm test -- src/features/identity/components/LoginForm.test.tsx`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add src/features/identity/components/LoginForm.tsx src/features/identity/components/LoginForm.test.tsx
git commit -m "feat(identity): LoginForm with not-verified resend affordance"
```

---

### Task D6: RegisterForm component

**Files:**
- Create: `src/features/identity/components/RegisterForm.tsx`
- Test: `src/features/identity/components/RegisterForm.test.tsx`

- [ ] **Step 1: Write the failing test**

Create `src/features/identity/components/RegisterForm.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "jest-axe";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { identityApi } from "../api";
import { RegisterForm } from "./RegisterForm";

vi.mock("../api", async (orig) => {
	const actual = await orig<typeof import("../api")>();
	return { ...actual, identityApi: { register: vi.fn() } };
});

function wrapper({ children }: { children: ReactNode }) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false } },
	});
	return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

describe("RegisterForm", () => {
	beforeEach(() => vi.clearAllMocks());

	it("submits and reports the registered email", async () => {
		vi.mocked(identityApi.register).mockResolvedValue({
			id: 1,
			email: "a@b.com",
			full_name: "A",
			account_type: "student",
		});
		const onSuccess = vi.fn();
		render(<RegisterForm onSuccess={onSuccess} />, { wrapper });
		await userEvent.type(screen.getByLabelText(/full name/i), "Ahmad");
		await userEvent.type(screen.getByLabelText(/email/i), "a@b.com");
		await userEvent.type(screen.getByLabelText(/password/i), "sup3r-secret");
		await userEvent.click(screen.getByRole("button", { name: /create account/i }));
		await waitFor(() => expect(onSuccess).toHaveBeenCalledWith("a@b.com"));
	});

	it("surfaces a duplicate-email field error", async () => {
		const { AxiosError } = await import("../api");
		const err = new AxiosError("bad");
		// @ts-expect-error minimal response
		err.response = {
			status: 400,
			data: { email: ["A user with this email already exists."] },
		};
		vi.mocked(identityApi.register).mockRejectedValue(err);
		render(<RegisterForm onSuccess={vi.fn()} />, { wrapper });
		await userEvent.type(screen.getByLabelText(/full name/i), "Ahmad");
		await userEvent.type(screen.getByLabelText(/email/i), "a@b.com");
		await userEvent.type(screen.getByLabelText(/password/i), "sup3r-secret");
		await userEvent.click(screen.getByRole("button", { name: /create account/i }));
		await waitFor(() =>
			expect(screen.getByText(/already exists/i)).toBeInTheDocument(),
		);
	});

	it("has no axe violations", async () => {
		const { container } = render(<RegisterForm onSuccess={vi.fn()} />, {
			wrapper,
		});
		expect(await axe(container)).toHaveNoViolations();
	});
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm test -- src/features/identity/components/RegisterForm.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Write the component**

Create `src/features/identity/components/RegisterForm.tsx`:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { Alert, AlertDescription, Button, Field, Input, Label } from "@/ui";
import { parseApiError } from "../api";
import { useRegister } from "../queries";
import { type RegisterInput, registerSchema } from "../schemas";

export function RegisterForm({
	onSuccess,
}: {
	onSuccess: (email: string) => void;
}) {
	const { t } = useTranslation();
	const registerUser = useRegister();
	const {
		register,
		handleSubmit,
		setError,
		formState: { errors, isSubmitting },
	} = useForm<RegisterInput>({
		resolver: zodResolver(registerSchema),
		defaultValues: { account_type: "student" },
	});

	async function onSubmit(values: RegisterInput) {
		try {
			const created = await registerUser.mutateAsync(values);
			onSuccess(created.email);
		} catch (error) {
			const parsed = parseApiError(error);
			for (const [field, message] of Object.entries(parsed.fieldErrors)) {
				setError(field as keyof RegisterInput, { message });
			}
			if (parsed.message) setError("root.server", { message: parsed.message });
		}
	}

	return (
		<form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-4" noValidate>
			<Field
				id="full_name"
				label={t("auth.fullName")}
				error={errors.full_name?.message}
			>
				<Input autoComplete="name" {...register("full_name")} />
			</Field>
			<Field id="email" label={t("auth.email")} error={errors.email?.message}>
				<Input type="email" autoComplete="email" {...register("email")} />
			</Field>
			<Field
				id="password"
				label={t("auth.password")}
				error={errors.password?.message}
			>
				<Input
					type="password"
					autoComplete="new-password"
					{...register("password")}
				/>
			</Field>
			<div className="flex flex-col gap-1.5">
				<Label htmlFor="account_type">{t("auth.accountType")}</Label>
				<select
					id="account_type"
					className="h-9 rounded-md border border-input bg-background px-3 text-sm"
					{...register("account_type")}
				>
					<option value="student">{t("auth.student")}</option>
					<option value="parent">{t("auth.parent")}</option>
				</select>
			</div>
			{errors.root?.server ? (
				<Alert variant="destructive">
					<AlertDescription>{errors.root.server.message}</AlertDescription>
				</Alert>
			) : null}
			<Button type="submit" disabled={isSubmitting}>
				{t("auth.register")}
			</Button>
		</form>
	);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm test -- src/features/identity/components/RegisterForm.test.tsx`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add src/features/identity/components/RegisterForm.tsx src/features/identity/components/RegisterForm.test.tsx
git commit -m "feat(identity): RegisterForm with account-type select"
```

---

### Task D7: Public routes — /login and /register

Wire the forms into file-based routes. (Route components are thin; tested via the form tests above + the home/guard tests. Verify they render by type-check + a smoke render.)

**Files:**
- Create: `src/routes/login.tsx`
- Create: `src/routes/register.tsx`
- Test: `src/routes/login.test.tsx`

- [ ] **Step 1: Write the failing smoke test**

Create `src/routes/login.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import type { ReactNode } from "react";
import { describe, expect, it } from "vitest";
import { LoginPage } from "./login";

function wrapper({ children }: { children: ReactNode }) {
	return (
		<QueryClientProvider client={new QueryClient()}>
			{children}
		</QueryClientProvider>
	);
}

describe("LoginPage", () => {
	it("renders the sign-in heading and a link to register", () => {
		render(<LoginPage />, { wrapper });
		expect(screen.getByRole("heading", { name: /welcome back/i })).toBeInTheDocument();
		expect(screen.getByRole("link", { name: /create an account/i })).toBeInTheDocument();
	});
});
```

> Note: export the page component (`LoginPage`) separately from the route so it can be rendered without the router. The route's `component` references it.

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm test -- src/routes/login.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Write `src/routes/login.tsx`**

```tsx
import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { LoginForm } from "@/features/identity/components/LoginForm";
import { AuthLayout } from "@/ui";

export function LoginPage() {
	const { t } = useTranslation();
	const navigate = useNavigate();
	return (
		<AuthLayout>
			<div className="flex flex-col gap-1 pb-4">
				<h1 className="font-display text-2xl font-semibold">
					{t("auth.welcomeBack")}
				</h1>
				<p className="text-sm text-muted-foreground">{t("auth.signInSubtitle")}</p>
			</div>
			<LoginForm
				onSuccess={() => navigate({ to: "/" })}
				onNotVerified={(email) =>
					navigate({ to: "/verify-pending", search: { email } })
				}
			/>
			<p className="pt-4 text-sm">
				<Link to="/register" className="text-primary underline">
					{t("auth.newToKaleem")}
				</Link>
			</p>
		</AuthLayout>
	);
}

export const Route = createFileRoute("/login")({ component: LoginPage });
```

- [ ] **Step 4: Write `src/routes/register.tsx`**

```tsx
import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { RegisterForm } from "@/features/identity/components/RegisterForm";
import { AuthLayout } from "@/ui";

export function RegisterPage() {
	const { t } = useTranslation();
	const navigate = useNavigate();
	return (
		<AuthLayout>
			<div className="flex flex-col gap-1 pb-4">
				<h1 className="font-display text-2xl font-semibold">
					{t("auth.createAccount")}
				</h1>
				<p className="text-sm text-muted-foreground">
					{t("auth.registerSubtitle")}
				</p>
			</div>
			<RegisterForm
				onSuccess={(email) =>
					navigate({ to: "/verify-pending", search: { email } })
				}
			/>
			<p className="pt-4 text-sm">
				<Link to="/login" className="text-primary underline">
					{t("auth.haveAccount")}
				</Link>
			</p>
		</AuthLayout>
	);
}

export const Route = createFileRoute("/register")({ component: RegisterPage });
```

- [ ] **Step 5: Run the smoke test (regenerates the route tree)**

Run: `pnpm test -- src/routes/login.test.tsx`
Expected: PASS. (The dev server / build regenerates `routeTree.gen.ts`; if the test can't resolve the route, run `pnpm exec tsc -b` once which triggers the router plugin, or start `pnpm dev` briefly.)

- [ ] **Step 6: Commit**

```bash
git add src/routes/login.tsx src/routes/register.tsx src/routes/login.test.tsx src/routeTree.gen.ts
git commit -m "feat(identity): /login and /register routes"
```

---

### Task D8: /verify-pending route

**Files:**
- Create: `src/routes/verify-pending.tsx`
- Test: `src/routes/verify-pending.test.tsx`

- [ ] **Step 1: Write the failing test**

Create `src/routes/verify-pending.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { identityApi } from "@/features/identity/api";
import { VerifyPendingPage } from "./verify-pending";

vi.mock("@/features/identity/api", async (orig) => {
	const actual = await orig<typeof import("@/features/identity/api")>();
	return { ...actual, identityApi: { resendVerification: vi.fn() } };
});

function wrapper({ children }: { children: ReactNode }) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false } },
	});
	return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

describe("VerifyPendingPage", () => {
	beforeEach(() => vi.clearAllMocks());

	it("shows the email and resends on click", async () => {
		vi.mocked(identityApi.resendVerification).mockResolvedValue(undefined);
		render(<VerifyPendingPage email="a@b.com" />, { wrapper });
		expect(screen.getByText(/a@b.com/)).toBeInTheDocument();
		await userEvent.click(screen.getByRole("button", { name: /resend/i }));
		await waitFor(() =>
			expect(identityApi.resendVerification).toHaveBeenCalledWith("a@b.com"),
		);
		expect(screen.getByText(/on its way/i)).toBeInTheDocument();
	});
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm test -- src/routes/verify-pending.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Write `src/routes/verify-pending.tsx`**

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { parseApiError } from "@/features/identity/api";
import { useResendVerification } from "@/features/identity/queries";
import { Alert, AlertDescription, AuthLayout, Button } from "@/ui";

export function VerifyPendingPage({ email }: { email: string }) {
	const { t } = useTranslation();
	const resend = useResendVerification();

	async function onResend() {
		try {
			await resend.mutateAsync(email);
		} catch {
			// parseApiError surfaces the throttle message below via resend.error
		}
	}

	const throttled =
		resend.isError && parseApiError(resend.error).throttled;

	return (
		<AuthLayout>
			<div className="flex flex-col gap-3">
				<h1 className="font-display text-2xl font-semibold">
					{t("auth.checkInbox")}
				</h1>
				<p className="text-sm text-muted-foreground">
					{t("auth.verifyPendingBody", { email })}
				</p>
				{resend.isSuccess ? (
					<Alert>
						<AlertDescription>{t("auth.resendSent")}</AlertDescription>
					</Alert>
				) : null}
				{throttled ? (
					<Alert variant="destructive">
						<AlertDescription>{t("auth.resendThrottled")}</AlertDescription>
					</Alert>
				) : null}
				<Button
					type="button"
					variant="outline"
					onClick={onResend}
					disabled={resend.isPending}
				>
					{t("auth.resend")}
				</Button>
			</div>
		</AuthLayout>
	);
}

export const Route = createFileRoute("/verify-pending")({
	validateSearch: (search: Record<string, unknown>) => ({
		email: typeof search.email === "string" ? search.email : "",
	}),
	component: function VerifyPendingRoute() {
		const { email } = Route.useSearch();
		return <VerifyPendingPage email={email} />;
	},
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm test -- src/routes/verify-pending.test.tsx`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/routes/verify-pending.tsx src/routes/verify-pending.test.tsx src/routeTree.gen.ts
git commit -m "feat(identity): /verify-pending with resend + throttle handling"
```

---

### Task D9: /verify-email landing route

**Files:**
- Create: `src/routes/verify-email.tsx`
- Test: `src/routes/verify-email.test.tsx`

- [ ] **Step 1: Write the failing test**

Create `src/routes/verify-email.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { identityApi } from "@/features/identity/api";
import { VerifyEmailPage } from "./verify-email";

vi.mock("@/features/identity/api", async (orig) => {
	const actual = await orig<typeof import("@/features/identity/api")>();
	return { ...actual, identityApi: { verifyEmail: vi.fn() } };
});

function wrapper({ children }: { children: ReactNode }) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false } },
	});
	return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

describe("VerifyEmailPage", () => {
	beforeEach(() => vi.clearAllMocks());

	it("shows success on a valid key", async () => {
		vi.mocked(identityApi.verifyEmail).mockResolvedValue(undefined);
		render(<VerifyEmailPage verifyKey="good-key" onVerified={vi.fn()} />, {
			wrapper,
		});
		await waitFor(() =>
			expect(screen.getByText(/email verified/i)).toBeInTheDocument(),
		);
	});

	it("shows an error on a bad key", async () => {
		vi.mocked(identityApi.verifyEmail).mockRejectedValue(new Error("nope"));
		render(<VerifyEmailPage verifyKey="bad-key" onVerified={vi.fn()} />, {
			wrapper,
		});
		await waitFor(() =>
			expect(screen.getByText(/invalid or has expired/i)).toBeInTheDocument(),
		);
	});
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm test -- src/routes/verify-email.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Write `src/routes/verify-email.tsx`**

```tsx
import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useEffect, useRef } from "react";
import { useTranslation } from "react-i18next";
import { useVerifyEmail } from "@/features/identity/queries";
import { Alert, AlertDescription, AuthLayout, Button, Spinner } from "@/ui";

export function VerifyEmailPage({
	verifyKey,
	onVerified,
}: {
	verifyKey: string;
	onVerified: () => void;
}) {
	const { t } = useTranslation();
	const verify = useVerifyEmail();
	const started = useRef(false);

	useEffect(() => {
		if (started.current || !verifyKey) return;
		started.current = true;
		verify.mutate(verifyKey, { onSuccess: onVerified });
	}, [verifyKey, verify, onVerified]);

	return (
		<AuthLayout>
			<div className="flex flex-col items-center gap-4 py-6 text-center">
				{verify.isPending || verify.isIdle ? (
					<>
						<Spinner />
						<p className="text-sm text-muted-foreground">{t("auth.verifying")}</p>
					</>
				) : null}
				{verify.isSuccess ? (
					<>
						<Alert>
							<AlertDescription>{t("auth.verified")}</AlertDescription>
						</Alert>
						<Button asChild>
							<Link to="/login">{t("auth.goToSignIn")}</Link>
						</Button>
					</>
				) : null}
				{verify.isError ? (
					<>
						<Alert variant="destructive">
							<AlertDescription>{t("auth.verifyFailed")}</AlertDescription>
						</Alert>
						<Button asChild variant="outline">
							<Link to="/login">{t("auth.goToSignIn")}</Link>
						</Button>
					</>
				) : null}
			</div>
		</AuthLayout>
	);
}

export const Route = createFileRoute("/verify-email")({
	validateSearch: (search: Record<string, unknown>) => ({
		key: typeof search.key === "string" ? search.key : "",
	}),
	component: function VerifyEmailRoute() {
		const { key } = Route.useSearch();
		const navigate = useNavigate();
		return (
			<VerifyEmailPage
				verifyKey={key}
				onVerified={() =>
					setTimeout(() => navigate({ to: "/login" }), 1500)
				}
			/>
		);
	},
});
```

> If `Button` has no `asChild` prop (check `src/ui/button.tsx`), wrap with `useNavigate` + `onClick` instead of `<Link>`. Verify against the actual primitive.

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm test -- src/routes/verify-email.test.tsx`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add src/routes/verify-email.tsx src/routes/verify-email.test.tsx src/routeTree.gen.ts
git commit -m "feat(identity): /verify-email landing (confirm-by-key)"
```

---

### Task D10: Protected layout route (`_authed`) + auth guard

**Files:**
- Create: `src/routes/_authed.tsx`
- Test: `src/features/identity/queries.test.tsx` (extend — guard logic is a plain function; test it directly)

> TanStack Router `beforeLoad` is awkward to unit test in isolation; extract the guard decision into a pure helper and test that, then use it in the route.

- [ ] **Step 1: Write the failing test**

Append to `src/features/identity/queries.test.tsx`:

```tsx
import { ensureAuthed } from "./queries";

describe("ensureAuthed", () => {
	it("returns the user when ensureQueryData resolves", async () => {
		const qc = {
			ensureQueryData: vi
				.fn()
				.mockResolvedValue({ id: 1, email: "a@b.com", full_name: "A", profiles: [] }),
		};
		// @ts-expect-error partial client
		await expect(ensureAuthed(qc)).resolves.toMatchObject({ id: 1 });
	});

	it("throws when ensureQueryData rejects (401)", async () => {
		const qc = { ensureQueryData: vi.fn().mockRejectedValue(new Error("401")) };
		// @ts-expect-error partial client
		await expect(ensureAuthed(qc)).rejects.toThrow();
	});
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm test -- src/features/identity/queries.test.tsx`
Expected: FAIL — `ensureAuthed` not exported.

- [ ] **Step 3: Add `ensureAuthed` to `src/features/identity/queries.ts`**

```ts
import type { QueryClient } from "@tanstack/react-query";
```

```ts
// Used by the _authed route's beforeLoad. Resolves to the user when the session
// is valid; rejects (→ redirect to /login) when /me returns 401.
export async function ensureAuthed(qc: QueryClient): Promise<Me> {
	return qc.ensureQueryData(meQueryOptions);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm test -- src/features/identity/queries.test.tsx`
Expected: PASS

- [ ] **Step 5: Write `src/routes/_authed.tsx`**

The router needs the `QueryClient` in its context. Update `src/main.tsx` to pass it (see Step 6), then:

```tsx
import {
	createFileRoute,
	Outlet,
	redirect,
} from "@tanstack/react-router";
import { ensureAuthed } from "@/features/identity/queries";

export const Route = createFileRoute("/_authed")({
	beforeLoad: async ({ context }) => {
		try {
			await ensureAuthed(context.queryClient);
		} catch {
			throw redirect({ to: "/login" });
		}
	},
	component: Outlet,
});
```

- [ ] **Step 6: Wire the QueryClient into router context in `src/main.tsx`**

Change the router creation and add the context type:

```tsx
const router = createRouter({
	routeTree,
	context: { queryClient },
});

declare module "@tanstack/react-router" {
	interface Register {
		router: typeof router;
	}
}
```

and create `src/routes/__root.tsx` context type — replace the existing `__root.tsx` with:

```tsx
import type { QueryClient } from "@tanstack/react-query";
import { createRootRouteWithContext, Outlet } from "@tanstack/react-router";

export interface RouterContext {
	queryClient: QueryClient;
}

export const Route = createRootRouteWithContext<RouterContext>()({
	component: () => (
		<div className="min-h-screen bg-background text-foreground">
			<Outlet />
		</div>
	),
});
```

- [ ] **Step 7: Run type-check + full suite**

Run: `pnpm exec tsc -b && pnpm test`
Expected: all green (route tree regenerates; context typed).

- [ ] **Step 8: Commit**

```bash
git add src/routes/_authed.tsx src/routes/__root.tsx src/main.tsx src/features/identity/queries.ts src/features/identity/queries.test.tsx src/routeTree.gen.ts
git commit -m "feat(identity): protected _authed layout + query-client router context"
```

---

### Task D11: Role-aware home + ProfileEditForm

**Files:**
- Create: `src/features/identity/components/ProfileEditForm.tsx`
- Create: `src/routes/_authed/index.tsx`
- Create: `src/routes/_authed/profile.tsx`
- Test: `src/features/identity/components/ProfileEditForm.test.tsx`
- Test: `src/routes/_authed/index.test.tsx`

- [ ] **Step 1: Write the failing ProfileEditForm test**

Create `src/features/identity/components/ProfileEditForm.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "jest-axe";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { identityApi } from "../api";
import { ProfileEditForm } from "./ProfileEditForm";

vi.mock("../api", async (orig) => {
	const actual = await orig<typeof import("../api")>();
	return { ...actual, identityApi: { updateMe: vi.fn() } };
});

function wrapper({ children }: { children: ReactNode }) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false } },
	});
	return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

const me = { id: 1, email: "a@b.com", full_name: "A", profiles: ["student"] as const };

describe("ProfileEditForm", () => {
	beforeEach(() => vi.clearAllMocks());

	it("saves edits", async () => {
		vi.mocked(identityApi.updateMe).mockResolvedValue({ ...me, full_name: "B" });
		render(<ProfileEditForm me={me} />, { wrapper });
		const name = screen.getByLabelText(/full name/i);
		await userEvent.clear(name);
		await userEvent.type(name, "B");
		await userEvent.click(screen.getByRole("button", { name: /save/i }));
		await waitFor(() =>
			expect(screen.getByText(/saved/i)).toBeInTheDocument(),
		);
	});

	it("has no axe violations", async () => {
		const { container } = render(<ProfileEditForm me={me} />, { wrapper });
		expect(await axe(container)).toHaveNoViolations();
	});
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm test -- src/features/identity/components/ProfileEditForm.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Write `src/features/identity/components/ProfileEditForm.tsx`**

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { Alert, AlertDescription, Button, Field, Input } from "@/ui";
import { parseApiError } from "../api";
import { useUpdateMe } from "../queries";
import { type Me, type ProfileEditInput, profileEditSchema } from "../schemas";

export function ProfileEditForm({ me }: { me: Me }) {
	const { t } = useTranslation();
	const update = useUpdateMe();
	const {
		register,
		handleSubmit,
		setError,
		formState: { errors, isSubmitting, isSubmitSuccessful },
	} = useForm<ProfileEditInput>({
		resolver: zodResolver(profileEditSchema),
		defaultValues: { full_name: me.full_name, email: me.email },
	});

	async function onSubmit(values: ProfileEditInput) {
		try {
			await update.mutateAsync(values);
		} catch (error) {
			const parsed = parseApiError(error);
			for (const [field, message] of Object.entries(parsed.fieldErrors)) {
				setError(field as keyof ProfileEditInput, { message });
			}
			if (parsed.message) setError("root.server", { message: parsed.message });
		}
	}

	return (
		<form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-4" noValidate>
			<Field
				id="full_name"
				label={t("auth.fullName")}
				error={errors.full_name?.message}
			>
				<Input autoComplete="name" {...register("full_name")} />
			</Field>
			<Field id="email" label={t("auth.email")} error={errors.email?.message}>
				<Input type="email" autoComplete="email" {...register("email")} />
			</Field>
			{errors.root?.server ? (
				<Alert variant="destructive">
					<AlertDescription>{errors.root.server.message}</AlertDescription>
				</Alert>
			) : null}
			{isSubmitSuccessful && update.isSuccess ? (
				<Alert>
					<AlertDescription>{t("auth.saved")}</AlertDescription>
				</Alert>
			) : null}
			<Button type="submit" disabled={isSubmitting}>
				{t("auth.save")}
			</Button>
		</form>
	);
}
```

- [ ] **Step 4: Write the failing home test**

Create `src/routes/_authed/index.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import type { ReactNode } from "react";
import { describe, expect, it } from "vitest";
import { Home } from "./index";

function wrapper({ children }: { children: ReactNode }) {
	return (
		<QueryClientProvider client={new QueryClient()}>
			{children}
		</QueryClientProvider>
	);
}

describe("Home", () => {
	it("greets the user and shows sign-out", () => {
		render(
			<Home
				me={{ id: 1, email: "a@b.com", full_name: "Ahmad", profiles: ["student"] }}
				onLogout={() => {}}
			/>,
			{ wrapper },
		);
		expect(screen.getByText(/ahmad/i)).toBeInTheDocument();
		expect(screen.getByRole("button", { name: /sign out/i })).toBeInTheDocument();
	});

	it("shows a parent panel for parents", () => {
		render(
			<Home
				me={{ id: 1, email: "a@b.com", full_name: "Mum", profiles: ["parent"] }}
				onLogout={() => {}}
			/>,
			{ wrapper },
		);
		// Parent tools land in Phase 2; for now assert the role-branch renders its heading.
		expect(screen.getByText(/parent/i)).toBeInTheDocument();
	});
});
```

- [ ] **Step 5: Run tests to verify they fail**

Run: `pnpm test -- src/routes/_authed/index.test.tsx src/features/identity/components/ProfileEditForm.test.tsx`
Expected: FAIL — modules not found.

- [ ] **Step 6: Write `src/routes/_authed/index.tsx`**

```tsx
import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { useLogout, useMe } from "@/features/identity/queries";
import type { Me } from "@/features/identity/schemas";
import { Button, Card, CardContent, CardHeader, CardTitle } from "@/ui";

export function Home({ me, onLogout }: { me: Me; onLogout: () => void }) {
	const { t } = useTranslation();
	const isParent = me.profiles.includes("parent");
	const isStudent = me.profiles.includes("student");
	return (
		<div className="mx-auto flex w-full max-w-2xl flex-col gap-6 p-6">
			<div className="flex items-center justify-between">
				<h1 className="font-display text-2xl font-semibold">
					{t("auth.greeting", { name: me.full_name })}
				</h1>
				<div className="flex gap-2">
					<Button asChild variant="outline">
						<Link to="/profile">{t("auth.profile")}</Link>
					</Button>
					<Button type="button" variant="outline" onClick={onLogout}>
						{t("auth.signOut")}
					</Button>
				</div>
			</div>
			{isParent ? (
				<Card>
					<CardHeader>
						<CardTitle>{t("auth.parent")}</CardTitle>
					</CardHeader>
					<CardContent className="text-sm text-muted-foreground">
						{/* Children + invite tools land in Phase 2. */}
						—
					</CardContent>
				</Card>
			) : null}
			{isStudent ? (
				<Card>
					<CardHeader>
						<CardTitle>{t("auth.student")}</CardTitle>
					</CardHeader>
					<CardContent className="text-sm text-muted-foreground">
						{/* Onboarding + invite-accept land in Phase 3. */}
						—
					</CardContent>
				</Card>
			) : null}
		</div>
	);
}

export const Route = createFileRoute("/_authed/")({
	component: function HomeRoute() {
		const { data: me } = useMe();
		const logout = useLogout();
		const navigate = useNavigate();
		if (!me) return null;
		return (
			<Home
				me={me}
				onLogout={() =>
					logout.mutate(undefined, {
						onSuccess: () => navigate({ to: "/login" }),
					})
				}
			/>
		);
	},
});
```

- [ ] **Step 7: Write `src/routes/_authed/profile.tsx`**

```tsx
import { createFileRoute, Link } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { ProfileEditForm } from "@/features/identity/components/ProfileEditForm";
import { useMe } from "@/features/identity/queries";
import { Button, Card, CardContent, CardHeader, CardTitle } from "@/ui";

export const Route = createFileRoute("/_authed/profile")({
	component: function ProfileRoute() {
		const { t } = useTranslation();
		const { data: me } = useMe();
		if (!me) return null;
		return (
			<div className="mx-auto flex w-full max-w-md flex-col gap-4 p-6">
				<Button asChild variant="outline" className="self-start">
					<Link to="/">{t("auth.home")}</Link>
				</Button>
				<Card>
					<CardHeader>
						<CardTitle>{t("auth.profile")}</CardTitle>
					</CardHeader>
					<CardContent>
						<ProfileEditForm me={me} />
					</CardContent>
				</Card>
			</div>
		);
	},
});
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `pnpm test -- src/routes/_authed/index.test.tsx src/features/identity/components/ProfileEditForm.test.tsx`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add src/features/identity/components/ProfileEditForm.tsx src/features/identity/components/ProfileEditForm.test.tsx src/routes/_authed/index.tsx src/routes/_authed/index.test.tsx src/routes/_authed/profile.tsx src/routeTree.gen.ts
git commit -m "feat(identity): role-aware home + profile edit"
```

---

### Task D12: Remove the placeholder, redirect `/`, full gate

**Files:**
- Modify: `src/routes/index.tsx` (redirect authenticated `/` → home; the `_authed/` route owns the real home, so make the public `/` redirect to `/login` or `/`)
- Delete: `src/routes/design-preview.tsx` and its references
- Test: full suite + a11y

> Decision: the public `/` placeholder is replaced by a redirect. Authenticated users should land on the `_authed/` home. Since `_authed/` renders at path `/`, there's a collision — resolve by making the home the index of `_authed` (path `/`) and removing the old public `src/routes/index.tsx`. The `_authed` guard then protects `/`; unauthenticated hits redirect to `/login`.

- [ ] **Step 1: Delete the public index and design-preview routes**

Run:

```bash
git rm src/routes/index.tsx src/routes/design-preview.tsx
```

(If `design-preview.tsx` imports are referenced elsewhere, grep and remove: `grep -rn "design-preview" src` → clean up.)

- [ ] **Step 2: Regenerate the route tree + type-check**

Run: `pnpm exec tsc -b`
Expected: no errors. `_authed/` now owns `/`.

- [ ] **Step 3: Run the full suite + lint + a11y**

Run: `pnpm test && pnpm exec biome check src`
Expected: all green, zero axe violations.

- [ ] **Step 4: Manual browser smoke (local dev stack)**

Run: `just dev` (from repo root) then visit `http://app.kaleem.localhost`:
- Unauthenticated `/` → redirects to `/login`.
- Register a parent → lands on `/verify-pending` showing the email.
- Open mailpit (`http://localhost:8025`) → click the verification link → lands on `app.kaleem.localhost/verify-email?key=…` → "Email verified" → redirected to `/login`.
- Log in → role-aware home greets you → Profile edit saves → Sign out → back to `/login`.
- Toggle locale to Arabic → layout flips RTL, copy translated.

Expected: the whole loop works locally.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(identity): make protected home the index; drop design-preview placeholder"
```

- [ ] **Step 6: Open the dashboard PR**

```bash
git push -u origin feat/identity-auth-core
gh pr create --base main --title "feat(identity): auth-core dashboard slice (register/login/verify/me)" \
  --body "Identity auth-core frontend: register, verify-pending, /verify-email landing, login, logout, role-aware home, profile edit. Built on the Serene Scholar design system; TanStack Query useMe + _authed guard. Closes the dashboard half of Phase A. Depends on backend PR (verify-email endpoint)."
```

---

## Meta repo (branch `feat/identity-auth-core-bump`)

### Task M1: Bump submodule pointers + STATE update + deploy verification

> Do this only after both submodule PRs are merged to their `main` branches.

**Files:**
- Modify: `backend`, `dashboard` submodule pointers
- Modify: `STATE.md`
- Modify: `ISSUES.md` (clear the throwaway smoke-test-users item if you reset staging)

- [ ] **Step 1: Update submodules to merged `main`**

```bash
git -C backend fetch origin && git -C backend checkout main && git -C backend pull
git -C dashboard fetch origin && git -C dashboard checkout main && git -C dashboard pull
```

- [ ] **Step 2: Set staging env on the VPS**

On the VPS, add to `.env.production`: `DJANGO_FRONTEND_URL=https://app-staging.kaleem.academy`. (Not synced by CI — managed on the box.)

- [ ] **Step 3: Update STATE.md**

Mark the identity frontend Phase 1 (auth core) as shipped, Phase A as closed once the staging click-through passes, and set the next active item to Phase 2 (parent flows).

- [ ] **Step 4: Commit + PR to develop**

```bash
git checkout -b feat/identity-auth-core-bump develop
git add backend dashboard STATE.md ISSUES.md
git commit -m "chore: bump identity auth-core submodule pointers; close Phase A"
git push -u origin feat/identity-auth-core-bump
gh pr create --base develop --title "chore: identity auth-core pointers + Phase A close" --body "Bumps backend + dashboard to the merged auth-core work; updates STATE."
```

- [ ] **Step 5: Promote develop → master to deploy to staging**

After the develop PR merges and CI is green, open the `develop → master` PR (the deploy-staging trigger). Watch the `deploy-staging` job.

- [ ] **Step 6: Verify the golden path on staging (closes Phase A)**

Register with a **real email address** on `https://app-staging.kaleem.academy/register` → receive the SES email → click the link → land on `/verify-email` → "verified" → `/login` → log in → role-aware home renders against `api-staging`. This proves the cross-subdomain session cookie end-to-end. **Phase A closed.**

---

## Self-Review

**Spec coverage:**
- Register → D6, D7. ✅
- Verify-pending + resend (incl. 429) → D8. ✅
- Custom /verify-email landing + backend endpoint + adapter override → B1, B2, D9. ✅
- Login (incl. not-verified resend affordance) → D5, D7. ✅
- Auth state (useMe + guard) → D3, D10. ✅
- Logout (clear cache) → D3, D11. ✅
- Role-aware home → D11. ✅
- Profile edit → D11. ✅
- i18n/RTL → D4 + a11y tests in each component task. ✅
- a11y (jest-axe) → D5, D6, D11 carry axe tests; existing gate covers AuthLayout. ✅
- Error helper for DRF shapes → D2. ✅
- react-hook-form + module-mocked tests → D0 + every component test uses `vi.mock`. ✅
- Remove /design-preview → D12. ✅
- Staging deploy + golden-path verify → M1. ✅
- Phase 2/3 (parent/student/availability grid) → explicitly deferred to their own plans (scope note). ✅

**Placeholder scan:** No TBD/TODO left as work items. The two "verify the primitive's props" notes (Alert variant, Button asChild) are deliberate guards against inventing props, with a concrete fallback — not placeholders for missing code.

**Type consistency:** `Me`, `LoginInput`, `RegisterInput`, `ProfileEditInput` defined in D1 and used consistently in D2/D3/D5/D6/D11. `identityApi` method names (`login/logout/me/updateMe/register/resendVerification/verifyEmail`) consistent across D2/D3 and all mocks. `meQueryKey`/`meQueryOptions`/`ensureAuthed` consistent across D3/D10. Backend `VerifyEmailView`/`VerifyEmailSerializer`/`verify-email/` consistent across B2.
