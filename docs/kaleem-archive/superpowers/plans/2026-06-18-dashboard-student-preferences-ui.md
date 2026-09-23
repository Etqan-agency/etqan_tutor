# Student Preferences UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a signed-in student set their learning preferences (teacher-gender + repeatable time slots) on the `/account` page, backed by a new read endpoint so the form pre-fills.

**Architecture:** A small additive backend change (a `GET` on the existing `me/student-profile/` view) plus a dashboard `features/identity` slice: schemas → api → query hooks → a `StudentPreferencesCard` (react-hook-form + `useFieldArray`) rendered student-only on the existing `/account` route. Spec 4 (final) of the dashboard-completion roadmap.

**Tech Stack:** Django + DRF + pytest (backend); React 19, TanStack Query, react-hook-form (`useFieldArray`), zod, react-i18next (en/ar + RTL), Tailwind + shadcn tokens, Vitest + Testing Library + jest-axe, biome (dashboard).

## Global Constraints

- **Two repos.** Task 1 is in the **`backend`** submodule on branch `feat/student-profile-get` (off `main`). Tasks 2–4 are in the **`dashboard`** submodule on branch `feat/student-preferences-ui` (off `main`). Git-flow: submodules use `feat → main`.
- **Backend:** business logic stays in `services.py`; views are thin; module boundaries enforced by import-linter. The DRF handler maps `NotFoundError` → 404 `{"detail": ...}` and `ValidationError(field=…)` → 400 `{field: [...]}` (see `kaleem/platform/drf.py`). Commit with `PIP_CONFIG_FILE=/dev/null` prefix if a pip-proxy pre-commit error appears; **never** `--no-verify`. Tests: `pytest`; lint: `ruff`, `mypy`, `lint-imports`.
- **Dashboard:** API URL from the `api` axios instance (baseURL includes `/api/v1/`) — pass `"identity/me/student-profile/"`, no leading slash, no version. No cross-feature imports (everything under `src/features/identity/` except the `/account` route file). i18n + RTL baseline (ADR-0020): every user-facing string is a key present in BOTH `src/locales/en/common.json` and `src/locales/ar/common.json` (en/ar parity); logical CSS only. WCAG 2.2 AA: every control label-associated (or `aria-label`), jest-axe per component. No new npm dependency.
- **TDD, failing test first, test output pristine.** Dashboard tests mock `../api`'s `identityApi`. tsc + biome clean before each dashboard commit.
- **Commit trailer** on every commit (both repos): `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

---

## File Structure

**Backend (repo `backend`):**
- Modify: `kaleem/identity/api/views.py` — add `get()` to `StudentProfileView`.
- Modify: `kaleem/identity/api/serializers.py` — add `StudentProfileResponseSerializer`.
- Modify: `kaleem/identity/tests/test_api_auth.py` — add GET tests to `TestStudentProfileEndpoint`.

**Dashboard (repo `dashboard`):**
- Modify: `src/features/identity/schemas.ts` — `TimeSlot`, `TeacherGender`, `StudentProfile`, `WEEKDAYS`, `timeSlotSchema`, `studentPreferencesSchema`.
- Modify: `src/features/identity/api.ts` — `getStudentProfile`, `saveStudentProfile`.
- Modify: `src/features/identity/queries.ts` — `studentProfileQueryKey`, `useStudentProfile`, `useSaveStudentProfile`.
- Modify: `src/features/identity/schemas.test.ts`, `src/features/identity/queries.test.tsx` — tests.
- Modify: `src/locales/en/common.json`, `src/locales/ar/common.json` — a `prefs` block.
- Create: `src/features/identity/components/StudentPreferencesCard.tsx` + `.test.tsx`.
- Modify: `src/routes/_authed/account.tsx` — export `Account({ me })`, render the student-only card.
- Create: `src/routes/_authed/account.test.tsx`.

---

## Task 1: Backend — `GET me/student-profile/`

**Repo:** `backend` · **Branch:** `feat/student-profile-get` (off `main`)

**Files:**
- Modify: `kaleem/identity/api/serializers.py`
- Modify: `kaleem/identity/api/views.py`
- Test: `kaleem/identity/tests/test_api_auth.py`

**Interfaces:**
- Produces: `GET /api/v1/identity/me/student-profile/` → `200 {"time_preferences": [{"day","start_time","end_time"}], "teacher_gender_preference": "<male|female|no_preference>"}`; `404 {"detail": ...}` when the caller has no `StudentProfile`.

- [ ] **Step 1: Write the failing tests** — add to the existing `TestStudentProfileEndpoint` class in `kaleem/identity/tests/test_api_auth.py`:

```python
    def test_get_student_profile_returns_saved_preferences(self, api):
        user = User.objects.create_user(email="spget@example.com", password="pw")
        StudentProfile.objects.create(
            user=user,
            time_preferences=[
                {"day": "monday", "start_time": "17:00", "end_time": "20:00"}
            ],
            teacher_gender_preference="female",
        )
        api.force_authenticate(user=user)
        resp = api.get("/api/v1/identity/me/student-profile/")
        assert resp.status_code == 200, resp.data
        assert resp.data == {
            "time_preferences": [
                {"day": "monday", "start_time": "17:00", "end_time": "20:00"}
            ],
            "teacher_gender_preference": "female",
        }

    def test_get_student_profile_404_when_no_profile(self, api):
        user = User.objects.create_user(email="noprofile@example.com", password="pw")
        api.force_authenticate(user=user)
        resp = api.get("/api/v1/identity/me/student-profile/")
        assert resp.status_code == 404, resp.data

    def test_get_student_profile_requires_auth(self, api):
        resp = api.get("/api/v1/identity/me/student-profile/")
        assert resp.status_code in (401, 403)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd backend && pytest kaleem/identity/tests/test_api_auth.py::TestStudentProfileEndpoint -v`
Expected: the two new GET-200/404 tests FAIL (GET not implemented — DRF returns 405 Method Not Allowed); the auth test may pass incidentally (405 vs 403) — it asserts `in (401, 403)` so it will FAIL too until GET exists.

- [ ] **Step 3: Add the response serializer** — in `kaleem/identity/api/serializers.py`, after the existing `StudentProfileSerializer` (which defines `TimeSlotSerializer` above it), add:

```python
class StudentProfileResponseSerializer(serializers.Serializer):
    time_preferences = TimeSlotSerializer(many=True)
    teacher_gender_preference = serializers.CharField()
```

- [ ] **Step 4: Add the GET handler** — in `kaleem/identity/api/views.py`, import the new serializer and the NotFoundError, then add a `get()` to `StudentProfileView`.

Add to the imports at the top:

```python
from kaleem.identity.api.serializers import StudentProfileResponseSerializer
from kaleem.platform.exceptions import NotFoundError
```

Add this method to `StudentProfileView` (above the existing `post`):

```python
    @extend_schema(
        responses={200: StudentProfileResponseSerializer},
        summary="Get the caller's student onboarding preferences.",
    )
    def get(self, request):
        profile = services.get_student_profile(request.user.id)
        if profile is None:
            raise NotFoundError("StudentProfile", request.user.id)
        return Response(
            {
                "time_preferences": profile.time_preferences,
                "teacher_gender_preference": profile.teacher_gender_preference,
            }
        )
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd backend && pytest kaleem/identity/tests/test_api_auth.py::TestStudentProfileEndpoint -v`
Expected: all tests in the class PASS (GET 200, GET 404, GET auth, plus the existing POST test).

- [ ] **Step 6: Lint + commit**

```bash
cd backend
ruff check kaleem/identity && ruff format --check kaleem/identity && mypy kaleem/identity && lint-imports
git add kaleem/identity/api/serializers.py kaleem/identity/api/views.py kaleem/identity/tests/test_api_auth.py
PIP_CONFIG_FILE=/dev/null git commit -m "feat(identity): GET me/student-profile/ returns saved preferences

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

Expected: ruff/mypy/lint-imports clean; commit succeeds.

---

## Task 2: Dashboard data layer + i18n

**Repo:** `dashboard` · **Branch:** `feat/student-preferences-ui` (off `main`)

**Files:**
- Modify: `src/features/identity/schemas.ts`
- Modify: `src/features/identity/api.ts`
- Modify: `src/features/identity/queries.ts`
- Modify: `src/features/identity/schemas.test.ts`, `src/features/identity/queries.test.tsx`
- Modify: `src/locales/en/common.json`, `src/locales/ar/common.json`

**Interfaces:**
- Consumes: the backend `GET/POST identity/me/student-profile/` (Task 1, separate repo).
- Produces:
  - `interface TimeSlot { day: string; start_time: string; end_time: string }`
  - `type TeacherGender = "male" | "female" | "no_preference"`
  - `interface StudentProfile { time_preferences: TimeSlot[]; teacher_gender_preference: TeacherGender }`
  - `WEEKDAYS: readonly string[]` (Saturday-first)
  - `studentPreferencesSchema` → `StudentPreferencesInput`
  - `identityApi.getStudentProfile(): Promise<StudentProfile>`, `identityApi.saveStudentProfile(input: StudentPreferencesInput): Promise<void>`
  - `studentProfileQueryKey = ["student-profile"]`, `useStudentProfile()`, `useSaveStudentProfile()` (invalidates `["student-profile"]`)

- [ ] **Step 1: Write the failing schema test** — append to `src/features/identity/schemas.test.ts`:

```ts
import { studentPreferencesSchema } from "./schemas";

describe("student preferences schema", () => {
	it("accepts valid preferences", () => {
		const result = studentPreferencesSchema.safeParse({
			teacher_gender_preference: "female",
			time_preferences: [{ day: "monday", start_time: "17:00", end_time: "20:00" }],
		});
		expect(result.success).toBe(true);
	});

	it("accepts an empty time_preferences list", () => {
		const result = studentPreferencesSchema.safeParse({
			teacher_gender_preference: "no_preference",
			time_preferences: [],
		});
		expect(result.success).toBe(true);
	});

	it("rejects an unknown teacher gender", () => {
		const result = studentPreferencesSchema.safeParse({
			teacher_gender_preference: "other",
			time_preferences: [],
		});
		expect(result.success).toBe(false);
	});
});
```

- [ ] **Step 2: Run the schema test to verify it fails**

Run: `pnpm exec vitest run src/features/identity/schemas.test.ts`
Expected: FAIL — `studentPreferencesSchema` not exported.

- [ ] **Step 3: Add the types + schema** — append to `src/features/identity/schemas.ts`:

```ts
export interface TimeSlot {
	day: string;
	start_time: string;
	end_time: string;
}

export type TeacherGender = "male" | "female" | "no_preference";

export interface StudentProfile {
	time_preferences: TimeSlot[];
	teacher_gender_preference: TeacherGender;
}

// Saturday-first (the conventional week start in the Arabic/Islamic context).
export const WEEKDAYS = [
	"saturday",
	"sunday",
	"monday",
	"tuesday",
	"wednesday",
	"thursday",
	"friday",
] as const;

// Structural typing only — required/ordering rules are enforced (and translated)
// in the StudentPreferencesCard onSubmit so messages can use t(...).
export const timeSlotSchema = z.object({
	day: z.string(),
	start_time: z.string(),
	end_time: z.string(),
});

export const studentPreferencesSchema = z.object({
	teacher_gender_preference: z.enum(["male", "female", "no_preference"]),
	time_preferences: z.array(timeSlotSchema),
});
export type StudentPreferencesInput = z.infer<typeof studentPreferencesSchema>;
```

- [ ] **Step 4: Run the schema test to verify it passes**

Run: `pnpm exec vitest run src/features/identity/schemas.test.ts`
Expected: PASS.

- [ ] **Step 5: Write the failing hook tests** — in `src/features/identity/queries.test.tsx`, add the two new methods to the mocked `identityApi` object (alongside the existing ones):

```ts
				getStudentProfile: vi.fn(),
				saveStudentProfile: vi.fn(),
```

Add these imports to the existing `./queries` import:

```ts
	useSaveStudentProfile,
	useStudentProfile,
```

Append the describe block (reuses the existing `wrapper` + `spiedWrapper` helpers):

```ts
const profile = {
	teacher_gender_preference: "female" as const,
	time_preferences: [{ day: "monday", start_time: "17:00", end_time: "20:00" }],
};

describe("student profile queries", () => {
	beforeEach(() => vi.clearAllMocks());

	it("useStudentProfile returns the saved preferences", async () => {
		vi.mocked(identityApi.getStudentProfile).mockResolvedValue(profile);
		const { result } = renderHook(() => useStudentProfile(), { wrapper });
		await waitFor(() => expect(result.current.data).toEqual(profile));
	});

	it("useSaveStudentProfile invalidates the student-profile query", async () => {
		vi.mocked(identityApi.saveStudentProfile).mockResolvedValue(undefined);
		const { wrap, spy } = spiedWrapper();
		const { result } = renderHook(() => useSaveStudentProfile(), { wrapper: wrap });
		await result.current.mutateAsync(profile);
		expect(spy).toHaveBeenCalledWith({ queryKey: ["student-profile"] });
	});
});
```

- [ ] **Step 6: Run the hook tests to verify they fail**

Run: `pnpm exec vitest run src/features/identity/queries.test.tsx`
Expected: FAIL — `useStudentProfile`/`useSaveStudentProfile` not exported.

- [ ] **Step 7: Add the api wrappers** — in `src/features/identity/api.ts`, extend the type import to add `StudentPreferencesInput` and `StudentProfile`, then add to the `identityApi` object (after `acceptInvite`):

```ts
	getStudentProfile: () =>
		api
			.get<StudentProfile>("identity/me/student-profile/")
			.then((r) => r.data),
	saveStudentProfile: (input: StudentPreferencesInput) =>
		api.post("identity/me/student-profile/", input).then(() => undefined),
```

- [ ] **Step 8: Add the query hooks** — in `src/features/identity/queries.ts`, extend the type import to add `StudentPreferencesInput`, then append (after `useAcceptInvite`, before `useUpdateMe`):

```ts
export const studentProfileQueryKey = ["student-profile"] as const;

export const studentProfileQueryOptions = {
	queryKey: studentProfileQueryKey,
	queryFn: identityApi.getStudentProfile,
	retry: false,
};

export function useStudentProfile() {
	return useQuery(studentProfileQueryOptions);
}

export function useSaveStudentProfile() {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (input: StudentPreferencesInput) =>
			identityApi.saveStudentProfile(input),
		onSuccess: () =>
			qc.invalidateQueries({ queryKey: studentProfileQueryKey }),
	});
}
```

- [ ] **Step 9: Add the `prefs` i18n block** — add a new top-level `"prefs"` object to `src/locales/en/common.json`:

```json
	"prefs": {
		"title": "Learning preferences",
		"teacherGender": "Preferred teacher gender",
		"gender": {
			"no_preference": "No preference",
			"male": "Male",
			"female": "Female"
		},
		"timeSlots": "Preferred times",
		"noSlots": "No time slots yet.",
		"day": "Day",
		"start": "Start time",
		"end": "End time",
		"weekday": {
			"saturday": "Saturday",
			"sunday": "Sunday",
			"monday": "Monday",
			"tuesday": "Tuesday",
			"wednesday": "Wednesday",
			"thursday": "Thursday",
			"friday": "Friday"
		},
		"addSlot": "Add time slot",
		"removeSlot": "Remove time slot",
		"save": "Save preferences",
		"saved": "Saved.",
		"timeRequired": "Start and end times are required.",
		"endAfterStart": "End time must be after start time.",
		"loadError": "Couldn't load your preferences.",
		"throttled": "Please wait a moment before trying again.",
		"genericError": "Something went wrong. Please try again."
	}
```

And the matching Arabic `"prefs"` object in `src/locales/ar/common.json`:

```json
	"prefs": {
		"title": "تفضيلات التعلّم",
		"teacherGender": "الجنس المفضّل للمعلّم",
		"gender": {
			"no_preference": "لا تفضيل",
			"male": "ذكر",
			"female": "أنثى"
		},
		"timeSlots": "الأوقات المفضّلة",
		"noSlots": "لا توجد أوقات بعد.",
		"day": "اليوم",
		"start": "وقت البدء",
		"end": "وقت الانتهاء",
		"weekday": {
			"saturday": "السبت",
			"sunday": "الأحد",
			"monday": "الاثنين",
			"tuesday": "الثلاثاء",
			"wednesday": "الأربعاء",
			"thursday": "الخميس",
			"friday": "الجمعة"
		},
		"addSlot": "إضافة وقت",
		"removeSlot": "إزالة الوقت",
		"save": "حفظ التفضيلات",
		"saved": "تم الحفظ.",
		"timeRequired": "وقت البدء والانتهاء مطلوبان.",
		"endAfterStart": "يجب أن يكون وقت الانتهاء بعد وقت البدء.",
		"loadError": "تعذّر تحميل تفضيلاتك.",
		"throttled": "يرجى الانتظار لحظة قبل المحاولة مرة أخرى.",
		"genericError": "حدث خطأ ما. يرجى المحاولة مرة أخرى."
	}
```

- [ ] **Step 10: Run the hook tests + typecheck + lint to verify green**

Run: `pnpm exec vitest run src/features/identity/queries.test.tsx src/features/identity/schemas.test.ts && pnpm exec tsc --noEmit && pnpm exec biome check src/features/identity src/locales`
Expected: PASS; no type errors; biome clean (run `biome check --write` if it reports formatting, then re-run the tests).

- [ ] **Step 11: Commit**

```bash
git add src/features/identity/schemas.ts src/features/identity/schemas.test.ts src/features/identity/api.ts src/features/identity/queries.ts src/features/identity/queries.test.tsx src/locales/en/common.json src/locales/ar/common.json
git commit -m "feat(identity): student-profile schemas, api, hooks + prefs i18n

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Dashboard — `StudentPreferencesCard`

**Repo:** `dashboard` · **Branch:** `feat/student-preferences-ui`

**Files:**
- Create: `src/features/identity/components/StudentPreferencesCard.tsx`
- Create: `src/features/identity/components/StudentPreferencesCard.test.tsx`

**Interfaces:**
- Consumes: `useStudentProfile`, `useSaveStudentProfile` (Task 2); `studentPreferencesSchema`/`StudentPreferencesInput`/`TeacherGender`/`WEEKDAYS` (Task 2); `parseApiError`; `@/ui` `Card`/`Field`/`Input`/`Alert`/`Button`/`Spinner`.
- Produces: `StudentPreferencesCard()` — the student's "Learning preferences" card.

- [ ] **Step 1: Write the failing test** — `src/features/identity/components/StudentPreferencesCard.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "jest-axe";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { identityApi } from "../api";
import { StudentPreferencesCard } from "./StudentPreferencesCard";

vi.mock("../api", async (orig) => {
	const actual = await orig<typeof import("../api")>();
	return {
		...actual,
		identityApi: { getStudentProfile: vi.fn(), saveStudentProfile: vi.fn() },
	};
});

function wrapper({ children }: { children: ReactNode }) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
	});
	return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

const saved = {
	teacher_gender_preference: "female" as const,
	time_preferences: [{ day: "monday", start_time: "17:00", end_time: "20:00" }],
};

describe("StudentPreferencesCard", () => {
	beforeEach(() => vi.clearAllMocks());

	it("pre-fills the form from the saved preferences", async () => {
		vi.mocked(identityApi.getStudentProfile).mockResolvedValue(saved);
		render(<StudentPreferencesCard />, { wrapper });
		expect(await screen.findByDisplayValue("17:00")).toBeInTheDocument();
		expect(screen.getByDisplayValue("20:00")).toBeInTheDocument();
		expect(screen.getByLabelText(/preferred teacher gender/i)).toHaveValue("female");
	});

	it("adds and removes a time slot", async () => {
		vi.mocked(identityApi.getStudentProfile).mockResolvedValue({
			teacher_gender_preference: "no_preference",
			time_preferences: [],
		});
		render(<StudentPreferencesCard />, { wrapper });
		await screen.findByText(/no time slots yet/i);
		await userEvent.click(screen.getByRole("button", { name: /add time slot/i }));
		expect(screen.getAllByLabelText(/^day$/i)).toHaveLength(1);
		await userEvent.click(screen.getByRole("button", { name: /remove time slot/i }));
		expect(screen.queryByLabelText(/^day$/i)).toBeNull();
	});

	it("saves valid preferences and shows the confirmation", async () => {
		vi.mocked(identityApi.getStudentProfile).mockResolvedValue(saved);
		vi.mocked(identityApi.saveStudentProfile).mockResolvedValue(undefined);
		render(<StudentPreferencesCard />, { wrapper });
		await screen.findByDisplayValue("17:00");
		await userEvent.click(screen.getByRole("button", { name: /save preferences/i }));
		await waitFor(() =>
			expect(screen.getByText(/^saved\.$/i)).toBeInTheDocument(),
		);
		expect(identityApi.saveStudentProfile).toHaveBeenCalledWith({
			teacher_gender_preference: "female",
			time_preferences: [{ day: "monday", start_time: "17:00", end_time: "20:00" }],
		});
	});

	it("blocks save when end is not after start", async () => {
		vi.mocked(identityApi.getStudentProfile).mockResolvedValue({
			teacher_gender_preference: "no_preference",
			time_preferences: [{ day: "monday", start_time: "20:00", end_time: "17:00" }],
		});
		render(<StudentPreferencesCard />, { wrapper });
		await screen.findByDisplayValue("20:00");
		await userEvent.click(screen.getByRole("button", { name: /save preferences/i }));
		await waitFor(() =>
			expect(screen.getByText(/end time must be after start time/i)).toBeInTheDocument(),
		);
		expect(identityApi.saveStudentProfile).not.toHaveBeenCalled();
	});

	it("saves an empty list after removing all slots", async () => {
		vi.mocked(identityApi.getStudentProfile).mockResolvedValue(saved);
		vi.mocked(identityApi.saveStudentProfile).mockResolvedValue(undefined);
		render(<StudentPreferencesCard />, { wrapper });
		await screen.findByDisplayValue("17:00");
		await userEvent.click(screen.getByRole("button", { name: /remove time slot/i }));
		await userEvent.click(screen.getByRole("button", { name: /save preferences/i }));
		await waitFor(() =>
			expect(identityApi.saveStudentProfile).toHaveBeenCalledWith({
				teacher_gender_preference: "female",
				time_preferences: [],
			}),
		);
	});

	it("shows a spinner while loading", () => {
		vi.mocked(identityApi.getStudentProfile).mockReturnValue(new Promise(() => {}));
		render(<StudentPreferencesCard />, { wrapper });
		expect(screen.getByRole("status")).toBeInTheDocument();
	});

	it("shows an alert on load error", async () => {
		vi.mocked(identityApi.getStudentProfile).mockRejectedValue(new Error("boom"));
		render(<StudentPreferencesCard />, { wrapper });
		await waitFor(() =>
			expect(screen.getByText(/couldn't load your preferences/i)).toBeInTheDocument(),
		);
	});

	it("has no axe violations", async () => {
		vi.mocked(identityApi.getStudentProfile).mockResolvedValue(saved);
		const { container } = render(<StudentPreferencesCard />, { wrapper });
		await screen.findByDisplayValue("17:00");
		expect(await axe(container)).toHaveNoViolations();
	});
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pnpm exec vitest run src/features/identity/components/StudentPreferencesCard.test.tsx`
Expected: FAIL — `StudentPreferencesCard` does not exist.

- [ ] **Step 3: Implement `StudentPreferencesCard.tsx`**:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useEffect, useState } from "react";
import { useFieldArray, useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import {
	Alert,
	AlertDescription,
	Button,
	Card,
	CardContent,
	CardHeader,
	CardTitle,
	Field,
	Input,
	Spinner,
} from "@/ui";
import { parseApiError } from "../api";
import { useSaveStudentProfile, useStudentProfile } from "../queries";
import {
	type StudentPreferencesInput,
	type TeacherGender,
	WEEKDAYS,
	studentPreferencesSchema,
} from "../schemas";

const GENDERS: TeacherGender[] = ["no_preference", "male", "female"];
const SELECT_CLASS =
	"flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background";

export function StudentPreferencesCard() {
	const { t } = useTranslation();
	const { data, isPending, isError } = useStudentProfile();
	const save = useSaveStudentProfile();
	const [saved, setSaved] = useState(false);
	const {
		register,
		control,
		handleSubmit,
		reset,
		setError,
		clearErrors,
		formState: { errors, isSubmitting },
	} = useForm<StudentPreferencesInput>({
		resolver: zodResolver(studentPreferencesSchema),
		defaultValues: { teacher_gender_preference: "no_preference", time_preferences: [] },
	});
	const { fields, append, remove } = useFieldArray({
		control,
		name: "time_preferences",
	});

	// Seed the form once the saved preferences arrive (and on refetch after save).
	useEffect(() => {
		if (data) reset(data);
	}, [data, reset]);

	async function onSubmit(values: StudentPreferencesInput) {
		setSaved(false);
		clearErrors(["root.server", "time_preferences"]);
		let hasError = false;
		values.time_preferences.forEach((slot, i) => {
			if (!slot.start_time || !slot.end_time) {
				setError(`time_preferences.${i}.end_time`, {
					message: t("prefs.timeRequired"),
				});
				hasError = true;
			} else if (slot.end_time <= slot.start_time) {
				setError(`time_preferences.${i}.end_time`, {
					message: t("prefs.endAfterStart"),
				});
				hasError = true;
			}
		});
		if (hasError) return;
		try {
			await save.mutateAsync(values);
			setSaved(true);
		} catch (error) {
			const parsed = parseApiError(error);
			setError("root.server", {
				message: parsed.throttled
					? t("prefs.throttled")
					: (parsed.message ?? t("prefs.genericError")),
			});
		}
	}

	return (
		<Card>
			<CardHeader>
				<CardTitle>{t("prefs.title")}</CardTitle>
			</CardHeader>
			<CardContent>
				{isPending ? <Spinner /> : null}
				{isError ? (
					<Alert variant="destructive">
						<AlertDescription>{t("prefs.loadError")}</AlertDescription>
					</Alert>
				) : null}
				{data ? (
					<form
						onSubmit={handleSubmit(onSubmit)}
						className="flex flex-col gap-4"
						noValidate
					>
						<Field id="teacher_gender" label={t("prefs.teacherGender")}>
							<select
								className={SELECT_CLASS}
								{...register("teacher_gender_preference")}
							>
								{GENDERS.map((g) => (
									<option key={g} value={g}>
										{t(`prefs.gender.${g}`)}
									</option>
								))}
							</select>
						</Field>

						<fieldset className="flex flex-col gap-3">
							<legend className="text-sm font-medium">
								{t("prefs.timeSlots")}
							</legend>
							{fields.length === 0 ? (
								<p className="text-sm text-muted-foreground">
									{t("prefs.noSlots")}
								</p>
							) : null}
							{fields.map((field, index) => (
								<div
									key={field.id}
									className="flex flex-wrap items-center gap-2"
								>
									<select
										aria-label={t("prefs.day")}
										className={`${SELECT_CLASS} w-auto`}
										{...register(`time_preferences.${index}.day`)}
									>
										{WEEKDAYS.map((d) => (
											<option key={d} value={d}>
												{t(`prefs.weekday.${d}`)}
											</option>
										))}
									</select>
									<Input
										type="time"
										aria-label={t("prefs.start")}
										className="w-auto"
										{...register(`time_preferences.${index}.start_time`)}
									/>
									<Input
										type="time"
										aria-label={t("prefs.end")}
										className="w-auto"
										{...register(`time_preferences.${index}.end_time`)}
									/>
									<Button
										type="button"
										variant="outline"
										size="sm"
										aria-label={t("prefs.removeSlot")}
										onClick={() => remove(index)}
									>
										×
									</Button>
									{errors.time_preferences?.[index]?.end_time ? (
										<p role="alert" className="w-full text-sm text-destructive">
											{errors.time_preferences[index]?.end_time?.message}
										</p>
									) : null}
								</div>
							))}
							<Button
								type="button"
								variant="outline"
								size="sm"
								onClick={() =>
									append({ day: WEEKDAYS[0], start_time: "09:00", end_time: "10:00" })
								}
							>
								{t("prefs.addSlot")}
							</Button>
						</fieldset>

						{errors.root?.server ? (
							<Alert variant="destructive">
								<AlertDescription>{errors.root.server.message}</AlertDescription>
							</Alert>
						) : null}
						{saved ? (
							<Alert>
								<AlertDescription>{t("prefs.saved")}</AlertDescription>
							</Alert>
						) : null}
						<Button type="submit" disabled={isSubmitting}>
							{t("prefs.save")}
						</Button>
					</form>
				) : null}
			</CardContent>
		</Card>
	);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pnpm exec vitest run src/features/identity/components/StudentPreferencesCard.test.tsx`
Expected: PASS (8/8). Confirm the output is pristine (no stray warnings).

- [ ] **Step 5: Typecheck + lint + commit**

```bash
pnpm exec tsc --noEmit && pnpm exec biome check src/features/identity
git add src/features/identity/components/StudentPreferencesCard.tsx src/features/identity/components/StudentPreferencesCard.test.tsx
git commit -m "feat(identity): StudentPreferencesCard (teacher gender + time slots)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

(Run `pnpm exec biome check --write src/features/identity` first if biome reports formatting on the verbatim code, then re-run the test.)

---

## Task 4: Dashboard — render the card on `/account` (student-only)

**Repo:** `dashboard` · **Branch:** `feat/student-preferences-ui`

**Files:**
- Modify: `src/routes/_authed/account.tsx`
- Create: `src/routes/_authed/account.test.tsx`

**Interfaces:**
- Consumes: `StudentPreferencesCard` (Task 3), `useMe`/`Me` (existing), `ProfileEditForm`/`EmailAddresses` (existing).
- Produces: an exported `Account({ me }: { me: Me })` component (testable, like `Home`/`Family`), rendered by the route.

- [ ] **Step 1: Write the failing test** — `src/routes/_authed/account.test.tsx` (mirrors `src/routes/_authed/family.test.tsx`):

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import {
	createMemoryHistory,
	createRootRoute,
	createRoute,
	createRouter,
	RouterProvider,
} from "@tanstack/react-router";
import { render, screen } from "@testing-library/react";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { identityApi } from "@/features/identity/api";
import type { Me } from "@/features/identity/schemas";
import { ThemeProvider } from "@/lib/theme";
import { Account } from "./account";

vi.mock("@/features/identity/api", async (orig) => {
	const actual = await orig<typeof import("@/features/identity/api")>();
	return {
		...actual,
		identityApi: {
			me: vi.fn(),
			updateMe: vi.fn(),
			listEmails: vi.fn(),
			getStudentProfile: vi.fn(),
		},
	};
});

function renderAccount(me: Me) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
	});
	const rootRoute = createRootRoute();
	const route = createRoute({
		getParentRoute: () => rootRoute,
		path: "/",
		component: () => <Account me={me} />,
	});
	const router = createRouter({
		routeTree: rootRoute.addChildren([route]),
		history: createMemoryHistory({ initialEntries: ["/"] }),
	});
	return render(
		<ThemeProvider>
			<QueryClientProvider client={client}>
				<RouterProvider router={router} />
			</QueryClientProvider>
		</ThemeProvider>,
	);
}

const student: Me = { id: 1, email: "s@b.com", full_name: "Sara", profiles: ["student"] };
const parent: Me = { id: 2, email: "p@b.com", full_name: "Pat", profiles: ["parent"] };

describe("Account route", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(identityApi.listEmails).mockResolvedValue([]);
		vi.mocked(identityApi.getStudentProfile).mockResolvedValue({
			teacher_gender_preference: "no_preference",
			time_preferences: [],
		});
	});

	it("shows the learning-preferences card for a student", async () => {
		renderAccount(student);
		expect(await screen.findByText(/learning preferences/i)).toBeInTheDocument();
	});

	it("hides the learning-preferences card for a non-student", () => {
		renderAccount(parent);
		expect(screen.queryByText(/learning preferences/i)).toBeNull();
	});
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pnpm exec vitest run src/routes/_authed/account.test.tsx`
Expected: FAIL — `account.tsx` does not export `Account`.

- [ ] **Step 3: Refactor `account.tsx` to export `Account({ me })` + render the student card** — replace the contents of `src/routes/_authed/account.tsx` with:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { EmailAddresses } from "@/features/identity/components/EmailAddresses";
import { ProfileEditForm } from "@/features/identity/components/ProfileEditForm";
import { StudentPreferencesCard } from "@/features/identity/components/StudentPreferencesCard";
import { useMe } from "@/features/identity/queries";
import type { Me } from "@/features/identity/schemas";
import { Card, CardContent, CardHeader, CardTitle } from "@/ui";

export function Account({ me }: { me: Me }) {
	const { t } = useTranslation();
	return (
		<div className="mx-auto flex w-full max-w-md flex-col gap-4">
			<Card>
				<CardHeader>
					<CardTitle>{t("auth.profile")}</CardTitle>
				</CardHeader>
				<CardContent>
					<ProfileEditForm me={me} />
				</CardContent>
			</Card>
			<EmailAddresses />
			{me.profiles.includes("student") ? <StudentPreferencesCard /> : null}
		</div>
	);
}

export const Route = createFileRoute("/_authed/account")({
	component: function AccountRoute() {
		const { data: me } = useMe();
		if (!me) return null;
		return <Account me={me} />;
	},
});
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pnpm exec vitest run src/routes/_authed/account.test.tsx`
Expected: PASS (both cases).

- [ ] **Step 5: Typecheck + lint + commit**

```bash
pnpm exec tsc --noEmit && pnpm exec biome check src/routes/_authed
git add src/routes/_authed/account.tsx src/routes/_authed/account.test.tsx
git commit -m "feat(identity): render student preferences card on /account

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Dashboard — full-suite green + lint closeout

**Repo:** `dashboard` · **Branch:** `feat/student-preferences-ui` · **Files:** none (verification only).

- [ ] **Step 1: Run the entire dashboard test suite**

Run: `pnpm exec vitest run`
Expected: PASS — all suites green (the pre-existing `scrollTo not implemented` stderr on route tests is jsdom noise, not a failure).

- [ ] **Step 2: Typecheck the whole project**

Run: `pnpm exec tsc --noEmit`
Expected: no errors.

- [ ] **Step 3: Lint + format check**

Run: `pnpm exec biome check src`
Expected: no errors (one pre-existing `main.tsx` non-null-assertion warning is acceptable — it predates this branch). If biome reports formatting on this branch's files, run `pnpm exec biome check --write src`, re-run the suite, and amend the last commit.

- [ ] **Step 4: Confirm clean tree**

Run: `git status --short`
Expected: empty.

---

## Self-Review (completed during planning)

**1. Spec coverage:**
- Backend `GET me/student-profile/` (+404) → Task 1. ✅
- schemas/api/queries data layer + `prefs` i18n (en+ar) → Task 2. ✅
- `StudentPreferencesCard` (pre-fill, teacher-gender select, repeatable slots add/remove, end>start + required validation in onSubmit, empty-list save, save confirmation, loading/error) → Task 3. ✅
- Student-only card on `/account` → Task 4. ✅
- Days Saturday-first, localized → `WEEKDAYS` (Task 2) + `prefs.weekday.*` (Task 2), used in Task 3. ✅
- a11y (label/aria-label per control, jest-axe), RTL logical CSS → Task 3 + Global Constraints. ✅
- Full-suite/lint gate → Task 5. ✅

**2. Placeholder scan:** No TBD/TODO; every code step shows complete code; every command has an expected result.

**3. Type consistency:** `StudentProfile`/`TimeSlot`/`TeacherGender`/`StudentPreferencesInput`/`WEEKDAYS` defined in Task 2 are used with the same names in Tasks 3–4. `getStudentProfile()`/`saveStudentProfile(input)` and `useStudentProfile`/`useSaveStudentProfile` are consistent across api/queries/tests/component. The backend GET response shape `{time_preferences, teacher_gender_preference}` (Task 1) matches the `StudentProfile` interface (Task 2). The save payload asserted in Task 3's test matches `StudentPreferencesInput`.

**Note for the executor (validation lives in onSubmit, by design):** `timeSlotSchema` intentionally does no required/ordering validation — `studentPreferencesSchema`'s only real guard is the `teacher_gender_preference` enum. Required-times and end-after-start are enforced in `StudentPreferencesCard.onSubmit` with `t(...)` messages (zod refine messages can't be translated). Do not "harden" the schema with `.min(1)`/`.refine(...)` — that would surface untranslated English messages and is what this design deliberately avoids. New slot rows default to `{ day: WEEKDAYS[0], start_time: "09:00", end_time: "10:00" }` so a fresh row is already valid.

**Note (cross-repo):** Tasks 1 (backend) and 2–5 (dashboard) are in different submodules on different branches. The dashboard UI can be built and unit-tested independently (the api is mocked in tests); the live end-to-end only works once the backend GET is deployed. Ship both via their own `feat → main` PRs; bump both submodule pointers in the meta docs PR.
