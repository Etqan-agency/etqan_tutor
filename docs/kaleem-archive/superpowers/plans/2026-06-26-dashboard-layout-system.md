# Dashboard Layout System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Replace ad-hoc per-page width wrappers with one shell-owned, token-driven content container + a standard page-header, eliminating the inconsistent-width / right-drift layout problem.

**Architecture:** Add a named content-width scale via Tailwind v4 `@theme` in the dashboard, a `PageContainer` (centered, token width, page padding, vertical stack) and a `PageHeader` (`<h1>` + optional description). Every authed page renders through them; `ModulePlaceholder` and `AuthLayout` are rebuilt on them. Presentational only — no data/route/logic changes.

**Tech Stack:** React 19, TanStack Router, Tailwind v4 (`@theme`), Vitest + Testing Library + jest-axe, Biome.

## Global Constraints

- 100% line + branch coverage (machine-enforced). Every new file fully covered.
- a11y/i18n/RTL baseline: components must pass `jest-axe`; copy comes from callers (already-translated strings) or i18n keys; no hardcoded user-facing strings in shared UI.
- No cross-feature imports. Shared UI lives in `src/ui/`.
- Width/padding expressed as tokens/utilities, never magic px.
- Token scale (verbatim): `--container-page: 48rem`, `--container-narrow: 28rem`, `--container-wide: 72rem`. Page padding: `px-4 sm:px-6`. Vertical stack: `flex flex-col gap-6`. Nav link min height: `min-h-11`.

---

### Task 1: Layout width tokens (`@theme`)

**Files:**
- Modify: `dashboard/src/index.css`

**Interfaces:**
- Produces: Tailwind utilities `max-w-page` (48rem), `max-w-narrow` (28rem), `max-w-wide` (72rem).

- [ ] **Step 1:** Add a `@theme { --container-page: 48rem; --container-narrow: 28rem; --container-wide: 72rem; }` block to `src/index.css` (after the tokens imports).
- [ ] **Step 2:** Verify utilities resolve — covered indirectly by Task 2's class assertions (Tailwind generates `max-w-*` from `--container-*`). No standalone test (CSS-only).
- [ ] **Step 3:** Commit: `style(dashboard): add content-width @theme tokens`.

> Note: CSS `@theme` is not unit-testable in jsdom; its correctness is asserted via PageContainer applying `max-w-page` etc. and verified visually in the after-shots.

---

### Task 2: `PageContainer`

**Files:**
- Create: `dashboard/src/ui/page-container.tsx`
- Test: `dashboard/src/ui/page-container.test.tsx`
- Modify: `dashboard/src/ui/index.ts` (export)

**Interfaces:**
- Produces: `PageContainer({ width?: "page" | "narrow" | "wide", className?, children }): JSX` — `data-slot="page-container"`, classes `mx-auto w-full px-4 sm:px-6 flex flex-col gap-6` + `max-w-{width}` (default `page`).

- [ ] **Step 1: Failing test** (`page-container.test.tsx`):

```tsx
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { PageContainer } from "./page-container";

const slot = (c: HTMLElement) => c.querySelector('[data-slot="page-container"]')!;

describe("PageContainer", () => {
  it("renders children", () => {
    render(<PageContainer>hi</PageContainer>);
    expect(screen.getByText("hi")).toBeInTheDocument();
  });
  it("defaults to the page width + centers + has page padding", () => {
    const { container } = render(<PageContainer>x</PageContainer>);
    expect(slot(container)).toHaveClass("max-w-page", "mx-auto", "px-4");
  });
  it("applies narrow and wide widths", () => {
    const { container: a } = render(<PageContainer width="narrow">x</PageContainer>);
    expect(slot(a)).toHaveClass("max-w-narrow");
    const { container: b } = render(<PageContainer width="wide">x</PageContainer>);
    expect(slot(b)).toHaveClass("max-w-wide");
  });
  it("merges a custom className", () => {
    const { container } = render(<PageContainer className="extra">x</PageContainer>);
    expect(slot(container)).toHaveClass("extra");
  });
});
```

- [ ] **Step 2:** Run `pnpm test -- page-container` → FAIL (module not found).
- [ ] **Step 3: Implement** (`page-container.tsx`):

```tsx
import type * as React from "react";
import { cn } from "@/lib/cn";

const WIDTHS = {
  page: "max-w-page",
  narrow: "max-w-narrow",
  wide: "max-w-wide",
} as const;

export function PageContainer({
  width = "page",
  className,
  children,
}: {
  width?: keyof typeof WIDTHS;
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <div
      data-slot="page-container"
      className={cn("mx-auto flex w-full flex-col gap-6 px-4 sm:px-6", WIDTHS[width], className)}
    >
      {children}
    </div>
  );
}
```

- [ ] **Step 4:** Run `pnpm test -- page-container` → PASS. Add export to `src/ui/index.ts`.
- [ ] **Step 5:** Commit: `feat(dashboard): add PageContainer layout primitive`.

---

### Task 3: `PageHeader`

**Files:**
- Create: `dashboard/src/ui/page-header.tsx`
- Test: `dashboard/src/ui/page-header.test.tsx`
- Modify: `dashboard/src/ui/index.ts`

**Interfaces:**
- Produces: `PageHeader({ title: string, description?: string }): JSX` — renders `<h1 class="font-display text-2xl font-semibold">` + optional muted `<p>`.

- [ ] **Step 1: Failing test:**

```tsx
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { PageHeader } from "./page-header";

describe("PageHeader", () => {
  it("renders the title as an h1", () => {
    render(<PageHeader title="Account" />);
    expect(screen.getByRole("heading", { level: 1, name: "Account" })).toBeInTheDocument();
  });
  it("renders a description when given", () => {
    render(<PageHeader title="Billing" description="Your plan." />);
    expect(screen.getByText("Your plan.")).toBeInTheDocument();
  });
  it("omits the description when absent", () => {
    const { container } = render(<PageHeader title="Account" />);
    expect(container.querySelector("p")).toBeNull();
  });
});
```

- [ ] **Step 2:** Run → FAIL. **Step 3: Implement:**

```tsx
export function PageHeader({ title, description }: { title: string; description?: string }) {
  return (
    <header className="flex flex-col gap-1">
      <h1 className="font-display text-2xl font-semibold">{title}</h1>
      {description ? <p className="text-sm text-muted-foreground">{description}</p> : null}
    </header>
  );
}
```

- [ ] **Step 4:** Run → PASS. Export from `index.ts`. **Step 5:** Commit `feat(dashboard): add PageHeader`.

---

### Task 4: Rebuild `ModulePlaceholder` on the new primitives

**Files:**
- Modify: `dashboard/src/ui/module-placeholder.tsx`
- Test: `dashboard/src/ui/module-placeholder.test.tsx` (existing — extend)

**Interfaces:**
- Consumes: `PageContainer`, `PageHeader`.

- [ ] **Step 1:** Extend the existing test to assert it renders inside a `PageContainer`:

```tsx
it("renders inside a page container", () => {
  const { container } = render(
    <ModulePlaceholder icon={BookOpen} title="Curriculum" description="Your lessons." note="Coming soon" />,
  );
  expect(container.querySelector('[data-slot="page-container"]')).toHaveClass("max-w-page");
});
```

- [ ] **Step 2:** Run → FAIL. **Step 3:** Replace the inner `mx-auto max-w-3xl` wrapper with `<PageContainer>` and the manual header block with `<PageHeader title={title} description={description} />`. Keep the Card + empty-state unchanged. (Existing heading/description/note + axe tests must still pass.)
- [ ] **Step 4:** Run `pnpm test -- module-placeholder` → PASS. **Step 5:** Commit `refactor(dashboard): rebuild ModulePlaceholder on PageContainer/PageHeader`.

---

### Task 5: Migrate the authed pages

**Files:** Modify `dashboard/src/routes/_authed/index.tsx`, `account.tsx`, `family.tsx`, `availability.tsx`. Update the colocated tests (`index.test.tsx`, `account.test.tsx`, `family.test.tsx`, `availability.test.tsx`).

**Interfaces:** Consumes `PageContainer`, `PageHeader`.

- [ ] **Step 1:** For each page, write/adjust a test asserting it renders inside `[data-slot="page-container"]`, and for Account assert an `<h1>` now exists (`getByRole("heading", { level: 1 })`). Example (account):

```tsx
it("renders inside a page container with a heading", () => {
  // ...render <Account me={...} /> with i18n + query providers as the existing test does
  expect(screen.getByRole("heading", { level: 1 })).toBeInTheDocument();
  expect(container.querySelector('[data-slot="page-container"]')).toHaveClass("max-w-page");
});
```

- [ ] **Step 2:** Run → FAIL (Account has no h1; pages lack the slot). **Step 3:** Edit pages:
  - `index.tsx` (Home): replace `<div className="mx-auto flex w-full max-w-2xl flex-col gap-6">` with `<PageContainer>`; keep the greeting `<h1>` (or swap to `<PageHeader title={greeting}/>`).
  - `account.tsx`: replace `<div className="mx-auto flex w-full max-w-md flex-col gap-4">` with `<PageContainer>` and add `<PageHeader title={t("auth.account")} />` as the first child.
  - `family.tsx`: replace `<div className="mx-auto flex w-full max-w-md flex-col gap-4">` with `<PageContainer>`; convert the bare `<h1>` to `<PageHeader title={t("family.title")} />`.
  - `availability.tsx`: replace `<div className="mx-auto flex w-full max-w-2xl flex-col gap-4 p-4">` with `<PageContainer width="wide">` (removes the double `p-4`).
- [ ] **Step 4:** Run `pnpm test -- routes/_authed` → PASS. **Step 5:** Commit `refactor(dashboard): route pages through PageContainer + PageHeader`.

---

### Task 6: Shell `<main>` + sidebar touch targets

**Files:** Modify `dashboard/src/features/shell/AppShell.tsx`, `AppSidebar.tsx`. Tests: `AppShell.test.tsx`, `AppSidebar.test.tsx`.

- [ ] **Step 1:** In `AppSidebar.test.tsx`, assert links carry `min-h-11`:

```tsx
// after rendering the sidebar with items, for a link:
expect(screen.getByRole("link", { name: /.../ })).toHaveClass("min-h-11");
```

- [ ] **Step 2:** Run → FAIL. **Step 3:** Add `min-h-11` to the `Link` className in `AppSidebar.tsx`. Change `AppShell.tsx` `<main className="min-w-0 p-4">` to `<main className="min-w-0 py-6">` (horizontal padding now owned by `PageContainer`; keep the sign-out `Alert` — wrap it so it still aligns, e.g. inside a `PageContainer` or leave full-width above children). Adjust `AppShell.test.tsx` only if a class assertion breaks (behavioural tests should still pass).
- [ ] **Step 4:** Run `pnpm test -- shell` → PASS. **Step 5:** Commit `refactor(dashboard): shell owns vertical rhythm; 44px nav targets`.

---

### Task 7: Align `AuthLayout` to the narrow token

**Files:** Modify `dashboard/src/ui/auth-layout.tsx`. Test: `auth-layout.test.tsx` (existing).

- [ ] **Step 1:** Add/adjust a test asserting the auth main uses `max-w-narrow`. **Step 2:** Run → FAIL. **Step 3:** Replace `max-w-sm` on the auth `<main>` with `max-w-narrow`. **Step 4:** Run → PASS. **Step 5:** Commit `style(dashboard): align AuthLayout to narrow content token`.

---

### Task 8: Full suite + lint gate

- [ ] **Step 1:** `pnpm test` (vitest, all) → PASS, 100% coverage. **Step 2:** `pnpm exec tsc --noEmit` → clean. **Step 3:** `pnpm exec biome check src` → clean (fix with `biome check --write` if needed). **Step 4:** Commit any formatting. (No app-code commit if clean.)

---

## Self-Review

- **Spec coverage:** tokens (T1) ✓, PageContainer (T2) ✓, PageHeader (T3) ✓, ModulePlaceholder rebuild (T4) ✓, page migration incl. double-padding + Account h1 (T5) ✓, shell main + nav targets (T6) ✓, AuthLayout (T7) ✓, tests/coverage/lint (T8) ✓. Visual verification is a post-implementation step in the spec (not a code task).
- **Placeholder scan:** none — all steps carry real code/commands.
- **Type consistency:** `width` union `"page" | "narrow" | "wide"` and `data-slot="page-container"` used consistently across T2/T4/T5; `max-w-{page,narrow,wide}` match T1 token names.
