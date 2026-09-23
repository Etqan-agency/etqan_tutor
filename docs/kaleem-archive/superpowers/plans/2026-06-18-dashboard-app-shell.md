# Dashboard App Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the authenticated dashboard a persistent app shell — a topbar + role-aware sidebar — that wraps every `/_authed/*` page, replacing the ad-hoc per-page nav.

**Architecture:** A new `src/features/shell/` module of small presentational components (nav config, `UserMenu`, `AppSidebar`, `AppTopbar`) composed by `AppShell`, which is installed as the component of the existing `_authed` layout route so it wraps the authed `<Outlet/>`. Presentational pieces take plain props (unit-tested in isolation); `AppShell` wires `useMe`/`useLogout`/`useNavigate`. No new dependencies — `radix-ui`, `lucide-react`, i18n, and the `ui` kit already exist.

**Tech Stack:** React 19, TanStack Router + Query, `radix-ui` (DropdownMenu), `lucide-react`, react-i18next, Tailwind + shadcn tokens, Vitest + Testing Library + jest-axe.

## Global Constraints

- All work is in the **`dashboard` submodule** (`/home/abdulkhalek/Projects/kaleem/dashboard`). Branch `feat/app-shell` off `main` (submodules use feat→main).
- **TDD**: failing test first, then minimal code. Repo gate is **100% line+branch coverage** — every branch of new components must be exercised.
- **No new npm dependency.** `radix-ui` (^1.5.0), `lucide-react`, `@testing-library/user-event`, `jest-axe` are already installed. Import radix as `import { DropdownMenu } from "radix-ui";` (matching `src/ui/label.tsx`).
- **i18n**: every user-visible string goes through `react-i18next`; add keys to BOTH `src/locales/en/common.json` and `src/locales/ar/common.json`. Reuse existing keys where they exist (`auth.home`, `auth.profile`, `auth.signOut`).
- **a11y/RTL (ADR-0020)**: keyboard-navigable, visible focus, `aria-current="page"` on the active link, RTL via existing `lib/direction` + logical CSS (use `ms-`/`me-`/`start`/`end`, never `ml-`/`left`). Every new component has a `jest-axe` test asserting `toHaveNoViolations()`.
- **No in-app footer** (per spec). Do not render a `<footer>`/`contentinfo` in the shell.
- Run checks from the dashboard repo root: tests `pnpm test` (or `pnpm exec vitest run <file>` for one file), lint `pnpm exec biome check .`, types `pnpm exec tsc --noEmit`. (If the host lacks `node_modules`, run the same commands inside the dashboard container — no reseed is needed since no dependency is added.)
- **No `--no-verify`.** Commit footer on every commit: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Do NOT push or open a PR (the controller handles git-flow at the end).

## File Structure

- `src/features/shell/nav.ts` — `NavItem` type, `NAV_ITEMS`, `visibleNavItems()`.
- `src/features/shell/UserMenu.tsx` — radix dropdown: Profile + Sign out.
- `src/features/shell/AppSidebar.tsx` — renders the nav (rail + drawer body).
- `src/features/shell/AppTopbar.tsx` — brand, mobile hamburger, toggles, `UserMenu`.
- `src/features/shell/AppShell.tsx` — grid frame; owns drawer state; wires hooks.
- `src/features/shell/index.ts` — barrel export.
- `src/routes/_authed.tsx` — change component from `Outlet` to `AppShell`-wrapped.
- `src/routes/_authed/index.tsx` + `.test.tsx` — drop the inline Profile/Sign-out buttons.
- `src/routes/_authed/profile.tsx` — drop the inline "Home" button.
- `src/locales/{en,ar}/common.json` — add `nav.*` keys.
- `src/test/setup.ts` — add jsdom stubs for radix overlays (Task 2).

Branch prep (run once):
```bash
cd /home/abdulkhalek/Projects/kaleem/dashboard
git checkout main && git pull --ff-only
git checkout -b feat/app-shell
```

---

### Task 1: Nav config + i18n keys

**Files:**
- Create: `src/features/shell/nav.ts`
- Modify: `src/locales/en/common.json`, `src/locales/ar/common.json`
- Test: `src/features/shell/nav.test.ts`

**Interfaces:**
- Produces:
  - `type NavItem = { to: string; labelKey: string; icon: LucideIcon; requires?: ProfileType }`
  - `const NAV_ITEMS: NavItem[]` — ship-time: Home (`/`, `auth.home`), Profile (`/profile`, `auth.profile`); neither has `requires`.
  - `function visibleNavItems(items: NavItem[], profiles: readonly ProfileType[]): NavItem[]` — keeps an item when it has no `requires` or `profiles` includes it.

- [ ] **Step 1: Write the failing test**

Create `src/features/shell/nav.test.ts`:

```ts
import { Home, User } from "lucide-react";
import { describe, expect, it } from "vitest";
import type { ProfileType } from "@/features/identity/schemas";
import { type NavItem, NAV_ITEMS, visibleNavItems } from "./nav";

const items: NavItem[] = [
	{ to: "/", labelKey: "auth.home", icon: Home },
	{ to: "/children", labelKey: "nav.children", icon: User, requires: "parent" },
];

describe("visibleNavItems", () => {
	it("always keeps items with no `requires`", () => {
		const result = visibleNavItems(items, [] as ProfileType[]);
		expect(result.map((i) => i.to)).toEqual(["/"]);
	});

	it("keeps a gated item only when the profile matches", () => {
		expect(visibleNavItems(items, ["parent"]).map((i) => i.to)).toEqual([
			"/",
			"/children",
		]);
		expect(visibleNavItems(items, ["student"]).map((i) => i.to)).toEqual(["/"]);
	});
});

describe("NAV_ITEMS", () => {
	it("ships Home and Profile, both ungated", () => {
		expect(NAV_ITEMS.map((i) => i.to)).toEqual(["/", "/profile"]);
		expect(NAV_ITEMS.every((i) => i.requires === undefined)).toBe(true);
	});
});
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `pnpm exec vitest run src/features/shell/nav.test.ts`
Expected: FAIL (cannot resolve `./nav`).

- [ ] **Step 3: Create the nav config**

Create `src/features/shell/nav.ts`:

```ts
import type { LucideIcon } from "lucide-react";
import { Home, User } from "lucide-react";
import type { ProfileType } from "@/features/identity/schemas";

export type NavItem = {
	to: string;
	labelKey: string;
	icon: LucideIcon;
	requires?: ProfileType;
};

export const NAV_ITEMS: NavItem[] = [
	{ to: "/", labelKey: "auth.home", icon: Home },
	{ to: "/profile", labelKey: "auth.profile", icon: User },
];

export function visibleNavItems(
	items: NavItem[],
	profiles: readonly ProfileType[],
): NavItem[] {
	return items.filter((i) => !i.requires || profiles.includes(i.requires));
}
```

- [ ] **Step 4: Add the i18n keys**

In `src/locales/en/common.json`, add a top-level `"nav"` block (sibling of `"theme"`):

```json
	"nav": {
		"primary": "Main navigation",
		"openMenu": "Open menu",
		"closeMenu": "Close menu",
		"account": "Account menu"
	}
```

In `src/locales/ar/common.json`, add the matching block:

```json
	"nav": {
		"primary": "التنقل الرئيسي",
		"openMenu": "افتح القائمة",
		"closeMenu": "أغلق القائمة",
		"account": "قائمة الحساب"
	}
```

(Place each as a sibling of the existing `theme`/`locale` blocks; mind the trailing-comma JSON syntax.)

- [ ] **Step 5: Run the test — expect PASS**

Run: `pnpm exec vitest run src/features/shell/nav.test.ts`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add src/features/shell/nav.ts src/features/shell/nav.test.ts src/locales/en/common.json src/locales/ar/common.json
PIP_CONFIG_FILE=/dev/null git commit -m "feat(shell): nav config + i18n keys

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: UserMenu (radix dropdown) + jsdom overlay stubs

**Files:**
- Modify: `src/test/setup.ts`
- Create: `src/features/shell/UserMenu.tsx`
- Test: `src/features/shell/UserMenu.test.tsx`

**Interfaces:**
- Consumes: existing `Button` from `@/ui`.
- Produces: `function UserMenu({ userName, onSignOut }: { userName: string; onSignOut: () => void })` — a dropdown whose trigger shows `userName`; items are **Profile** (a `Link` to `/profile`) and **Sign out** (calls `onSignOut`).

- [ ] **Step 1: Add jsdom stubs for radix overlays**

radix overlays need pointer/observer APIs jsdom lacks. Append to `src/test/setup.ts` (after the `matchMedia` stub):

```ts
// radix overlays (DropdownMenu, etc.) need these APIs that jsdom omits.
class ResizeObserverStub {
	observe() {}
	unobserve() {}
	disconnect() {}
}
window.ResizeObserver ??= ResizeObserverStub;
Element.prototype.scrollIntoView ??= () => {};
Element.prototype.hasPointerCapture ??= () => false;
Element.prototype.setPointerCapture ??= () => {};
Element.prototype.releasePointerCapture ??= () => {};
```

- [ ] **Step 2: Write the failing test**

Create `src/features/shell/UserMenu.test.tsx`:

```tsx
import {
	createMemoryHistory,
	createRootRoute,
	createRoute,
	createRouter,
	RouterProvider,
} from "@tanstack/react-router";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "jest-axe";
import { describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { UserMenu } from "./UserMenu";

function renderMenu(onSignOut = () => {}) {
	const rootRoute = createRootRoute({
		component: () => <UserMenu userName="Sara" onSignOut={onSignOut} />,
	});
	const profileRoute = createRoute({
		getParentRoute: () => rootRoute,
		path: "/profile",
		component: () => null,
	});
	const router = createRouter({
		routeTree: rootRoute.addChildren([profileRoute]),
		history: createMemoryHistory({ initialEntries: ["/"] }),
	});
	return render(<RouterProvider router={router} />);
}

describe("UserMenu", () => {
	it("shows the user name on the trigger", () => {
		renderMenu();
		expect(screen.getByRole("button", { name: /account menu/i })).toHaveTextContent(
			"Sara",
		);
	});

	it("opens to Profile + Sign out and fires sign out", async () => {
		const onSignOut = vi.fn();
		renderMenu(onSignOut);
		await userEvent.click(screen.getByRole("button", { name: /account menu/i }));
		expect(
			screen.getByRole("menuitem", { name: /profile/i }),
		).toBeInTheDocument();
		await userEvent.click(screen.getByRole("menuitem", { name: /sign out/i }));
		expect(onSignOut).toHaveBeenCalledOnce();
	});

	it("has no axe violations when open", async () => {
		const { container, baseElement } = renderMenu();
		await userEvent.click(screen.getByRole("button", { name: /account menu/i }));
		expect(await axe(baseElement)).toHaveNoViolations();
		expect(container).toBeTruthy();
	});
});
```

- [ ] **Step 3: Run it and confirm it fails**

Run: `pnpm exec vitest run src/features/shell/UserMenu.test.tsx`
Expected: FAIL (cannot resolve `./UserMenu`).

- [ ] **Step 4: Implement UserMenu**

Create `src/features/shell/UserMenu.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { ChevronDown, LogOut, User } from "lucide-react";
import { DropdownMenu } from "radix-ui";
import { useTranslation } from "react-i18next";
import { Button } from "@/ui";

const itemClass =
	"flex w-full cursor-pointer items-center gap-2 rounded-sm px-2 py-1.5 text-sm outline-none focus:bg-accent focus:text-accent-foreground";

export function UserMenu({
	userName,
	onSignOut,
}: {
	userName: string;
	onSignOut: () => void;
}) {
	const { t } = useTranslation();
	return (
		<DropdownMenu.Root>
			<DropdownMenu.Trigger asChild>
				<Button variant="outline" size="sm" aria-label={t("nav.account")}>
					<User className="size-4" />
					<span className="max-w-[12ch] truncate">{userName}</span>
					<ChevronDown className="size-4" />
				</Button>
			</DropdownMenu.Trigger>
			<DropdownMenu.Portal>
				<DropdownMenu.Content
					align="end"
					sideOffset={6}
					className="z-50 min-w-44 rounded-md border border-border bg-popover p-1 text-popover-foreground shadow-md"
				>
					<DropdownMenu.Item asChild>
						<Link to="/profile" className={itemClass}>
							<User className="size-4" />
							{t("auth.profile")}
						</Link>
					</DropdownMenu.Item>
					<DropdownMenu.Item className={itemClass} onSelect={onSignOut}>
						<LogOut className="size-4" />
						{t("auth.signOut")}
					</DropdownMenu.Item>
				</DropdownMenu.Content>
			</DropdownMenu.Portal>
		</DropdownMenu.Root>
	);
}
```

- [ ] **Step 5: Run the test — expect PASS**

Run: `pnpm exec vitest run src/features/shell/UserMenu.test.tsx`
Expected: PASS (3 tests). If the menu fails to open, confirm the Step 1 stubs were saved.

- [ ] **Step 6: Commit**

```bash
git add src/test/setup.ts src/features/shell/UserMenu.tsx src/features/shell/UserMenu.test.tsx
PIP_CONFIG_FILE=/dev/null git commit -m "feat(shell): UserMenu dropdown (profile + sign out)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: AppSidebar

**Files:**
- Create: `src/features/shell/AppSidebar.tsx`
- Test: `src/features/shell/AppSidebar.test.tsx`

**Interfaces:**
- Consumes: `NAV_ITEMS`/`NavItem` from `./nav`.
- Produces: `function AppSidebar({ items, onNavigate }: { items: NavItem[]; onNavigate?: () => void })` — a `<nav aria-label={t("nav.primary")}>` listing each item as a TanStack `Link`; the active link carries `aria-current="page"`; clicking a link calls `onNavigate`.

- [ ] **Step 1: Write the failing test**

Create `src/features/shell/AppSidebar.test.tsx`:

```tsx
import {
	createMemoryHistory,
	createRootRoute,
	createRoute,
	createRouter,
	RouterProvider,
} from "@tanstack/react-router";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "jest-axe";
import { describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { AppSidebar } from "./AppSidebar";
import { NAV_ITEMS } from "./nav";

function renderSidebar(onNavigate = () => {}, initial = "/") {
	const rootRoute = createRootRoute({
		component: () => <AppSidebar items={NAV_ITEMS} onNavigate={onNavigate} />,
	});
	const idx = createRoute({ getParentRoute: () => rootRoute, path: "/", component: () => null });
	const profile = createRoute({ getParentRoute: () => rootRoute, path: "/profile", component: () => null });
	const router = createRouter({
		routeTree: rootRoute.addChildren([idx, profile]),
		history: createMemoryHistory({ initialEntries: [initial] }),
	});
	return render(<RouterProvider router={router} />);
}

describe("AppSidebar", () => {
	it("marks the current route active and others not", async () => {
		renderSidebar(() => {}, "/");
		const home = await screen.findByRole("link", { name: /home/i });
		expect(home).toHaveAttribute("aria-current", "page");
		expect(screen.getByRole("link", { name: /profile/i })).not.toHaveAttribute(
			"aria-current",
		);
	});

	it("calls onNavigate when a link is clicked", async () => {
		const onNavigate = vi.fn();
		renderSidebar(onNavigate, "/");
		await userEvent.click(screen.getByRole("link", { name: /profile/i }));
		expect(onNavigate).toHaveBeenCalled();
	});

	it("labels the nav and has no axe violations", async () => {
		const { container } = renderSidebar();
		expect(
			screen.getByRole("navigation", { name: /main navigation/i }),
		).toBeInTheDocument();
		expect(await axe(container)).toHaveNoViolations();
	});
});
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `pnpm exec vitest run src/features/shell/AppSidebar.test.tsx`
Expected: FAIL (cannot resolve `./AppSidebar`).

- [ ] **Step 3: Implement AppSidebar**

Create `src/features/shell/AppSidebar.tsx`:

```tsx
import { Link } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import type { NavItem } from "./nav";

export function AppSidebar({
	items,
	onNavigate,
}: {
	items: NavItem[];
	onNavigate?: () => void;
}) {
	const { t } = useTranslation();
	return (
		<nav aria-label={t("nav.primary")} className="flex flex-col gap-1 p-3">
			{items.map((item) => {
				const Icon = item.icon;
				return (
					<Link
						key={item.to}
						to={item.to}
						activeOptions={{ exact: item.to === "/" }}
						activeProps={{ "aria-current": "page" }}
						onClick={onNavigate}
						className="flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium text-muted-foreground hover:bg-accent hover:text-accent-foreground aria-[current=page]:bg-accent aria-[current=page]:text-accent-foreground"
					>
						<Icon className="size-4 shrink-0" />
						{t(item.labelKey)}
					</Link>
				);
			})}
		</nav>
	);
}
```

- [ ] **Step 4: Run the test — expect PASS**

Run: `pnpm exec vitest run src/features/shell/AppSidebar.test.tsx`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/features/shell/AppSidebar.tsx src/features/shell/AppSidebar.test.tsx
PIP_CONFIG_FILE=/dev/null git commit -m "feat(shell): AppSidebar nav with active state

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: AppTopbar

**Files:**
- Create: `src/features/shell/AppTopbar.tsx`
- Test: `src/features/shell/AppTopbar.test.tsx`

**Interfaces:**
- Consumes: `LocaleToggle`, `ThemeToggle`, `Button` from `@/ui`; `UserMenu` from `./UserMenu`.
- Produces: `function AppTopbar({ userName, onSignOut, onOpenMenu }: { userName: string; onSignOut: () => void; onOpenMenu: () => void })` — brand wordmark; a hamburger button (hidden ≥ `md`) labelled `nav.openMenu` that calls `onOpenMenu`; the locale + theme toggles; and `UserMenu`.

- [ ] **Step 1: Write the failing test**

Create `src/features/shell/AppTopbar.test.tsx`:

```tsx
import {
	createMemoryHistory,
	createRootRoute,
	createRoute,
	createRouter,
	RouterProvider,
} from "@tanstack/react-router";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "jest-axe";
import { describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { ThemeProvider } from "@/lib/theme";
import { AppTopbar } from "./AppTopbar";

function renderTopbar(onOpenMenu = () => {}) {
	const rootRoute = createRootRoute({
		component: () => (
			<AppTopbar userName="Sara" onSignOut={() => {}} onOpenMenu={onOpenMenu} />
		),
	});
	const profile = createRoute({ getParentRoute: () => rootRoute, path: "/profile", component: () => null });
	const router = createRouter({
		routeTree: rootRoute.addChildren([profile]),
		history: createMemoryHistory({ initialEntries: ["/"] }),
	});
	return render(
		<ThemeProvider>
			<RouterProvider router={router} />
		</ThemeProvider>,
	);
}

describe("AppTopbar", () => {
	it("renders the brand, toggles, and the user menu", () => {
		renderTopbar();
		expect(screen.getByText(/kaleem/i)).toBeInTheDocument();
		expect(screen.getByRole("button", { name: /toggle theme/i })).toBeInTheDocument();
		expect(screen.getByRole("button", { name: /switch language/i })).toBeInTheDocument();
		expect(screen.getByRole("button", { name: /account menu/i })).toHaveTextContent("Sara");
	});

	it("fires onOpenMenu from the hamburger", async () => {
		const onOpenMenu = vi.fn();
		renderTopbar(onOpenMenu);
		await userEvent.click(screen.getByRole("button", { name: /open menu/i }));
		expect(onOpenMenu).toHaveBeenCalledOnce();
	});

	it("has no axe violations", async () => {
		const { container } = renderTopbar();
		expect(await axe(container)).toHaveNoViolations();
	});
});
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `pnpm exec vitest run src/features/shell/AppTopbar.test.tsx`
Expected: FAIL (cannot resolve `./AppTopbar`).

- [ ] **Step 3: Implement AppTopbar**

Create `src/features/shell/AppTopbar.tsx`:

```tsx
import { Menu } from "lucide-react";
import { useTranslation } from "react-i18next";
import { Button, LocaleToggle, ThemeToggle } from "@/ui";
import { UserMenu } from "./UserMenu";

export function AppTopbar({
	userName,
	onSignOut,
	onOpenMenu,
}: {
	userName: string;
	onSignOut: () => void;
	onOpenMenu: () => void;
}) {
	const { t } = useTranslation();
	return (
		<header className="flex items-center gap-2 border-b border-border bg-background px-4 py-2">
			<Button
				variant="outline"
				size="icon"
				className="md:hidden"
				aria-label={t("nav.openMenu")}
				onClick={onOpenMenu}
			>
				<Menu className="size-4" />
			</Button>
			<span className="font-display text-xl font-semibold text-primary">
				kaleem<span className="text-accent">.</span>
			</span>
			<div className="ms-auto flex items-center gap-2">
				<LocaleToggle />
				<ThemeToggle />
				<UserMenu userName={userName} onSignOut={onSignOut} />
			</div>
		</header>
	);
}
```

- [ ] **Step 4: Run the test — expect PASS**

Run: `pnpm exec vitest run src/features/shell/AppTopbar.test.tsx`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/features/shell/AppTopbar.tsx src/features/shell/AppTopbar.test.tsx
PIP_CONFIG_FILE=/dev/null git commit -m "feat(shell): AppTopbar (brand, toggles, hamburger, user menu)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: AppShell + install into the `_authed` route

**Files:**
- Create: `src/features/shell/AppShell.tsx`, `src/features/shell/index.ts`
- Modify: `src/routes/_authed.tsx`
- Test: `src/features/shell/AppShell.test.tsx`

**Interfaces:**
- Consumes: `useMe`, `useLogout` from `@/features/identity/queries`; `useNavigate` from TanStack Router; `NAV_ITEMS`/`visibleNavItems` from `./nav`; `AppTopbar`, `AppSidebar`; `Alert`/`AlertDescription` from `@/ui`.
- Produces: `function AppShell({ children }: { children: React.ReactNode })` — grid frame; persistent sidebar on `md`+; mobile drawer toggled from the topbar; sign-out via `useLogout` then navigate to `/login`; on logout error renders an `Alert`.

- [ ] **Step 1: Write the failing test**

Create `src/features/shell/AppShell.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import {
	createMemoryHistory,
	createRootRoute,
	createRoute,
	createRouter,
	Outlet,
	RouterProvider,
} from "@tanstack/react-router";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import "@/lib/i18n";
import { identityApi } from "@/features/identity/api";
import type { Me } from "@/features/identity/schemas";
import { ThemeProvider } from "@/lib/theme";
import { AppShell } from "./AppShell";

const me: Me = { id: 1, email: "s@b.com", full_name: "Sara", profiles: ["student"] };

function renderShell() {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
	});
	client.setQueryData(["me"], me);
	const rootRoute = createRootRoute({
		component: () => (
			<AppShell>
				<Outlet />
			</AppShell>
		),
	});
	const idx = createRoute({
		getParentRoute: () => rootRoute,
		path: "/",
		component: () => <div>page body</div>,
	});
	const profile = createRoute({ getParentRoute: () => rootRoute, path: "/profile", component: () => <div>profile page</div> });
	const login = createRoute({ getParentRoute: () => rootRoute, path: "/login", component: () => <div>login page</div> });
	const router = createRouter({
		routeTree: rootRoute.addChildren([idx, profile, login]),
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

afterEach(() => vi.restoreAllMocks());

describe("AppShell", () => {
	it("renders topbar, sidebar nav, page body, and no footer", async () => {
		renderShell();
		expect(await screen.findByText("page body")).toBeInTheDocument();
		expect(screen.getByRole("navigation", { name: /main navigation/i })).toBeInTheDocument();
		expect(screen.getByRole("button", { name: /account menu/i })).toHaveTextContent("Sara");
		expect(document.querySelector("footer")).toBeNull();
	});

	it("opens the mobile drawer from the hamburger and closes on Escape", async () => {
		renderShell();
		// two navs would exist if open (rail + drawer); start with one
		await userEvent.click(screen.getByRole("button", { name: /open menu/i }));
		expect(screen.getAllByRole("navigation", { name: /main navigation/i }).length).toBeGreaterThan(1);
		await userEvent.keyboard("{Escape}");
		await waitFor(() =>
			expect(screen.getAllByRole("navigation", { name: /main navigation/i }).length).toBe(1),
		);
	});

	it("signs out and redirects to /login", async () => {
		vi.spyOn(identityApi, "logout").mockResolvedValue(undefined);
		renderShell();
		await userEvent.click(screen.getByRole("button", { name: /account menu/i }));
		await userEvent.click(screen.getByRole("menuitem", { name: /sign out/i }));
		expect(await screen.findByText("login page")).toBeInTheDocument();
	});

	it("surfaces a sign-out error and stays put", async () => {
		vi.spyOn(identityApi, "logout").mockRejectedValue(new Error("boom"));
		renderShell();
		await userEvent.click(screen.getByRole("button", { name: /account menu/i }));
		await userEvent.click(screen.getByRole("menuitem", { name: /sign out/i }));
		expect(await screen.findByRole("alert")).toBeInTheDocument();
		expect(screen.getByText("page body")).toBeInTheDocument();
	});
});
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `pnpm exec vitest run src/features/shell/AppShell.test.tsx`
Expected: FAIL (cannot resolve `./AppShell`).

- [ ] **Step 3: Implement AppShell**

Create `src/features/shell/AppShell.tsx`:

```tsx
import { useNavigate } from "@tanstack/react-router";
import { X } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useLogout, useMe } from "@/features/identity/queries";
import { Alert, AlertDescription, Button } from "@/ui";
import { AppSidebar } from "./AppSidebar";
import { AppTopbar } from "./AppTopbar";
import { NAV_ITEMS, visibleNavItems } from "./nav";

export function AppShell({ children }: { children: React.ReactNode }) {
	const { t } = useTranslation();
	const { data: me } = useMe();
	const logout = useLogout();
	const navigate = useNavigate();
	const [drawerOpen, setDrawerOpen] = useState(false);
	const [signOutFailed, setSignOutFailed] = useState(false);

	const items = visibleNavItems(NAV_ITEMS, me?.profiles ?? []);

	const onSignOut = () => {
		setSignOutFailed(false);
		logout.mutate(undefined, {
			onSuccess: () => navigate({ to: "/login" }),
			onError: () => setSignOutFailed(true),
		});
	};

	return (
		<div className="grid min-h-dvh grid-rows-[auto_1fr] bg-background text-foreground">
			<AppTopbar
				userName={me?.full_name ?? ""}
				onSignOut={onSignOut}
				onOpenMenu={() => setDrawerOpen(true)}
			/>
			<div className="grid md:grid-cols-[16rem_1fr]">
				<aside className="hidden border-e border-border md:block">
					<AppSidebar items={items} />
				</aside>
				<main className="min-w-0 p-4">
					{signOutFailed ? (
						<Alert variant="destructive" className="mb-4">
							<AlertDescription>{t("auth.signOutFailed")}</AlertDescription>
						</Alert>
					) : null}
					{children}
				</main>
			</div>

			{drawerOpen ? (
				// biome-ignore lint/a11y/useKeyWithClickEvents: overlay closes via Escape (window) + the close button; this is a backdrop.
				<div
					className="fixed inset-0 z-40 bg-black/40 md:hidden"
					onClick={() => setDrawerOpen(false)}
				>
					<div
						role="dialog"
						aria-label={t("nav.primary")}
						className="absolute inset-y-0 start-0 w-64 bg-background shadow-lg"
						onClick={(e) => e.stopPropagation()}
						onKeyDown={(e) => e.key === "Escape" && setDrawerOpen(false)}
					>
						<div className="flex justify-end p-2">
							<Button
								variant="outline"
								size="icon"
								aria-label={t("nav.closeMenu")}
								onClick={() => setDrawerOpen(false)}
							>
								<X className="size-4" />
							</Button>
						</div>
						<AppSidebar items={items} onNavigate={() => setDrawerOpen(false)} />
					</div>
				</div>
			) : null}
		</div>
	);
}
```

Note: the `Escape`-to-close in the test fires on `window`; add a window listener so Escape works regardless of focus. Adjust the implementation to include:

```tsx
import { useEffect } from "react";
// ...inside AppShell, after state:
useEffect(() => {
	if (!drawerOpen) return;
	const onKey = (e: KeyboardEvent) => e.key === "Escape" && setDrawerOpen(false);
	window.addEventListener("keydown", onKey);
	return () => window.removeEventListener("keydown", onKey);
}, [drawerOpen]);
```

(Keep the listener; the inline `onKeyDown` on the dialog can be removed to avoid duplication — the window listener covers Escape.)

- [ ] **Step 4: Add the `auth.signOutFailed` i18n key**

In `src/locales/en/common.json` add to the `auth` block: `"signOutFailed": "Couldn't sign you out. Please try again."`
In `src/locales/ar/common.json` add: `"signOutFailed": "تعذّر تسجيل الخروج. يُرجى المحاولة مرة أخرى."`

- [ ] **Step 5: Create the barrel export**

Create `src/features/shell/index.ts`:

```ts
export { AppShell } from "./AppShell";
```

- [ ] **Step 6: Run the test — expect PASS**

Run: `pnpm exec vitest run src/features/shell/AppShell.test.tsx`
Expected: PASS (4 tests).

- [ ] **Step 7: Install the shell into the authed layout route**

Replace `src/routes/_authed.tsx` body so the shell wraps the outlet:

```tsx
import { createFileRoute, Outlet, redirect } from "@tanstack/react-router";
import { AppShell } from "@/features/shell";
import { ensureAuthed } from "@/features/identity/queries";

export const Route = createFileRoute("/_authed")({
	beforeLoad: async ({ context }) => {
		try {
			await ensureAuthed(context.queryClient);
		} catch {
			throw redirect({ to: "/login" });
		}
	},
	component: () => (
		<AppShell>
			<Outlet />
		</AppShell>
	),
});
```

- [ ] **Step 8: Run the full suite — expect GREEN**

Run: `pnpm test`
Expected: all pass (the existing `_authed/index` and `profile` route tests still pass; they render those pages in isolation, not through `_authed`).

- [ ] **Step 9: Commit**

```bash
git add src/features/shell/AppShell.tsx src/features/shell/index.ts src/features/shell/AppShell.test.tsx src/routes/_authed.tsx src/locales/en/common.json src/locales/ar/common.json
PIP_CONFIG_FILE=/dev/null git commit -m "feat(shell): AppShell + install on the _authed layout route

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Remove redundant inline nav from existing authed pages

**Files:**
- Modify: `src/routes/_authed/index.tsx`, `src/routes/_authed/index.test.tsx`
- Modify: `src/routes/_authed/profile.tsx`

**Interfaces:**
- Consumes: the shell now owns navigation + sign-out. `Home` no longer needs `onLogout`.

- [ ] **Step 1: Update the Home test to drop the sign-out assertion**

The shell now provides sign-out, so `Home` should not. Edit `src/routes/_authed/index.test.tsx`:
- In `renderHome`, change the index route component to `() => <Home me={me} />` (drop the `onLogout` prop).
- Replace the first test body with an assertion that no longer expects a sign-out button:

```tsx
	it("greets the user", async () => {
		renderHome(student);
		expect(await screen.findByText(/sara/i)).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: /sign out/i })).toBeNull();
	});
```

Keep the "shows a parent section for parents" test unchanged.

- [ ] **Step 2: Run it and confirm it fails**

Run: `pnpm exec vitest run src/routes/_authed/index.test.tsx`
Expected: FAIL — `Home` still renders the Sign-out button (and still requires `onLogout`).

- [ ] **Step 3: Simplify the Home component**

Edit `src/routes/_authed/index.tsx`:
- Change the signature to `export function Home({ me }: { me: Me })` and delete the entire header `<div>` that holds the Profile `<Link>` and the Sign-out `<Button>` (the block with `flex items-center justify-between`). Keep the greeting `<h1>` (move it to the top of the column) and the parent/student `Card`s.
- In `HomeRoute`, drop `useLogout`/`useNavigate` and render `<Home me={me} />`.
- Remove now-unused imports (`Link`, `useNavigate`, `useLogout`, `Button`). Keep `useMe`, `Card*`, `useTranslation`.

Resulting `Home` body:

```tsx
export function Home({ me }: { me: Me }) {
	const { t } = useTranslation();
	const isParent = me.profiles.includes("parent");
	const isStudent = me.profiles.includes("student");
	return (
		<div className="mx-auto flex w-full max-w-2xl flex-col gap-6">
			<h1 className="font-display text-2xl font-semibold">
				{t("auth.greeting", { name: me.full_name })}
			</h1>
			{isParent ? (
				<Card>
					<CardHeader>
						<CardTitle>{t("auth.parent")}</CardTitle>
					</CardHeader>
					<CardContent className="text-sm text-muted-foreground">—</CardContent>
				</Card>
			) : null}
			{isStudent ? (
				<Card>
					<CardHeader>
						<CardTitle>{t("auth.student")}</CardTitle>
					</CardHeader>
					<CardContent className="text-sm text-muted-foreground">—</CardContent>
				</Card>
			) : null}
		</div>
	);
}

export const Route = createFileRoute("/_authed/")({
	component: function HomeRoute() {
		const { data: me } = useMe();
		if (!me) return null;
		return <Home me={me} />;
	},
});
```

- [ ] **Step 4: Remove the "Home" button from the profile page**

Edit `src/routes/_authed/profile.tsx`: delete the `<Button asChild variant="outline" className="self-start"><Link to="/">…</Link></Button>` block and the now-unused `Link`/`Button` imports (keep `Card*`, `ProfileEditForm`, `useMe`, `useTranslation`). The page becomes just the profile `Card` + form, in its centered column.

- [ ] **Step 5: Run the focused tests — expect PASS**

Run: `pnpm exec vitest run src/routes/_authed/index.test.tsx`
Expected: PASS.

- [ ] **Step 6: Full gate — tests, types, lint**

Run:
```bash
pnpm test
pnpm exec tsc --noEmit
pnpm exec biome check .
```
Expected: all green, no type errors, no lint errors. If `biome check` reports formatting, run `pnpm exec biome check --write .` and re-run.

- [ ] **Step 7: Commit**

```bash
git add src/routes/_authed/index.tsx src/routes/_authed/index.test.tsx src/routes/_authed/profile.tsx
PIP_CONFIG_FILE=/dev/null git commit -m "refactor(shell): drop per-page inline nav now owned by the shell

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage** (against `2026-06-18-dashboard-app-shell-design.md`):
- Topbar with brand/toggles/user-menu → Task 4. Role-aware sidebar + active state → Tasks 1+3. Data-driven nav config → Task 1. User menu (Profile + Sign out) on radix → Task 2. Shell wraps `/_authed/*` via `_authed.tsx` → Task 5. Mobile drawer (open/close/Escape) → Task 5. Sign-out success→/login and error→Alert → Task 5. No in-app footer → asserted in Task 5. Remove redundant inline nav → Task 6. i18n en+ar for every label → Tasks 1,5. a11y (axe) + RTL logical props → every component task. ✓ All spec sections covered.
- Out-of-scope items (footer, other feature pages, breadcrumbs, collapsible rail) correctly have no task.

**Placeholder scan:** No "TBD"/"handle X"/vague steps; every code step shows full code. The drawer backdrop carries an explicit `biome-ignore` with reason (Escape via window listener + close button provide keyboard access) — intentional, not a placeholder.

**Type consistency:** `NavItem`/`NAV_ITEMS`/`visibleNavItems` identical across Tasks 1,3,5. Component prop shapes consistent: `UserMenu({userName,onSignOut})` (Tasks 2,4), `AppSidebar({items,onNavigate})` (Tasks 3,5), `AppTopbar({userName,onSignOut,onOpenMenu})` (Tasks 4,5). i18n keys used match keys added (`nav.primary/openMenu/closeMenu/account`, `auth.signOutFailed`, reused `auth.home/profile/signOut`). `Me`/`ProfileType` imported from `@/features/identity/schemas`. Active-link contract (`aria-current="page"`) consistent between Task 3 impl and Task 5 assertion.
