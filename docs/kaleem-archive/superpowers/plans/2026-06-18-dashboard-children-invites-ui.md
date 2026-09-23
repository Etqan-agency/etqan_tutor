# Dashboard Children + Invites UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a role-aware `/family` page to the dashboard where a parent manages children (list, add by name, set password) and generates invite codes, and a student accepts an invite code to link to a parent.

**Architecture:** Frontend-only, inside the dashboard's `features/identity` slice. It consumes existing identity endpoints via `src/lib/api.ts` (no backend change). New types/schemas → `identityApi` axios wrappers → TanStack Query hooks → small prop-driven components (react-hook-form + zod + radix dialogs) → a role-aware TanStack file route. Mirrors the email-management UI shipped in Spec 2.

**Tech Stack:** React 19, TanStack Router (file-based), TanStack Query, react-hook-form, zod, `radix-ui` (already installed), lucide-react, react-i18next (en/ar + RTL), Tailwind + shadcn tokens, Vitest + Testing Library + user-event + jest-axe, biome.

## Global Constraints

- **No backend change.** Consume existing endpoints only:
  - `GET /api/v1/identity/children/` → `[{ id, full_name, student_profile_id, teacher_gender_preference }]`
  - `POST /api/v1/identity/children/` — body `{ full_name }` → `201 { child_user_id, student_profile_id }`
  - `POST /api/v1/identity/children/{student_profile_id}/set-password/` — body `{ password }` (min 8) → `200`
  - `POST /api/v1/identity/invites/` — no body → `201 { code, expires_at }`
  - `POST /api/v1/identity/invites/accept/` — body `{ code }` → `200 { parent_name, linked }`
- **Axios paths are relative to `/api/v1/`** (the `api` instance baseURL already includes it) — pass `"identity/children/"`, never a leading slash, never the version.
- **No cross-feature imports.** Everything lives under `src/features/identity/` except the one nav entry in `src/features/shell/nav.ts` and the route file in `src/routes/_authed/`.
- **i18n + RTL baseline (ADR-0020):** every user-facing string is a translation key present in **both** `src/locales/en/common.json` and `src/locales/ar/common.json`; use logical CSS (`me-auto`, `start-*`, `ms-*`) never left/right. No hard-coded copy in components.
- **a11y baseline (WCAG 2.2 AA):** dialogs labelled + focus-trapped (radix gives this), every input label-associated via `Field id=…`, jest-axe passes on each component.
- **TDD, 100% line+branch, failing test first.** Tests mock `../api`'s `identityApi` (never real network); route/component tests `import "@/lib/i18n"` and assert the real English copy.
- **Commit trailer** on every commit:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- **Pre-commit:** if a pip-proxy hook error appears, commit with `PIP_CONFIG_FILE=/dev/null` prefixed — **never** `--no-verify`.
- **Branch:** all work on the dashboard submodule's `feat/children-invites-ui` branch off `main` (git-flow: submodules use `feat → main`).

---

## File Structure

**New files:**
- `src/features/identity/components/AddChildForm.tsx` — reveal-on-click full-name form.
- `src/features/identity/components/SetChildPasswordDialog.tsx` — radix Dialog, password field.
- `src/features/identity/components/ChildrenCard.tsx` — children list card; hosts the two above.
- `src/features/identity/components/InviteCard.tsx` — generate/copy/expiry invite card.
- `src/features/identity/components/AcceptInviteCard.tsx` — student code-entry card.
- `src/routes/_authed/family.tsx` — role-aware `/family` route (exports `Family` + `Route`).
- Test files alongside each (`*.test.tsx`).

**Modified files:**
- `src/features/identity/schemas.ts` — Child/Invite types + three zod schemas.
- `src/features/identity/api.ts` — five `identityApi` methods.
- `src/features/identity/queries.ts` — children query + five hooks.
- `src/features/shell/nav.ts` — `requiresAny` support + Family nav item.
- `src/features/shell/nav.test.ts` — updated `NAV_ITEMS` assertion + `requiresAny` case.
- `src/locales/en/common.json` + `src/locales/ar/common.json` — `nav.family` + a `family` block.
- `src/test/setup.ts` — `navigator.clipboard` stub (added in the InviteCard task).
- `src/routeTree.gen.ts` — regenerated (auto, in the route task).
- Meta repo: `ISSUES.md` — log the child-login limitation (final task).

---

## Task 1: Schemas (types + zod)

**Files:**
- Modify: `src/features/identity/schemas.ts`
- Test: `src/features/identity/schemas.test.ts`

**Interfaces:**
- Produces:
  - `interface Child { id: number; full_name: string; student_profile_id: number; teacher_gender_preference: string }`
  - `interface Invite { code: string; expires_at: string }`
  - `addChildSchema` → `AddChildInput = { full_name: string }`
  - `setChildPasswordSchema` → `SetChildPasswordInput = { password: string }`
  - `acceptInviteSchema` → `AcceptInviteInput = { code: string }`

- [ ] **Step 1: Write the failing tests** — append to `src/features/identity/schemas.test.ts`:

```ts
import {
	acceptInviteSchema,
	addChildSchema,
	setChildPasswordSchema,
} from "./schemas";

describe("children + invites schemas", () => {
	it("accepts a child with a name and rejects an empty one", () => {
		expect(addChildSchema.safeParse({ full_name: "Yusuf" }).success).toBe(true);
		expect(addChildSchema.safeParse({ full_name: "" }).success).toBe(false);
	});

	it("requires a child password of at least 8 chars", () => {
		expect(setChildPasswordSchema.safeParse({ password: "longenough" }).success).toBe(true);
		expect(setChildPasswordSchema.safeParse({ password: "short" }).success).toBe(false);
	});

	it("requires a non-empty invite code", () => {
		expect(acceptInviteSchema.safeParse({ code: "abc" }).success).toBe(true);
		expect(acceptInviteSchema.safeParse({ code: "" }).success).toBe(false);
	});
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pnpm exec vitest run src/features/identity/schemas.test.ts`
Expected: FAIL — `addChildSchema`/`setChildPasswordSchema`/`acceptInviteSchema` are not exported.

- [ ] **Step 3: Add the types and schemas** — append to `src/features/identity/schemas.ts` (after the existing `EmailAddress`/`setPrimarySchema` block, before `interface Me`):

```ts
export interface Child {
	id: number;
	full_name: string;
	student_profile_id: number;
	teacher_gender_preference: string;
}

export interface Invite {
	code: string;
	expires_at: string;
}

export const addChildSchema = z.object({ full_name: z.string().min(1) });
export type AddChildInput = z.infer<typeof addChildSchema>;

export const setChildPasswordSchema = z.object({ password: z.string().min(8) });
export type SetChildPasswordInput = z.infer<typeof setChildPasswordSchema>;

export const acceptInviteSchema = z.object({ code: z.string().min(1) });
export type AcceptInviteInput = z.infer<typeof acceptInviteSchema>;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pnpm exec vitest run src/features/identity/schemas.test.ts`
Expected: PASS (all schema tests green).

- [ ] **Step 5: Typecheck + commit**

```bash
pnpm exec tsc --noEmit
git add src/features/identity/schemas.ts src/features/identity/schemas.test.ts
git commit -m "feat(identity): child + invite schemas and types

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Data layer (api wrappers + query hooks)

**Files:**
- Modify: `src/features/identity/api.ts`
- Modify: `src/features/identity/queries.ts`
- Test: `src/features/identity/queries.test.tsx`

**Interfaces:**
- Consumes (Task 1): `Child`, `Invite`, `AddChildInput`, `SetChildPasswordInput`, `AcceptInviteInput`.
- Produces:
  - `identityApi.listChildren(): Promise<Child[]>`
  - `identityApi.addChild(input: AddChildInput): Promise<{ child_user_id: number; student_profile_id: number }>`
  - `identityApi.setChildPassword(studentProfileId: number, input: SetChildPasswordInput): Promise<void>`
  - `identityApi.createInvite(): Promise<Invite>`
  - `identityApi.acceptInvite(input: AcceptInviteInput): Promise<{ parent_name: string; linked: boolean }>`
  - `childrenQueryKey = ["children"]`, `useChildren()`
  - `useAddChild()` (invalidates `["children"]` + `["me"]`), `useSetChildPassword()`, `useCreateInvite()`, `useAcceptInvite()` (invalidates `["me"]`). `useSetChildPassword` mutates `{ studentProfileId, input }`.

Note: the thin axios wrappers in `api.ts` are not unit-tested directly (codebase convention — `register`/`login`/`me` aren't either); they are exercised via the query-hook tests, which mock `identityApi`.

- [ ] **Step 1: Write the failing hook tests** — append to `src/features/identity/queries.test.tsx`. First extend the existing `vi.mock("./api", …)` `identityApi` object to add the five new methods, then add the describe block:

Add these keys inside the mocked `identityApi` object (alongside `me`, `login`, …):

```ts
				listChildren: vi.fn(),
				addChild: vi.fn(),
				setChildPassword: vi.fn(),
				createInvite: vi.fn(),
				acceptInvite: vi.fn(),
```

Add these imports to the existing import from `./queries`:

```ts
	useAcceptInvite,
	useAddChild,
	useChildren,
	useCreateInvite,
	useSetChildPassword,
```

Append the describe block (reuses the existing `spiedWrapper` + `wrapper` helpers):

```ts
const child = { id: 9, full_name: "Yusuf", student_profile_id: 3, teacher_gender_preference: "no_preference" };

describe("children + invite queries", () => {
	beforeEach(() => vi.clearAllMocks());

	it("useChildren lists children", async () => {
		vi.mocked(identityApi.listChildren).mockResolvedValue([child]);
		const { result } = renderHook(() => useChildren(), { wrapper });
		await waitFor(() => expect(result.current.data).toEqual([child]));
	});

	it("useAddChild invalidates children and me", async () => {
		vi.mocked(identityApi.addChild).mockResolvedValue({ child_user_id: 9, student_profile_id: 3 });
		const { wrap, spy } = spiedWrapper();
		const { result } = renderHook(() => useAddChild(), { wrapper: wrap });
		await result.current.mutateAsync({ full_name: "Yusuf" });
		expect(spy).toHaveBeenCalledWith({ queryKey: ["children"] });
		expect(spy).toHaveBeenCalledWith({ queryKey: ["me"] });
	});

	it("useSetChildPassword calls the api with the profile id and input", async () => {
		vi.mocked(identityApi.setChildPassword).mockResolvedValue(undefined);
		const { result } = renderHook(() => useSetChildPassword(), { wrapper });
		await result.current.mutateAsync({ studentProfileId: 3, input: { password: "longenough" } });
		expect(identityApi.setChildPassword).toHaveBeenCalledWith(3, { password: "longenough" });
	});

	it("useCreateInvite returns a fresh code", async () => {
		const invite = { code: "abc123", expires_at: "2026-06-19T00:00:00Z" };
		vi.mocked(identityApi.createInvite).mockResolvedValue(invite);
		const { result } = renderHook(() => useCreateInvite(), { wrapper });
		await expect(result.current.mutateAsync()).resolves.toEqual(invite);
	});

	it("useAcceptInvite invalidates me", async () => {
		vi.mocked(identityApi.acceptInvite).mockResolvedValue({ parent_name: "Pat", linked: true });
		const { wrap, spy } = spiedWrapper();
		const { result } = renderHook(() => useAcceptInvite(), { wrapper: wrap });
		await result.current.mutateAsync({ code: "abc123" });
		expect(spy).toHaveBeenCalledWith({ queryKey: ["me"] });
	});
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pnpm exec vitest run src/features/identity/queries.test.tsx`
Expected: FAIL — the five hooks are not exported.

- [ ] **Step 3a: Add the api wrappers** — in `src/features/identity/api.ts`, extend the type import to add the new types:

```ts
import type {
	AcceptInviteInput,
	AddChildInput,
	AddEmailInput,
	Child,
	EmailAddress,
	Invite,
	LoginInput,
	Me,
	ProfileEditInput,
	RegisterInput,
	SetChildPasswordInput,
	SetPrimaryInput,
} from "./schemas";
```

Then add these methods inside the `identityApi` object (after `removeEmail`):

```ts
	listChildren: () =>
		api.get<Child[]>("identity/children/").then((r) => r.data),
	addChild: (input: AddChildInput) =>
		api
			.post<{ child_user_id: number; student_profile_id: number }>(
				"identity/children/",
				input,
			)
			.then((r) => r.data),
	setChildPassword: (studentProfileId: number, input: SetChildPasswordInput) =>
		api
			.post(`identity/children/${studentProfileId}/set-password/`, input)
			.then(() => undefined),
	createInvite: () =>
		api.post<Invite>("identity/invites/").then((r) => r.data),
	acceptInvite: (input: AcceptInviteInput) =>
		api
			.post<{ parent_name: string; linked: boolean }>(
				"identity/invites/accept/",
				input,
			)
			.then((r) => r.data),
```

- [ ] **Step 3b: Add the query hooks** — in `src/features/identity/queries.ts`, extend the type import:

```ts
import type {
	AcceptInviteInput,
	AddChildInput,
	AddEmailInput,
	LoginInput,
	Me,
	ProfileEditInput,
	RegisterInput,
	SetChildPasswordInput,
	SetPrimaryInput,
} from "./schemas";
```

Append (after `useVerifyEmail`, before `useUpdateMe`):

```ts
export const childrenQueryKey = ["children"] as const;

export const childrenQueryOptions = {
	queryKey: childrenQueryKey,
	queryFn: identityApi.listChildren,
	retry: false,
};

export function useChildren() {
	return useQuery(childrenQueryOptions);
}

export function useAddChild() {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (input: AddChildInput) => identityApi.addChild(input),
		onSuccess: () => {
			qc.invalidateQueries({ queryKey: childrenQueryKey });
			qc.invalidateQueries({ queryKey: meQueryKey });
		},
	});
}

export function useSetChildPassword() {
	return useMutation({
		mutationFn: ({
			studentProfileId,
			input,
		}: {
			studentProfileId: number;
			input: SetChildPasswordInput;
		}) => identityApi.setChildPassword(studentProfileId, input),
	});
}

export function useCreateInvite() {
	return useMutation({ mutationFn: () => identityApi.createInvite() });
}

export function useAcceptInvite() {
	const qc = useQueryClient();
	return useMutation({
		mutationFn: (input: AcceptInviteInput) => identityApi.acceptInvite(input),
		onSuccess: () => qc.invalidateQueries({ queryKey: meQueryKey }),
	});
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pnpm exec vitest run src/features/identity/queries.test.tsx`
Expected: PASS (all children + invite query tests green).

- [ ] **Step 5: Typecheck + commit**

```bash
pnpm exec tsc --noEmit
git add src/features/identity/api.ts src/features/identity/queries.ts src/features/identity/queries.test.tsx
git commit -m "feat(identity): children + invite api wrappers and query hooks

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Navigation — Family item + `requiresAny`

**Files:**
- Modify: `src/features/shell/nav.ts`
- Modify: `src/features/shell/nav.test.ts`
- Modify: `src/locales/en/common.json`, `src/locales/ar/common.json` (add `nav.family`)

**Interfaces:**
- Produces: `NavItem` gains `requiresAny?: ProfileType[]`; `NAV_ITEMS` gains `{ to: "/family", labelKey: "nav.family", icon: Users, requiresAny: ["parent", "student"] }`; `visibleNavItems` shows an item when it has neither `requires` nor `requiresAny`, when `requires` matches, **or** when any `requiresAny` role matches.

- [ ] **Step 1: Update the failing tests** — replace the body of `src/features/shell/nav.test.ts` with:

```ts
import { Home, User, Users } from "lucide-react";
import { describe, expect, it } from "vitest";
import type { ProfileType } from "@/features/identity/schemas";
import { NAV_ITEMS, type NavItem, visibleNavItems } from "./nav";

const items: NavItem[] = [
	{ to: "/", labelKey: "auth.home", icon: Home },
	{ to: "/children", labelKey: "nav.children", icon: User, requires: "parent" },
	{ to: "/family", labelKey: "nav.family", icon: Users, requiresAny: ["parent", "student"] },
];

describe("visibleNavItems", () => {
	it("always keeps items with no requirement", () => {
		expect(visibleNavItems(items, [] as ProfileType[]).map((i) => i.to)).toEqual(["/"]);
	});

	it("keeps a `requires` item only when the profile matches", () => {
		expect(visibleNavItems(items, ["parent"]).map((i) => i.to)).toContain("/children");
		expect(visibleNavItems(items, ["student"]).map((i) => i.to)).not.toContain("/children");
	});

	it("keeps a `requiresAny` item when any listed role matches", () => {
		expect(visibleNavItems(items, ["student"]).map((i) => i.to)).toContain("/family");
		expect(visibleNavItems(items, ["parent"]).map((i) => i.to)).toContain("/family");
		expect(visibleNavItems(items, ["teacher"]).map((i) => i.to)).not.toContain("/family");
	});
});

describe("NAV_ITEMS", () => {
	it("ships Home, Family, and Account", () => {
		expect(NAV_ITEMS.map((i) => i.to)).toEqual(["/", "/family", "/account"]);
	});

	it("gates Family to parents or students", () => {
		const family = NAV_ITEMS.find((i) => i.to === "/family");
		expect(family?.requiresAny).toEqual(["parent", "student"]);
	});
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pnpm exec vitest run src/features/shell/nav.test.ts`
Expected: FAIL — `NAV_ITEMS` has no `/family`; `requiresAny` is not honoured.

- [ ] **Step 3: Update `nav.ts`** — replace the file contents with:

```ts
import type { LucideIcon } from "lucide-react";
import { Home, User, Users } from "lucide-react";
import type { ProfileType } from "@/features/identity/schemas";

export type NavItem = {
	to: string;
	labelKey: string;
	icon: LucideIcon;
	requires?: ProfileType;
	requiresAny?: ProfileType[];
};

export const NAV_ITEMS: NavItem[] = [
	{ to: "/", labelKey: "auth.home", icon: Home },
	{ to: "/family", labelKey: "nav.family", icon: Users, requiresAny: ["parent", "student"] },
	{ to: "/account", labelKey: "auth.account", icon: User },
];

export function visibleNavItems(
	items: NavItem[],
	profiles: readonly ProfileType[],
): NavItem[] {
	return items.filter((i) => {
		if (i.requires) return profiles.includes(i.requires);
		if (i.requiresAny) return i.requiresAny.some((r) => profiles.includes(r));
		return true;
	});
}
```

- [ ] **Step 4: Add the `nav.family` copy** — in `src/locales/en/common.json` add to the `nav` object: `"family": "Family"`. In `src/locales/ar/common.json` add to the `nav` object: `"family": "العائلة"`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `pnpm exec vitest run src/features/shell/nav.test.ts`
Expected: PASS.

- [ ] **Step 6: Run the full shell suite (sidebar/topbar render NAV_ITEMS) + commit**

Run: `pnpm exec vitest run src/features/shell`
Expected: PASS — confirm the new nav item didn't break `AppSidebar`/`AppTopbar` rendering. If a sidebar/topbar test asserts an exact nav-item count, update it to include Family (visible when the mocked `me` is a parent/student).

```bash
git add src/features/shell/nav.ts src/features/shell/nav.test.ts src/locales/en/common.json src/locales/ar/common.json
git commit -m "feat(shell): add Family nav item gated to parents or students

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: AddChildForm

**Files:**
- Create: `src/features/identity/components/AddChildForm.tsx`
- Create: `src/features/identity/components/AddChildForm.test.tsx`
- Modify: `src/locales/en/common.json`, `src/locales/ar/common.json` (start the `family` block)

**Interfaces:**
- Consumes: `useAddChild` (Task 2), `addChildSchema`/`AddChildInput` (Task 1), `parseApiError`.
- Produces: `AddChildForm({ onSuccess }: { onSuccess: (name: string) => void })`.

- [ ] **Step 1: Add the `family` i18n keys** — add a new top-level `"family"` object to `src/locales/en/common.json`:

```json
	"family": {
		"title": "Family",
		"nothingHere": "Nothing here yet.",
		"children": "My children",
		"noChildren": "No children yet.",
		"addChild": "Add child",
		"addChildSubmit": "Add child",
		"childName": "Child's full name",
		"childAdded": "{{name}} added.",
		"setPassword": "Set password",
		"setPasswordTitle": "Set a password for {{name}}",
		"newPassword": "New password",
		"passwordSet": "Password set for {{name}}.",
		"cancel": "Cancel",
		"save": "Save",
		"invite": "Invite a student",
		"generateCode": "Generate invite code",
		"generateNewCode": "Generate new code",
		"copy": "Copy",
		"copied": "Copied",
		"expiresIn": "Expires in 24 hours.",
		"regenerateNote": "Generating a new code invalidates the previous one.",
		"linkParent": "Link to a parent",
		"inviteCode": "Invite code",
		"link": "Link",
		"linked": "You're now linked to {{name}}.",
		"throttled": "Please wait a moment before trying again.",
		"genericError": "Something went wrong. Please try again.",
		"loadError": "Couldn't load your children."
	}
```

And the matching Arabic `"family"` object in `src/locales/ar/common.json`:

```json
	"family": {
		"title": "العائلة",
		"nothingHere": "لا يوجد شيء هنا بعد.",
		"children": "أبنائي",
		"noChildren": "لا يوجد أبناء بعد.",
		"addChild": "إضافة ابن",
		"addChildSubmit": "إضافة ابن",
		"childName": "اسم الابن الكامل",
		"childAdded": "تمت إضافة {{name}}.",
		"setPassword": "تعيين كلمة المرور",
		"setPasswordTitle": "تعيين كلمة مرور لـ {{name}}",
		"newPassword": "كلمة مرور جديدة",
		"passwordSet": "تم تعيين كلمة المرور لـ {{name}}.",
		"cancel": "إلغاء",
		"save": "حفظ",
		"invite": "دعوة طالب",
		"generateCode": "إنشاء رمز دعوة",
		"generateNewCode": "إنشاء رمز جديد",
		"copy": "نسخ",
		"copied": "تم النسخ",
		"expiresIn": "تنتهي الصلاحية خلال ٢٤ ساعة.",
		"regenerateNote": "إنشاء رمز جديد يُلغي الرمز السابق.",
		"linkParent": "الارتباط بوليّ أمر",
		"inviteCode": "رمز الدعوة",
		"link": "ربط",
		"linked": "أنت الآن مرتبط بـ {{name}}.",
		"throttled": "يرجى الانتظار لحظة قبل المحاولة مرة أخرى.",
		"genericError": "حدث خطأ ما. يرجى المحاولة مرة أخرى.",
		"loadError": "تعذّر تحميل قائمة أبنائك."
	}
```

- [ ] **Step 2: Write the failing test** — `src/features/identity/components/AddChildForm.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { axe } from "jest-axe";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { identityApi } from "../api";
import { AddChildForm } from "./AddChildForm";

vi.mock("../api", async (orig) => {
	const actual = await orig<typeof import("../api")>();
	return { ...actual, identityApi: { addChild: vi.fn() } };
});

function wrapper({ children }: { children: ReactNode }) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
	});
	return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

describe("AddChildForm", () => {
	beforeEach(() => vi.clearAllMocks());

	it("submits a name and calls onSuccess with it", async () => {
		vi.mocked(identityApi.addChild).mockResolvedValue({ child_user_id: 9, student_profile_id: 3 });
		const onSuccess = vi.fn();
		render(<AddChildForm onSuccess={onSuccess} />, { wrapper });
		await userEvent.type(screen.getByLabelText(/child's full name/i), "Yusuf");
		await userEvent.click(screen.getByRole("button", { name: /add child/i }));
		await waitFor(() => expect(onSuccess).toHaveBeenCalledWith("Yusuf"));
		expect(identityApi.addChild).toHaveBeenCalledWith({ full_name: "Yusuf" });
	});

	it("shows a field error from the server", async () => {
		const err = new AxiosError("bad");
		err.response = { status: 400, data: { full_name: ["Too long"] } } as never;
		vi.mocked(identityApi.addChild).mockRejectedValue(err);
		render(<AddChildForm onSuccess={vi.fn()} />, { wrapper });
		await userEvent.type(screen.getByLabelText(/child's full name/i), "Yusuf");
		await userEvent.click(screen.getByRole("button", { name: /add child/i }));
		await waitFor(() => expect(screen.getByText(/too long/i)).toBeInTheDocument());
	});

	it("has no axe violations", async () => {
		const { container } = render(<AddChildForm onSuccess={vi.fn()} />, { wrapper });
		expect(await axe(container)).toHaveNoViolations();
	});
});
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `pnpm exec vitest run src/features/identity/components/AddChildForm.test.tsx`
Expected: FAIL — `AddChildForm` does not exist.

- [ ] **Step 4: Implement `AddChildForm.tsx`**:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { Alert, AlertDescription, Button, Field, Input } from "@/ui";
import { parseApiError } from "../api";
import { useAddChild } from "../queries";
import { type AddChildInput, addChildSchema } from "../schemas";

export function AddChildForm({ onSuccess }: { onSuccess: (name: string) => void }) {
	const { t } = useTranslation();
	const add = useAddChild();
	const {
		register,
		handleSubmit,
		setError,
		formState: { errors, isSubmitting },
	} = useForm<AddChildInput>({
		resolver: zodResolver(addChildSchema),
		defaultValues: { full_name: "" },
	});

	async function onSubmit(values: AddChildInput) {
		try {
			await add.mutateAsync(values);
			onSuccess(values.full_name);
		} catch (error) {
			const parsed = parseApiError(error);
			for (const [field, message] of Object.entries(parsed.fieldErrors)) {
				setError(field as keyof AddChildInput, { message });
			}
			if (parsed.throttled) {
				setError("root.server", { message: t("family.throttled") });
			} else if (parsed.message) {
				setError("root.server", { message: parsed.message });
			}
		}
	}

	return (
		<form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-4" noValidate>
			<Field id="child_name" label={t("family.childName")} error={errors.full_name?.message}>
				<Input autoComplete="off" {...register("full_name")} />
			</Field>
			{errors.root?.server ? (
				<Alert variant="destructive">
					<AlertDescription>{errors.root.server.message}</AlertDescription>
				</Alert>
			) : null}
			<Button type="submit" disabled={isSubmitting}>
				{t("family.addChildSubmit")}
			</Button>
		</form>
	);
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `pnpm exec vitest run src/features/identity/components/AddChildForm.test.tsx`
Expected: PASS.

- [ ] **Step 6: Typecheck + commit**

```bash
pnpm exec tsc --noEmit
git add src/features/identity/components/AddChildForm.tsx src/features/identity/components/AddChildForm.test.tsx src/locales/en/common.json src/locales/ar/common.json
git commit -m "feat(identity): AddChildForm (name-only) + family i18n copy

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: SetChildPasswordDialog

**Files:**
- Create: `src/features/identity/components/SetChildPasswordDialog.tsx`
- Create: `src/features/identity/components/SetChildPasswordDialog.test.tsx`

**Interfaces:**
- Consumes: `useSetChildPassword` (Task 2), `setChildPasswordSchema`/`SetChildPasswordInput` (Task 1), `Child` (Task 1), `parseApiError`. Radix `Dialog` (`import { Dialog } from "radix-ui"`).
- Produces: `SetChildPasswordDialog({ child, onSuccess }: { child: Child; onSuccess: (name: string) => void })`. Controlled per-instance `open` state (one instance per child row, like `SetPrimaryDialog`).

- [ ] **Step 1: Write the failing test** — `SetChildPasswordDialog.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "jest-axe";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { identityApi } from "../api";
import { SetChildPasswordDialog } from "./SetChildPasswordDialog";

vi.mock("../api", async (orig) => {
	const actual = await orig<typeof import("../api")>();
	return { ...actual, identityApi: { setChildPassword: vi.fn() } };
});

function wrapper({ children }: { children: ReactNode }) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
	});
	return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

const child = { id: 9, full_name: "Yusuf", student_profile_id: 3, teacher_gender_preference: "no_preference" };

describe("SetChildPasswordDialog", () => {
	beforeEach(() => vi.clearAllMocks());

	it("sets the password and calls onSuccess", async () => {
		vi.mocked(identityApi.setChildPassword).mockResolvedValue(undefined);
		const onSuccess = vi.fn();
		render(<SetChildPasswordDialog child={child} onSuccess={onSuccess} />, { wrapper });
		await userEvent.click(screen.getByRole("button", { name: /set password/i }));
		await userEvent.type(await screen.findByLabelText(/new password/i), "longenough");
		await userEvent.click(screen.getByRole("button", { name: /save/i }));
		await waitFor(() => expect(onSuccess).toHaveBeenCalledWith("Yusuf"));
		expect(identityApi.setChildPassword).toHaveBeenCalledWith(3, { password: "longenough" });
	});

	it("keeps the dialog open and shows a server error", async () => {
		const { AxiosError } = await import("axios");
		const err = new AxiosError("bad");
		err.response = { status: 400, data: { password: ["Too weak"] } } as never;
		vi.mocked(identityApi.setChildPassword).mockRejectedValue(err);
		render(<SetChildPasswordDialog child={child} onSuccess={vi.fn()} />, { wrapper });
		await userEvent.click(screen.getByRole("button", { name: /set password/i }));
		await userEvent.type(await screen.findByLabelText(/new password/i), "longenough");
		await userEvent.click(screen.getByRole("button", { name: /save/i }));
		await waitFor(() => expect(screen.getByText(/too weak/i)).toBeInTheDocument());
	});

	it("has no axe violations when open", async () => {
		const { container } = render(<SetChildPasswordDialog child={child} onSuccess={vi.fn()} />, { wrapper });
		await userEvent.click(screen.getByRole("button", { name: /set password/i }));
		await screen.findByLabelText(/new password/i);
		expect(await axe(container)).toHaveNoViolations();
	});
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pnpm exec vitest run src/features/identity/components/SetChildPasswordDialog.test.tsx`
Expected: FAIL — `SetChildPasswordDialog` does not exist.

- [ ] **Step 3: Implement `SetChildPasswordDialog.tsx`** (mirrors `SetPrimaryDialog`, single password field, no re-auth):

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { Dialog } from "radix-ui";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { Alert, AlertDescription, Button, Field, Input } from "@/ui";
import { parseApiError } from "../api";
import { useSetChildPassword } from "../queries";
import { type Child, type SetChildPasswordInput, setChildPasswordSchema } from "../schemas";

export function SetChildPasswordDialog({
	child,
	onSuccess,
}: {
	child: Child;
	onSuccess: (name: string) => void;
}) {
	const { t } = useTranslation();
	const [open, setOpen] = useState(false);
	const setPassword = useSetChildPassword();
	const {
		register,
		handleSubmit,
		setError,
		reset,
		formState: { errors, isSubmitting },
	} = useForm<SetChildPasswordInput>({
		resolver: zodResolver(setChildPasswordSchema),
		defaultValues: { password: "" },
	});

	async function onSubmit(values: SetChildPasswordInput) {
		try {
			await setPassword.mutateAsync({ studentProfileId: child.student_profile_id, input: values });
			reset();
			setOpen(false);
			onSuccess(child.full_name);
		} catch (error) {
			const parsed = parseApiError(error);
			if (parsed.fieldErrors.password) {
				setError("password", { message: parsed.fieldErrors.password });
			} else {
				setError("root.server", { message: parsed.message ?? t("family.genericError") });
			}
		}
	}

	return (
		<Dialog.Root
			open={open}
			onOpenChange={(next) => {
				if (!next) reset();
				setOpen(next);
			}}
		>
			<Dialog.Trigger asChild>
				<Button variant="outline" size="sm">
					{t("family.setPassword")}
				</Button>
			</Dialog.Trigger>
			<Dialog.Portal>
				<Dialog.Overlay className="fixed inset-0 z-40 bg-black/40" />
				<Dialog.Content className="fixed start-1/2 top-1/2 z-50 w-[min(90vw,24rem)] -translate-x-1/2 -translate-y-1/2 rounded-lg border border-border bg-background p-6 shadow-lg rtl:translate-x-1/2">
					<Dialog.Title className="font-display text-lg font-semibold">
						{t("family.setPasswordTitle", { name: child.full_name })}
					</Dialog.Title>
					<form onSubmit={handleSubmit(onSubmit)} className="mt-4 flex flex-col gap-4" noValidate>
						<Field id="child_password" label={t("family.newPassword")} error={errors.password?.message}>
							<Input type="password" autoComplete="new-password" {...register("password")} />
						</Field>
						{errors.root?.server ? (
							<Alert variant="destructive">
								<AlertDescription>{errors.root.server.message}</AlertDescription>
							</Alert>
						) : null}
						<div className="flex justify-end gap-2">
							<Dialog.Close asChild>
								<Button type="button" variant="outline" disabled={isSubmitting}>
									{t("family.cancel")}
								</Button>
							</Dialog.Close>
							<Button type="submit" disabled={isSubmitting}>
								{t("family.save")}
							</Button>
						</div>
					</form>
				</Dialog.Content>
			</Dialog.Portal>
		</Dialog.Root>
	);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pnpm exec vitest run src/features/identity/components/SetChildPasswordDialog.test.tsx`
Expected: PASS.

- [ ] **Step 5: Typecheck + commit**

```bash
pnpm exec tsc --noEmit
git add src/features/identity/components/SetChildPasswordDialog.tsx src/features/identity/components/SetChildPasswordDialog.test.tsx
git commit -m "feat(identity): SetChildPasswordDialog

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: ChildrenCard

**Files:**
- Create: `src/features/identity/components/ChildrenCard.tsx`
- Create: `src/features/identity/components/ChildrenCard.test.tsx`

**Interfaces:**
- Consumes: `useChildren` (Task 2), `AddChildForm` (Task 4), `SetChildPasswordDialog` (Task 5), `Child` (Task 1), `@/ui` `Card`/`Spinner`/`Alert`/`Button`.
- Produces: `ChildrenCard()` — the parent's "My children" card.

- [ ] **Step 1: Write the failing test** — `ChildrenCard.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "jest-axe";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { identityApi } from "../api";
import { ChildrenCard } from "./ChildrenCard";

vi.mock("../api", async (orig) => {
	const actual = await orig<typeof import("../api")>();
	return { ...actual, identityApi: { listChildren: vi.fn(), addChild: vi.fn(), setChildPassword: vi.fn() } };
});

function wrapper({ children }: { children: ReactNode }) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
	});
	return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

const children = [
	{ id: 9, full_name: "Yusuf", student_profile_id: 3, teacher_gender_preference: "no_preference" },
	{ id: 10, full_name: "Maryam", student_profile_id: 4, teacher_gender_preference: "no_preference" },
];

describe("ChildrenCard", () => {
	beforeEach(() => vi.clearAllMocks());

	it("lists children with a set-password button each", async () => {
		vi.mocked(identityApi.listChildren).mockResolvedValue(children);
		render(<ChildrenCard />, { wrapper });
		const row = (await screen.findByText("Yusuf")).closest("li") as HTMLElement;
		expect(within(row).getByRole("button", { name: /set password/i })).toBeInTheDocument();
		expect(screen.getByText("Maryam")).toBeInTheDocument();
	});

	it("shows the empty state when there are no children", async () => {
		vi.mocked(identityApi.listChildren).mockResolvedValue([]);
		render(<ChildrenCard />, { wrapper });
		await waitFor(() => expect(screen.getByText(/no children yet/i)).toBeInTheDocument());
	});

	it("adds a child and shows the confirmation", async () => {
		vi.mocked(identityApi.listChildren).mockResolvedValue([]);
		vi.mocked(identityApi.addChild).mockResolvedValue({ child_user_id: 9, student_profile_id: 3 });
		render(<ChildrenCard />, { wrapper });
		await screen.findByText(/no children yet/i);
		await userEvent.click(screen.getByRole("button", { name: /add child/i }));
		await userEvent.type(screen.getByLabelText(/child's full name/i), "Yusuf");
		await userEvent.click(screen.getByRole("button", { name: /^add child$/i }));
		await waitFor(() => expect(screen.getByText(/yusuf added/i)).toBeInTheDocument());
	});

	it("sets a child's password and shows the confirmation", async () => {
		vi.mocked(identityApi.listChildren).mockResolvedValue(children);
		vi.mocked(identityApi.setChildPassword).mockResolvedValue(undefined);
		render(<ChildrenCard />, { wrapper });
		const row = (await screen.findByText("Yusuf")).closest("li") as HTMLElement;
		await userEvent.click(within(row).getByRole("button", { name: /set password/i }));
		await userEvent.type(await screen.findByLabelText(/new password/i), "longenough");
		await userEvent.click(screen.getByRole("button", { name: /save/i }));
		await waitFor(() => expect(screen.getByText(/password set for yusuf/i)).toBeInTheDocument());
	});

	it("shows a spinner while loading", () => {
		vi.mocked(identityApi.listChildren).mockReturnValue(new Promise(() => {}));
		render(<ChildrenCard />, { wrapper });
		expect(screen.getByRole("status")).toBeInTheDocument();
	});

	it("shows an alert on error", async () => {
		vi.mocked(identityApi.listChildren).mockRejectedValue(new Error("boom"));
		render(<ChildrenCard />, { wrapper });
		await waitFor(() => expect(screen.getByText(/couldn't load your children/i)).toBeInTheDocument());
	});

	it("has no axe violations", async () => {
		vi.mocked(identityApi.listChildren).mockResolvedValue(children);
		const { container } = render(<ChildrenCard />, { wrapper });
		await screen.findByText("Yusuf");
		expect(await axe(container)).toHaveNoViolations();
	});
});
```

Note on the add-child assertion: the submit button uses copy `family.addChildSubmit` = "Add child" and the reveal button uses `family.addChild` = "Add child" too, so the test disambiguates with the anchored `/^add child$/i` on the submit and the reveal click happens first while the form is hidden. To keep them unambiguous, the reveal button is only present before revealing and the submit button only after — they are never in the DOM at the same time.

- [ ] **Step 2: Run the test to verify it fails**

Run: `pnpm exec vitest run src/features/identity/components/ChildrenCard.test.tsx`
Expected: FAIL — `ChildrenCard` does not exist.

- [ ] **Step 3: Implement `ChildrenCard.tsx`** (mirrors `EmailAddresses`):

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Alert, AlertDescription, Button, Card, CardContent, CardHeader, CardTitle, Spinner } from "@/ui";
import { useChildren } from "../queries";
import { AddChildForm } from "./AddChildForm";
import { SetChildPasswordDialog } from "./SetChildPasswordDialog";

export function ChildrenCard() {
	const { t } = useTranslation();
	const { data: children, isPending, isError } = useChildren();
	const [adding, setAdding] = useState(false);
	const [notice, setNotice] = useState<string | null>(null);

	return (
		<Card>
			<CardHeader>
				<CardTitle>{t("family.children")}</CardTitle>
			</CardHeader>
			<CardContent className="flex flex-col gap-4">
				{isPending ? <Spinner /> : null}
				{isError ? (
					<Alert variant="destructive">
						<AlertDescription>{t("family.loadError")}</AlertDescription>
					</Alert>
				) : null}
				{children && children.length > 0 ? (
					<ul aria-label={t("family.children")} className="flex flex-col gap-3">
						{children.map((child) => (
							<li key={child.id} className="flex flex-wrap items-center gap-2">
								<span className="me-auto text-sm">{child.full_name}</span>
								<SetChildPasswordDialog
									child={child}
									onSuccess={(name) => setNotice(t("family.passwordSet", { name }))}
								/>
							</li>
						))}
					</ul>
				) : null}
				{children && children.length === 0 ? (
					<p className="text-sm text-muted-foreground">{t("family.noChildren")}</p>
				) : null}
				{notice ? (
					<Alert>
						<AlertDescription>{notice}</AlertDescription>
					</Alert>
				) : null}
				{adding ? (
					<AddChildForm
						onSuccess={(name) => {
							setAdding(false);
							setNotice(t("family.childAdded", { name }));
						}}
					/>
				) : (
					<Button
						variant="outline"
						onClick={() => {
							setNotice(null);
							setAdding(true);
						}}
					>
						{t("family.addChild")}
					</Button>
				)}
			</CardContent>
		</Card>
	);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pnpm exec vitest run src/features/identity/components/ChildrenCard.test.tsx`
Expected: PASS.

- [ ] **Step 5: Typecheck + commit**

```bash
pnpm exec tsc --noEmit
git add src/features/identity/components/ChildrenCard.tsx src/features/identity/components/ChildrenCard.test.tsx
git commit -m "feat(identity): ChildrenCard (list, add, set-password)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: InviteCard (+ clipboard test stub)

**Files:**
- Create: `src/features/identity/components/InviteCard.tsx`
- Create: `src/features/identity/components/InviteCard.test.tsx`
- Modify: `src/test/setup.ts` (add a `navigator.clipboard` stub)

**Interfaces:**
- Consumes: `useCreateInvite` (Task 2), `Invite` (Task 1), `@/ui` `Card`/`Button`/`Alert`.
- Produces: `InviteCard()` — the parent's "Invite a student" card; generate → display code + Copy + expiry; regenerate.

- [ ] **Step 1: Add a clipboard stub** — append to `src/test/setup.ts`:

```ts
// jsdom omits the async Clipboard API; provide a stub so copy buttons work.
if (!navigator.clipboard) {
	Object.defineProperty(navigator, "clipboard", {
		writable: true,
		value: { writeText: () => Promise.resolve() },
	});
}
```

- [ ] **Step 2: Write the failing test** — `InviteCard.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "jest-axe";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { identityApi } from "../api";
import { InviteCard } from "./InviteCard";

vi.mock("../api", async (orig) => {
	const actual = await orig<typeof import("../api")>();
	return { ...actual, identityApi: { createInvite: vi.fn() } };
});

function wrapper({ children }: { children: ReactNode }) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
	});
	return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

describe("InviteCard", () => {
	beforeEach(() => vi.clearAllMocks());

	it("generates and shows a code with its expiry", async () => {
		vi.mocked(identityApi.createInvite).mockResolvedValue({ code: "abc123", expires_at: "2026-06-19T00:00:00Z" });
		render(<InviteCard />, { wrapper });
		await userEvent.click(screen.getByRole("button", { name: /generate invite code/i }));
		await waitFor(() => expect(screen.getByText("abc123")).toBeInTheDocument());
		expect(screen.getByText(/expires in 24 hours/i)).toBeInTheDocument();
		expect(screen.getByText(/invalidates the previous one/i)).toBeInTheDocument();
	});

	it("copies the code to the clipboard", async () => {
		vi.mocked(identityApi.createInvite).mockResolvedValue({ code: "abc123", expires_at: "2026-06-19T00:00:00Z" });
		const writeText = vi.spyOn(navigator.clipboard, "writeText").mockResolvedValue();
		render(<InviteCard />, { wrapper });
		await userEvent.click(screen.getByRole("button", { name: /generate invite code/i }));
		await screen.findByText("abc123");
		await userEvent.click(screen.getByRole("button", { name: /copy/i }));
		expect(writeText).toHaveBeenCalledWith("abc123");
		await waitFor(() => expect(screen.getByText(/copied/i)).toBeInTheDocument());
	});

	it("has no axe violations", async () => {
		const { container } = render(<InviteCard />, { wrapper });
		expect(await axe(container)).toHaveNoViolations();
	});
});
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `pnpm exec vitest run src/features/identity/components/InviteCard.test.tsx`
Expected: FAIL — `InviteCard` does not exist.

- [ ] **Step 4: Implement `InviteCard.tsx`**:

```tsx
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Alert, AlertDescription, Button, Card, CardContent, CardHeader, CardTitle } from "@/ui";
import { useCreateInvite } from "../queries";
import type { Invite } from "../schemas";

export function InviteCard() {
	const { t } = useTranslation();
	const create = useCreateInvite();
	const [invite, setInvite] = useState<Invite | null>(null);
	const [copied, setCopied] = useState(false);

	async function generate() {
		const result = await create.mutateAsync();
		setCopied(false);
		setInvite(result);
	}

	// `code` is passed in from the render branch where `invite` is non-null, so
	// there is no null-guard branch to leave uncovered.
	async function copy(code: string) {
		await navigator.clipboard.writeText(code);
		setCopied(true);
	}

	return (
		<Card>
			<CardHeader>
				<CardTitle>{t("family.invite")}</CardTitle>
			</CardHeader>
			<CardContent className="flex flex-col gap-4">
				{invite ? (
					<div className="flex flex-col gap-2">
						<div className="flex flex-wrap items-center gap-2">
							<code className="me-auto rounded bg-muted px-2 py-1 text-sm">{invite.code}</code>
							<Button variant="outline" size="sm" onClick={() => copy(invite.code)}>
								{copied ? t("family.copied") : t("family.copy")}
							</Button>
						</div>
						<p className="text-sm text-muted-foreground">{t("family.expiresIn")}</p>
						<p className="text-sm text-muted-foreground">{t("family.regenerateNote")}</p>
					</div>
				) : null}
				<Button variant="outline" onClick={generate} disabled={create.isPending}>
					{invite ? t("family.generateNewCode") : t("family.generateCode")}
				</Button>
			</CardContent>
		</Card>
	);
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `pnpm exec vitest run src/features/identity/components/InviteCard.test.tsx`
Expected: PASS.

- [ ] **Step 6: Typecheck + commit**

```bash
pnpm exec tsc --noEmit
git add src/features/identity/components/InviteCard.tsx src/features/identity/components/InviteCard.test.tsx src/test/setup.ts
git commit -m "feat(identity): InviteCard (generate, copy, expiry)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: AcceptInviteCard

**Files:**
- Create: `src/features/identity/components/AcceptInviteCard.tsx`
- Create: `src/features/identity/components/AcceptInviteCard.test.tsx`

**Interfaces:**
- Consumes: `useAcceptInvite` (Task 2), `acceptInviteSchema`/`AcceptInviteInput` (Task 1), `parseApiError`, `@/ui`.
- Produces: `AcceptInviteCard()` — the student's "Link to a parent" card.

- [ ] **Step 1: Write the failing test** — `AcceptInviteCard.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AxiosError } from "axios";
import { axe } from "jest-axe";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { identityApi } from "../api";
import { AcceptInviteCard } from "./AcceptInviteCard";

vi.mock("../api", async (orig) => {
	const actual = await orig<typeof import("../api")>();
	return { ...actual, identityApi: { acceptInvite: vi.fn() } };
});

function wrapper({ children }: { children: ReactNode }) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
	});
	return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

describe("AcceptInviteCard", () => {
	beforeEach(() => vi.clearAllMocks());

	it("links to a parent and shows the confirmation", async () => {
		vi.mocked(identityApi.acceptInvite).mockResolvedValue({ parent_name: "Pat", linked: true });
		render(<AcceptInviteCard />, { wrapper });
		await userEvent.type(screen.getByLabelText(/invite code/i), "abc123");
		await userEvent.click(screen.getByRole("button", { name: /link/i }));
		await waitFor(() => expect(screen.getByText(/now linked to pat/i)).toBeInTheDocument());
		expect(identityApi.acceptInvite).toHaveBeenCalledWith({ code: "abc123" });
	});

	it("shows the field error for an invalid code", async () => {
		const err = new AxiosError("bad");
		err.response = { status: 400, data: { code: ["Invalid or expired invite code."] } } as never;
		vi.mocked(identityApi.acceptInvite).mockRejectedValue(err);
		render(<AcceptInviteCard />, { wrapper });
		await userEvent.type(screen.getByLabelText(/invite code/i), "nope");
		await userEvent.click(screen.getByRole("button", { name: /link/i }));
		await waitFor(() => expect(screen.getByText(/invalid or expired invite code/i)).toBeInTheDocument());
	});

	it("has no axe violations", async () => {
		const { container } = render(<AcceptInviteCard />, { wrapper });
		expect(await axe(container)).toHaveNoViolations();
	});
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pnpm exec vitest run src/features/identity/components/AcceptInviteCard.test.tsx`
Expected: FAIL — `AcceptInviteCard` does not exist.

- [ ] **Step 3: Implement `AcceptInviteCard.tsx`**:

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { useTranslation } from "react-i18next";
import { Alert, AlertDescription, Button, Card, CardContent, CardHeader, CardTitle, Field, Input } from "@/ui";
import { parseApiError } from "../api";
import { useAcceptInvite } from "../queries";
import { type AcceptInviteInput, acceptInviteSchema } from "../schemas";

export function AcceptInviteCard() {
	const { t } = useTranslation();
	const accept = useAcceptInvite();
	const [linkedTo, setLinkedTo] = useState<string | null>(null);
	const {
		register,
		handleSubmit,
		setError,
		reset,
		formState: { errors, isSubmitting },
	} = useForm<AcceptInviteInput>({
		resolver: zodResolver(acceptInviteSchema),
		defaultValues: { code: "" },
	});

	async function onSubmit(values: AcceptInviteInput) {
		try {
			const result = await accept.mutateAsync(values);
			reset();
			setLinkedTo(result.parent_name);
		} catch (error) {
			const parsed = parseApiError(error);
			if (parsed.fieldErrors.code) {
				setError("code", { message: parsed.fieldErrors.code });
			} else if (parsed.throttled) {
				setError("root.server", { message: t("family.throttled") });
			} else {
				setError("root.server", { message: parsed.message ?? t("family.genericError") });
			}
		}
	}

	return (
		<Card>
			<CardHeader>
				<CardTitle>{t("family.linkParent")}</CardTitle>
			</CardHeader>
			<CardContent>
				{linkedTo ? (
					<Alert>
						<AlertDescription>{t("family.linked", { name: linkedTo })}</AlertDescription>
					</Alert>
				) : (
					<form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-4" noValidate>
						<Field id="invite_code" label={t("family.inviteCode")} error={errors.code?.message}>
							<Input autoComplete="off" {...register("code")} />
						</Field>
						{errors.root?.server ? (
							<Alert variant="destructive">
								<AlertDescription>{errors.root.server.message}</AlertDescription>
							</Alert>
						) : null}
						<Button type="submit" disabled={isSubmitting}>
							{t("family.link")}
						</Button>
					</form>
				)}
			</CardContent>
		</Card>
	);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pnpm exec vitest run src/features/identity/components/AcceptInviteCard.test.tsx`
Expected: PASS.

- [ ] **Step 5: Typecheck + commit**

```bash
pnpm exec tsc --noEmit
git add src/features/identity/components/AcceptInviteCard.tsx src/features/identity/components/AcceptInviteCard.test.tsx
git commit -m "feat(identity): AcceptInviteCard (student links to a parent)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Family route (role-aware) + route tree + ISSUES.md

**Files:**
- Create: `src/routes/_authed/family.tsx`
- Create: `src/routes/_authed/family.test.tsx`
- Modify: `src/routeTree.gen.ts` (regenerated, not hand-edited)
- Modify (meta repo): `ISSUES.md`

**Interfaces:**
- Consumes: `useMe` (existing), `Me` (existing), `ChildrenCard` (Task 6), `InviteCard` (Task 7), `AcceptInviteCard` (Task 8).
- Produces: `Family({ me }: { me: Me })` (exported for testing, like `Home`) + `Route`.

- [ ] **Step 1: Write the failing test** — `src/routes/_authed/family.test.tsx` (mirrors `_authed/index.test.tsx`: render the exported component through a memory router, mock `../api` so the cards' queries don't hit the network):

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
import { Family } from "./family";

vi.mock("@/features/identity/api", async (orig) => {
	const actual = await orig<typeof import("@/features/identity/api")>();
	return { ...actual, identityApi: { listChildren: vi.fn(), createInvite: vi.fn(), acceptInvite: vi.fn() } };
});

function renderFamily(me: Me) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
	});
	const rootRoute = createRootRoute();
	const route = createRoute({ getParentRoute: () => rootRoute, path: "/", component: () => <Family me={me} /> });
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

const parent: Me = { id: 1, email: "p@b.com", full_name: "Pat", profiles: ["parent"] };
const student: Me = { id: 2, email: "s@b.com", full_name: "Sara", profiles: ["student"] };
const both: Me = { id: 3, email: "b@b.com", full_name: "Bo", profiles: ["parent", "student"] };
const teacher: Me = { id: 4, email: "t@b.com", full_name: "Tariq", profiles: ["teacher"] };

describe("Family route", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(identityApi.listChildren).mockResolvedValue([]);
	});

	it("shows children + invite cards for a parent and no accept card", async () => {
		renderFamily(parent);
		expect(await screen.findByText(/my children/i)).toBeInTheDocument();
		expect(screen.getByText(/invite a student/i)).toBeInTheDocument();
		expect(screen.queryByText(/link to a parent/i)).toBeNull();
	});

	it("shows the accept card for a student and no children card", async () => {
		renderFamily(student);
		expect(await screen.findByText(/link to a parent/i)).toBeInTheDocument();
		expect(screen.queryByText(/my children/i)).toBeNull();
	});

	it("shows all three cards for a parent-and-student", async () => {
		renderFamily(both);
		expect(await screen.findByText(/my children/i)).toBeInTheDocument();
		expect(screen.getByText(/invite a student/i)).toBeInTheDocument();
		expect(screen.getByText(/link to a parent/i)).toBeInTheDocument();
	});

	it("shows the muted note for a user who is neither", async () => {
		renderFamily(teacher);
		expect(await screen.findByText(/nothing here yet/i)).toBeInTheDocument();
	});
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pnpm exec vitest run src/routes/_authed/family.test.tsx`
Expected: FAIL — `./family` does not exist.

- [ ] **Step 3: Implement `src/routes/_authed/family.tsx`**:

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { AcceptInviteCard } from "@/features/identity/components/AcceptInviteCard";
import { ChildrenCard } from "@/features/identity/components/ChildrenCard";
import { InviteCard } from "@/features/identity/components/InviteCard";
import { useMe } from "@/features/identity/queries";
import type { Me } from "@/features/identity/schemas";

export function Family({ me }: { me: Me }) {
	const { t } = useTranslation();
	const isParent = me.profiles.includes("parent");
	const isStudent = me.profiles.includes("student");
	return (
		<div className="mx-auto flex w-full max-w-md flex-col gap-4">
			<h1 className="font-display text-2xl font-semibold">{t("family.title")}</h1>
			{isParent ? <ChildrenCard /> : null}
			{isParent ? <InviteCard /> : null}
			{isStudent ? <AcceptInviteCard /> : null}
			{!isParent && !isStudent ? (
				<p className="text-sm text-muted-foreground">{t("family.nothingHere")}</p>
			) : null}
		</div>
	);
}

export const Route = createFileRoute("/_authed/family")({
	component: function FamilyRoute() {
		const { data: me } = useMe();
		if (!me) return null;
		return <Family me={me} />;
	},
});
```

- [ ] **Step 4: Regenerate the route tree** — the generated tree must include `/family` before tsc runs (tsc runs before vite in `pnpm build`):

Run: `pnpm exec vite build`
Expected: build succeeds; `git diff src/routeTree.gen.ts` shows a new `/_authed/family` route wired in.

- [ ] **Step 5: Run the test + typecheck to verify they pass**

Run: `pnpm exec vitest run src/routes/_authed/family.test.tsx && pnpm exec tsc --noEmit`
Expected: PASS, no type errors.

- [ ] **Step 6: Log the child-login limitation in the meta repo's `ISSUES.md`** — add one line under the existing list:

```
- Children are created with a placeholder email (`child.<uuid>@placeholder.kaleem`) and no externally known login identity, so a child cannot actually sign in even after a parent sets a password. Needs a child-login design (own spec). Surfaced by the children+invites UI (Spec 3, 2026-06-18).
```

(Commit this in the meta repo on its own `feat/children-invites-ui` docs branch — see the closeout step. It is not part of the dashboard commit.)

- [ ] **Step 7: Commit the dashboard route**

```bash
git add src/routes/_authed/family.tsx src/routes/_authed/family.test.tsx src/routeTree.gen.ts
git commit -m "feat(identity): role-aware /family route (children, invites, accept)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: Full-suite green + lint (closeout gate)

**Files:** none (verification only).

- [ ] **Step 1: Run the entire dashboard test suite**

Run: `pnpm exec vitest run`
Expected: PASS — all suites, including the pre-existing shell/identity tests, green.

- [ ] **Step 2: Typecheck the whole project**

Run: `pnpm exec tsc --noEmit`
Expected: no errors.

- [ ] **Step 3: Lint + format check**

Run: `pnpm exec biome check src`
Expected: no errors. If biome reports formatting, run `pnpm exec biome check --write src`, re-run the suite, and amend the last commit.

- [ ] **Step 4: Confirm clean tree**

Run: `git status --short`
Expected: empty (everything committed).

---

## Self-Review (completed during planning)

**1. Spec coverage:**
- `/family` role-aware route → Task 9. ✅
- Family nav item + `requiresAny` → Task 3. ✅
- Children list / add (name only) / set-password → Tasks 4, 5, 6. ✅
- Invite generate / copy / expiry / regenerate → Task 7. ✅
- Student accept-invite + error mapping → Task 8. ✅
- schemas/api/queries data layer → Tasks 1, 2. ✅
- Loading/empty/error states → Task 6 (children), inherent in cards. ✅
- i18n en+ar + RTL, jest-axe per component → folded into each component task + Global Constraints. ✅
- Child-login limitation logged to ISSUES.md → Task 9 Step 6. ✅
- Home unchanged → no task touches it. ✅

**2. Placeholder scan:** No TBD/TODO; every code step shows complete code; every command has an expected result.

**3. Type consistency:** `Child.student_profile_id` is the id used by `setChildPassword(studentProfileId, …)` and `SetChildPasswordDialog`; `useSetChildPassword` mutates `{ studentProfileId, input }` consistently in Task 2's hook, Task 2's test, and Task 5's component. `useAddChild` invalidates `["children"]`+`["me"]` consistently in hook and test. `createInvite()` takes no args everywhere. `acceptInvite({ code })` consistent across api/hook/component/tests. Nav `requiresAny: ProfileType[]` consistent in `nav.ts`, its test, and `NAV_ITEMS`.

**Note for the executor (cross-task copy collision):** `family.addChild` ("Add child", the reveal button) and `family.addChildSubmit` ("Add child", the submit) share visible text. The ChildrenCard test (Task 6) relies on the reveal button and submit button never being in the DOM simultaneously (the form replaces the button on reveal). This is satisfied by the `ChildrenCard` implementation as written; do not change that conditional rendering without updating the Task 6 test selectors.
