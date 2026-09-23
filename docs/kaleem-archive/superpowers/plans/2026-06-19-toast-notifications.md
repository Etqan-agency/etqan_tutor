# Toast notifications — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add a radix-based toast system to the dashboard and move transient success confirmations from inline `<Alert>` banners to toasts.

**Architecture:** A module-level toast store + `<Toaster/>` (radix `Toast`) in `src/ui/toast.tsx`, mounted once in `main.tsx`. Migrate 4 components' success notices. Errors + page states stay inline. Spec: `docs/superpowers/specs/2026-06-19-toast-notifications-design.md`.

**Tech Stack:** React 19, radix-ui (installed), TanStack Router/Query, react-i18next, Tailwind v4, vitest + @testing-library/react + jest-axe.

## Global Constraints

- a11y/i18n/l10n baseline (ADR-0020): every UI string via `t(...)` with en+ar parity; RTL-safe; jest-axe clean per component.
- Follow `src/ui/` conventions: `cva` + `cn` + `data-slot`, functional components (see `src/ui/alert.tsx`).
- No new npm dependency (use `radix-ui`'s `Toast`). tsc + biome clean. All dashboard tests green.
- `toast()` is called from event/mutation handlers, never from a `useEffect` (StrictMode-safety; cf. the verify-email spin bug).
- Errors and page/route states are NOT toasted (spec scope decision).

---

### Task 1: Toast primitive, i18n keys, mount

**Files:**
- Create: `src/ui/toast.tsx`
- Create: `src/ui/toast.test.tsx`
- Modify: `src/ui/index.ts` (barrel export)
- Modify: `src/main.tsx` (mount `<Toaster/>`)
- Modify: `src/locales/en/common.json`, `src/locales/ar/common.json` (add `toast.*`)

**Interfaces:**
- Produces: `toast(input: { title?: string; description: string; variant?: "default" | "success" | "destructive" }): void` and `<Toaster/>`, both exported from `@/ui`. Test-only `__resetToasts()` exported from `./toast`.

- [ ] **Step 1: Write the failing test**

```tsx
// src/ui/toast.test.tsx
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "jest-axe";
import { act } from "react";
import { afterEach, expect, test } from "vitest";
import "@/lib/i18n";
import { DirectionProvider } from "@/lib/direction";
import { __resetToasts, Toaster, toast } from "./toast";

afterEach(() => {
	act(() => __resetToasts());
});

test("toast() shows a message in the Toaster", () => {
	render(<Toaster />);
	act(() => toast({ description: "Saved!" }));
	expect(screen.getByText("Saved!")).toBeInTheDocument();
});

test("close button dismisses the toast", async () => {
	const user = userEvent.setup();
	render(<Toaster />);
	act(() => toast({ description: "Saved!" }));
	await user.click(screen.getByLabelText("Dismiss"));
	expect(screen.queryByText("Saved!")).not.toBeInTheDocument();
});

test("toaster with a toast has no a11y violations", async () => {
	const { container } = render(
		<DirectionProvider>
			<Toaster />
		</DirectionProvider>,
	);
	act(() => toast({ description: "Saved!", variant: "success" }));
	expect(await axe(container)).toHaveNoViolations();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm vitest run src/ui/toast.test.tsx`
Expected: FAIL — `./toast` does not exist.

- [ ] **Step 3: Implement the primitive**

```tsx
// src/ui/toast.tsx
import { cva, type VariantProps } from "class-variance-authority";
import { X } from "lucide-react";
import { Toast as ToastPrimitive } from "radix-ui";
import { useSyncExternalStore } from "react";
import { useTranslation } from "react-i18next";
import { cn } from "@/lib/cn";

type ToastVariant = NonNullable<VariantProps<typeof toastVariants>["variant"]>;

type ToastItem = {
	id: number;
	title?: string;
	description: string;
	variant: ToastVariant;
};

let items: ToastItem[] = [];
let nextId = 0;
const listeners = new Set<() => void>();

function emit() {
	for (const listener of listeners) listener();
}

export function toast(input: {
	title?: string;
	description: string;
	variant?: ToastVariant;
}) {
	items = [...items, { id: nextId++, variant: "default", ...input }];
	emit();
}

function dismissToast(id: number) {
	items = items.filter((item) => item.id !== id);
	emit();
}

function subscribe(listener: () => void) {
	listeners.add(listener);
	return () => {
		listeners.delete(listener);
	};
}

function getSnapshot() {
	return items;
}

/** Test-only: clear the store between tests. */
export function __resetToasts() {
	items = [];
	nextId = 0;
	emit();
}

const toastVariants = cva(
	"pointer-events-auto flex w-full items-start gap-3 rounded-lg border bg-card px-4 py-3 text-sm shadow-lg",
	{
		variants: {
			variant: {
				default: "text-card-foreground",
				success: "text-card-foreground",
				destructive: "text-destructive",
			},
		},
		defaultVariants: { variant: "default" },
	},
);

export function Toaster() {
	const toasts = useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
	const { t, i18n } = useTranslation();

	return (
		<ToastPrimitive.Provider
			label={t("toast.regionLabel")}
			swipeDirection={i18n.dir() === "rtl" ? "left" : "right"}
		>
			{toasts.map((item) => (
				<ToastPrimitive.Root
					key={item.id}
					duration={5000}
					onOpenChange={(open) => {
						if (!open) dismissToast(item.id);
					}}
					className={cn(toastVariants({ variant: item.variant }))}
				>
					<div className="grid flex-1 gap-1">
						{item.title ? (
							<ToastPrimitive.Title className="font-medium">
								{item.title}
							</ToastPrimitive.Title>
						) : null}
						<ToastPrimitive.Description className="text-muted-foreground">
							{item.description}
						</ToastPrimitive.Description>
					</div>
					<ToastPrimitive.Close
						aria-label={t("toast.dismiss")}
						className="shrink-0 text-muted-foreground hover:text-foreground"
					>
						<X className="size-4" />
					</ToastPrimitive.Close>
				</ToastPrimitive.Root>
			))}
			<ToastPrimitive.Viewport className="fixed bottom-0 end-0 z-100 flex max-h-screen w-full flex-col gap-2 p-4 sm:max-w-sm" />
		</ToastPrimitive.Provider>
	);
}
```

- [ ] **Step 4: Add i18n keys**

In `src/locales/en/common.json`, add a top-level block:

```json
	"toast": {
		"dismiss": "Dismiss",
		"regionLabel": "Notifications"
	},
```

In `src/locales/ar/common.json`, add the matching block:

```json
	"toast": {
		"dismiss": "إغلاق",
		"regionLabel": "الإشعارات"
	},
```

(Place it consistently with sibling keys; mind trailing commas / valid JSON.)

- [ ] **Step 5: Barrel export + mount**

In `src/ui/index.ts` add:

```ts
export { Toaster, toast } from "./toast";
```

In `src/main.tsx`, import `Toaster` and render it inside `DirectionProvider` (after `RouterProvider`):

```tsx
import { Toaster } from "@/ui";
// …
				<QueryClientProvider client={queryClient}>
					<RouterProvider router={router} />
					<Toaster />
				</QueryClientProvider>
```

- [ ] **Step 6: Run tests + typecheck**

Run: `pnpm vitest run src/ui/toast.test.tsx && pnpm tsc --noEmit && pnpm biome check src/ui/toast.tsx src/main.tsx`
Expected: PASS / clean. (If biome wants import ordering changes, apply `pnpm biome check --write` on the touched files.)

- [ ] **Step 7: Commit**

```bash
git add src/ui/toast.tsx src/ui/toast.test.tsx src/ui/index.ts src/main.tsx src/locales/en/common.json src/locales/ar/common.json
git commit -m "feat(ui): radix-based toast system (Toaster + toast())"
```

---

### Task 2: Migrate form-success notices (ProfileEditForm, StudentPreferencesCard)

**Files:**
- Modify: `src/features/identity/components/ProfileEditForm.tsx` + its test
- Modify: `src/features/identity/components/StudentPreferencesCard.tsx` + its test

**Interfaces:** Consumes `toast` from `@/ui`.

- [ ] **Step 1: Update ProfileEditForm test**

In `ProfileEditForm.test.tsx`: render the form wrapped with `<Toaster/>` (import from `@/ui`) and, on a successful save, assert `await screen.findByText("Saved.")` appears (the toast). Remove/replace any assertion that looked for the inline success Alert. Keep the error-path test as-is (error still inline). Add `afterEach(() => act(() => __resetToasts()))` (import `__resetToasts` from `@/ui/toast`).

- [ ] **Step 2: Run it to confirm it fails**

Run: `pnpm vitest run src/features/identity/components/ProfileEditForm.test.tsx`
Expected: FAIL (no toast yet).

- [ ] **Step 3: Migrate ProfileEditForm**

- Import `toast` from `@/ui`.
- In `onSubmit`, after `await update.mutateAsync(values)` succeeds, call
  `toast({ description: t("auth.saved"), variant: "success" })`.
- Delete the `{isSubmitSuccessful && update.isSuccess ? (<Alert>…auth.saved…</Alert>) : null}` block and drop `isSubmitSuccessful` from the destructured `formState` if now unused.
- Keep the `errors.root?.server` Alert.

- [ ] **Step 4: Repeat for StudentPreferencesCard**

Update its test the same way (success → toast `prefs.saved`), then migrate: call `toast({ description: t("prefs.saved"), variant: "success" })` on save success, and remove the `const [saved, setSaved] = useState(false)` state, its `setSaved` calls, and the `{saved ? <Alert>…prefs.saved…</Alert> : null}` block. Keep the inline load/validation error Alerts.

- [ ] **Step 5: Run both tests + typecheck**

Run: `pnpm vitest run src/features/identity/components/ProfileEditForm.test.tsx src/features/identity/components/StudentPreferencesCard.test.tsx && pnpm tsc --noEmit`
Expected: PASS / clean.

- [ ] **Step 6: Commit**

```bash
git add src/features/identity/components/ProfileEditForm.tsx src/features/identity/components/ProfileEditForm.test.tsx src/features/identity/components/StudentPreferencesCard.tsx src/features/identity/components/StudentPreferencesCard.test.tsx
git commit -m "feat(ui): toast success on profile + preferences save"
```

---

### Task 3: Migrate notice-state notices (EmailAddresses, ChildrenCard)

**Files:**
- Modify: `src/features/identity/components/EmailAddresses.tsx` + its test
- Modify: `src/features/identity/components/ChildrenCard.tsx` + its test

**Interfaces:** Consumes `toast` from `@/ui`.

- [ ] **Step 1: Update EmailAddresses test**

Render with `<Toaster/>`; assert that after resending verification the toast `account.resent` text appears, and after adding an email the `account.verificationSent` text appears. Remove assertions tied to the inline `notice` Alert. Keep load-error (inline) test. `afterEach` resets toasts.

- [ ] **Step 2: Run it to confirm it fails**

Run: `pnpm vitest run src/features/identity/components/EmailAddresses.test.tsx`
Expected: FAIL.

- [ ] **Step 3: Migrate EmailAddresses**

- Import `toast` from `@/ui`. Remove `const [notice, setNotice] = useState<string | null>(null)`.
- resend `onSuccess`: `toast({ description: t("account.resent"), variant: "success" })`.
- AddEmailForm `onSuccess(email)`: `setAdding(false); toast({ description: t("account.verificationSent", { email }), variant: "success" })`.
- Delete the `{notice ? <Alert>…</Alert> : null}` block and the `setNotice(null)` call in the "add" button handler. Keep the `isError` load Alert.

- [ ] **Step 4: Repeat for ChildrenCard**

Update its test (child added → toast `family.childAdded`; password set → toast `family.passwordSet`), then migrate: remove `notice` state; `AddChildForm onSuccess(name)` → `setAdding(false); toast({ description: t("family.childAdded", { name }), variant: "success" })`; `SetChildPasswordDialog onSuccess(name)` → `toast({ description: t("family.passwordSet", { name }), variant: "success" })`; delete the notice Alert block. Keep the `isError` load Alert. (InviteCard is NOT changed — its "Copied" is a button-label affordance, not a banner.)

- [ ] **Step 5: Full dashboard gate**

Run: `pnpm vitest run && pnpm tsc --noEmit && pnpm biome check src`
Expected: all green/clean.

- [ ] **Step 6: Commit**

```bash
git add src/features/identity/components/EmailAddresses.tsx src/features/identity/components/EmailAddresses.test.tsx src/features/identity/components/ChildrenCard.tsx src/features/identity/components/ChildrenCard.test.tsx
git commit -m "feat(ui): toast success on email + children actions"
```
