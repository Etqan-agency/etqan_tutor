# Design System & Visual Identity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build kaleem's shared design system — a `@kaleem/tokens` package (CSS variables + Tailwind v4 `@theme`), light/dark theming, full RTL/i18n plumbing, and the dashboard's shadcn-backed `src/ui/` primitives scoped to the identity slice — so the next build (identity UI) renders on a finished foundation.

**Architecture:** A standalone `@kaleem/tokens` git repo is the single source of truth for brand tokens; the React dashboard and Astro marketing site both install it from its git URL. The dashboard maps the tokens onto shadcn's CSS-variable contract so generated primitives are themed automatically. Theme (light/dark) is a `data-theme`-style class on `<html>`; direction/locale is driven by i18next and sets `<html dir>`. All layout uses logical CSS properties so RTL is a flip, not a rewrite.

**Tech Stack:** Tailwind v4, shadcn/ui, class-variance-authority, clsx + tailwind-merge, React 19 + TanStack Router, react-i18next, Vitest + Testing Library + jest-axe, Astro (marketing), git submodules.

**Spec:** `docs/superpowers/specs/2026-06-13-design-system-visual-identity-design.md`
**Binding standard:** ADR-0020 (a11y WCAG 2.2 AA both themes, i18n, full RTL).

---

## Conventions for the whole plan

- **Package manager: `pnpm`** (the dashboard & marketing repos use pnpm — `pnpm-lock.yaml`, and the Dockerfiles use pnpm; plain `npm install` crashes against the pnpm `node_modules` layout). Throughout this plan substitute: `pnpm add` for `npm i`, `pnpm add -D` for `npm i -D`, and `pnpm test` / `pnpm run build` / `pnpm dev` for the `npm` equivalents. `npx shadcn@latest …` still works (or `pnpm dlx shadcn@latest …`). Commit `pnpm-lock.yaml`, not `package-lock.json`.

- **Git-flow:** the tokens, dashboard, and marketing repos are submodules → branch `feat/<name>` off `main`, PR into `main`. The meta repo → `docs/<name>` (or `feat/<name>`) off `develop`, PR into `develop`. Never commit to a trunk directly. No `--no-verify`.
- **Token git URL** used by consumers: `git+ssh://git@github.com/kaleem-lms/tokens.git#<tag>`. Bump the tag when tokens change and re-`npm install`.
- **Color values below are the starting direction.** Task D3 (contrast harness) is the gate — if any pairing fails AA in either theme, nudge the value and re-run. Do not ship a failing pairing.
- **No hardcoded UI strings** in any component — text comes from i18n keys (ADR-0020).

---

## File structure (what gets created, and its one responsibility)

**`tokens` repo (new, becomes `tokens/` submodule):**
- `package.json` — package metadata + exports map.
- `tokens.css` — brand custom properties for `:root` (light) and `.dark`, mapped onto shadcn's variable contract + kaleem extras (status colors, fonts).
- `theme.css` — Tailwind v4 `@theme inline` block exposing token utilities (`bg-primary`, `font-display`, `rounded-lg`, …).
- `index.css` — `@import`s both, single entry for consumers that want one import.
- `README.md` — what it is, how to consume, how to bump.

**`dashboard` repo:**
- `src/index.css` — imports Tailwind + tokens + theme + fonts; the shadcn `@theme`/base layer.
- `components.json` — shadcn config (tokens-aware).
- `src/lib/cn.ts` — `cn()` helper.
- `src/ui/*.tsx` — owned primitives (Button, Input, Label, Field, FormError, Card, Alert, Spinner) wrapping shadcn.
- `src/ui/index.ts` — barrel; the ONLY import surface for features.
- `src/lib/theme.tsx` — `ThemeProvider` + `useTheme` (light/dark, persisted, no-flash).
- `src/lib/i18n.ts` — i18next init; `src/locales/{en,ar}/common.json` — string catalogs.
- `src/lib/direction.tsx` — `DirectionProvider` syncing `<html dir>`/`lang` to locale.
- `src/ui/theme-toggle.tsx`, `src/ui/locale-toggle.tsx` — the two switches.
- `src/ui/auth-layout.tsx` — centered auth shell.
- `src/routes/design-preview.tsx` — temporary verification route rendering the 3-mode login.
- `src/test/setup.ts`, `vitest.config.ts` — test harness.
- `src/test/a11y.test.tsx` — axe + contrast + RTL gate.

**`marketing` repo:**
- `src/styles/global.css` (or layout import) — consumes `@kaleem/tokens`.
- `astro.config.mjs` / Tailwind wiring — Tailwind v4 + tokens.
- One branded element in `src/pages/index.astro` proving tokens apply.

**`infra`/CI:** a GitHub Actions secret (machine-user PAT or deploy key) granting the dashboard & marketing image builds read access to the private `tokens` repo.

**meta repo:** `tokens/` submodule pointer; bumped `dashboard`/`marketing` pointers; `docs/architecture/design-system.md`; `STATE.md`.

---

# Phase A — `@kaleem/tokens` package

> Work in a standalone clone (the repo is empty). Clone to a temp path, author, PR to `main`, tag `v0.1.0`. It becomes a submodule in Phase E.

### Task A1: Bootstrap the tokens repo

**Files:**
- Create: `package.json`, `.gitignore`, `README.md` (in the tokens clone)

- [ ] **Step 1: Clone the empty repo and branch**

```bash
git clone git@github.com:kaleem-lms/tokens.git /tmp/kaleem-tokens
cd /tmp/kaleem-tokens
git checkout -b feat/initial-tokens
```

- [ ] **Step 2: Write `package.json`**

```json
{
  "name": "@kaleem/tokens",
  "version": "0.1.0",
  "private": true,
  "description": "kaleem LMS shared design tokens: CSS custom properties + Tailwind v4 @theme preset",
  "type": "module",
  "files": ["tokens.css", "theme.css", "index.css"],
  "scripts": {
    "test": "node smoke.test.mjs"
  },
  "exports": {
    ".": "./index.css",
    "./tokens.css": "./tokens.css",
    "./theme.css": "./theme.css"
  }
}
```

(`"private": true` prevents accidental `npm publish`; it does NOT affect git-URL installation.)

- [ ] **Step 3: Write `.gitignore` and a stub `README.md`**

```gitignore
node_modules/
```

```markdown
# @kaleem/tokens

Single source of truth for kaleem's brand: color, type, spacing, radius, shadow, motion.
Consumed by the dashboard (React) and marketing (Astro) via git URL.

## Consume

    npm i "@kaleem/tokens@git+ssh://git@github.com/kaleem-lms/tokens.git#v0.1.1"

In your Tailwind v4 entry CSS:

    @import "tailwindcss";
    @import "@kaleem/tokens/tokens.css";
    @import "@kaleem/tokens/theme.css";

## Bump

Edit tokens, commit, tag `vX.Y.Z`, push the tag. Consumers bump the ref and reinstall.
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "chore: bootstrap @kaleem/tokens package"
```

### Task A2: Author `tokens.css` (brand → shadcn contract, light + dark)

**Files:**
- Create: `tokens.css`

- [ ] **Step 1: Write `tokens.css`**

```css
/* kaleem design tokens — Serene Scholar.
   Names follow shadcn's CSS-variable contract so shadcn primitives theme for free,
   plus kaleem extras (status colors, fonts). Values are the starting direction;
   the dashboard contrast harness is the AA gate (ADR-0020). */
:root {
  --background: #FAF7F0;
  --foreground: #16211D;
  --card: #FFFFFF;
  --card-foreground: #16211D;
  --popover: #FFFFFF;
  --popover-foreground: #16211D;
  --primary: #0E5C4F;
  --primary-foreground: #FFFFFF;
  --secondary: #EFE9DB;
  --secondary-foreground: #16211D;
  --muted: #EFE9DB;
  --muted-foreground: #62736C; /* AA 4.69:1 on #FAF7F0 (v0.1.1; was #6B7A74 ≈ 4.21:1, failed) */
  --accent: #C9A227;
  --accent-foreground: #3A2F00;
  --destructive: #C0432E;
  --destructive-foreground: #FFFFFF;
  --border: #E0D9C8;
  --input: #E0D9C8;
  --ring: #127D6B;
  --radius: 0.5rem;

  /* kaleem status extras (not in shadcn's base contract) */
  --success: #127D6B;
  --success-foreground: #FFFFFF;
  --warning: #C98A2B;
  --warning-foreground: #3A2600;
  --info: #2F6F8F;
  --info-foreground: #FFFFFF;

  /* type */
  --font-sans: "Inter", system-ui, sans-serif;
  --font-display: "Fraunces", Georgia, serif;
  --font-arabic: "IBM Plex Sans Arabic", "Inter", sans-serif;
  --font-quran: "Amiri Quran", "Noto Naskh Arabic", serif; /* reserved; consumer adds the face */

  /* shadow — warm green-tinted (same in both themes; tuned for cream/ink surfaces) */
  --shadow-sm: 0 1px 2px rgba(14, 92, 79, 0.06);
  --shadow-md: 0 1px 3px rgba(14, 92, 79, 0.08), 0 8px 24px rgba(14, 92, 79, 0.06);
  --shadow-lg: 0 12px 32px rgba(14, 92, 79, 0.12);

  /* motion */
  --duration-fast: 120ms;
  --duration-base: 200ms;
  --duration-slow: 320ms;
  --ease-standard: cubic-bezier(0.2, 0, 0, 1);
}

.dark {
  --background: #0E1715;
  --foreground: #ECEFEC;
  --card: #16211D;
  --card-foreground: #ECEFEC;
  --popover: #16211D;
  --popover-foreground: #ECEFEC;
  --primary: #4FB89F;
  --primary-foreground: #07302A;
  --secondary: #1E2B27;
  --secondary-foreground: #ECEFEC;
  --muted: #1E2B27;
  --muted-foreground: #9DB0A8;
  --accent: #D9B43C;
  --accent-foreground: #3A2F00;
  --destructive: #E0735B;
  --destructive-foreground: #1A0E0A;
  --border: #2A3A34;
  --input: #2A3A34;
  --ring: #3AA08C;

  --success: #3AA08C;
  --success-foreground: #07302A;
  --warning: #D9B43C;
  --warning-foreground: #3A2600;
  --info: #5AA9C9;
  --info-foreground: #07212A;
}
```

- [ ] **Step 2: Commit**

```bash
git add tokens.css && git commit -m "feat: brand tokens (light + dark) on shadcn contract"
```

### Task A3: Author `theme.css` (Tailwind v4 `@theme inline`) and `index.css`

**Files:**
- Create: `theme.css`, `index.css`

- [ ] **Step 1: Write `theme.css`**

```css
/* Exposes tokens as Tailwind v4 utilities. Import AFTER `@import "tailwindcss"`
   and AFTER tokens.css. `inline` means utilities resolve the live CSS variable,
   so light/dark swapping just works. */
@theme inline {
  --color-background: var(--background);
  --color-foreground: var(--foreground);
  --color-card: var(--card);
  --color-card-foreground: var(--card-foreground);
  --color-popover: var(--popover);
  --color-popover-foreground: var(--popover-foreground);
  --color-primary: var(--primary);
  --color-primary-foreground: var(--primary-foreground);
  --color-secondary: var(--secondary);
  --color-secondary-foreground: var(--secondary-foreground);
  --color-muted: var(--muted);
  --color-muted-foreground: var(--muted-foreground);
  --color-accent: var(--accent);
  --color-accent-foreground: var(--accent-foreground);
  --color-destructive: var(--destructive);
  --color-destructive-foreground: var(--destructive-foreground);
  --color-border: var(--border);
  --color-input: var(--input);
  --color-ring: var(--ring);
  --color-success: var(--success);
  --color-success-foreground: var(--success-foreground);
  --color-warning: var(--warning);
  --color-warning-foreground: var(--warning-foreground);
  --color-info: var(--info);
  --color-info-foreground: var(--info-foreground);

  --font-sans: var(--font-sans);
  --font-display: var(--font-display);
  --font-arabic: var(--font-arabic);
  --font-quran: var(--font-quran);

  --radius-sm: calc(var(--radius) - 2px);
  --radius-md: var(--radius);
  --radius-lg: calc(var(--radius) + 4px);
  --radius-xl: calc(var(--radius) + 8px);

  --shadow-sm: var(--shadow-sm);
  --shadow-md: var(--shadow-md);
  --shadow-lg: var(--shadow-lg);

  --ease-standard: var(--ease-standard);
}
```

- [ ] **Step 2: Write `index.css`**

```css
@import "./tokens.css";
@import "./theme.css";
```

- [ ] **Step 3: Commit**

```bash
git add theme.css index.css && git commit -m "feat: Tailwind v4 @theme preset + single-import entry"
```

### Task A4: Smoke-test that tokens resolve, then PR + tag

**Files:**
- Create: `smoke.test.mjs`

- [ ] **Step 1: Write a dependency-free resolve check**

```js
// smoke.test.mjs — fails (exit 1) if a required token or utility mapping is missing,
// or if any :root color token is absent from the .dark block.
import { readFileSync } from "node:fs";
const tokens = readFileSync("tokens.css", "utf8");
const theme = readFileSync("theme.css", "utf8");

const required = ["--background", "--foreground", "--primary", "--ring", "--destructive",
  "--success", "--warning", "--info", "--font-display", "--font-arabic", "--duration-fast"];
const missingTok = required.filter((t) => !tokens.includes(t + ":"));

// Compare color-token coverage between :root and .dark.
const rootBlock = tokens.slice(tokens.indexOf(":root"), tokens.indexOf(".dark"));
const darkBlock = tokens.slice(tokens.indexOf(".dark"));
const colorNames = (block) =>
  [...block.matchAll(/--([\w-]*(?:background|foreground|primary|secondary|card|popover|muted|accent|destructive|border|input|ring|success|warning|info))\s*:/g)]
    .map((m) => m[0].trim().replace(/\s*:$/, ""));
const rootColors = new Set(colorNames(rootBlock));
const darkColors = new Set(colorNames(darkBlock));
const missingDark = [...rootColors].filter((c) => !darkColors.has(c));

const missingMap = ["--color-primary", "--color-background", "--font-display"].filter((m) => !theme.includes(m + ":"));
const problems = [
  ...missingTok.map((t) => `light token missing: ${t}`),
  ...missingDark.map((t) => `dark token missing: ${t}`),
  ...missingMap.map((m) => `theme mapping missing: ${m}`),
];
if (problems.length) { console.error(problems.join("\n")); process.exit(1); }
console.log(`tokens OK (${rootColors.size} color tokens, all present in .dark)`);
```

- [ ] **Step 2: Run it — expect PASS**

Run: `node smoke.test.mjs`
Expected: prints `tokens OK`, exit 0.

- [ ] **Step 3: Commit, push, open PR to `main`**

```bash
git add smoke.test.mjs && git commit -m "test: token resolve smoke check"
git push -u origin feat/initial-tokens
gh pr create --base main --title "feat: initial @kaleem/tokens" --body "Brand tokens (light+dark) on shadcn contract + Tailwind v4 @theme preset. Smoke test green."
```

- [ ] **Step 4: Merge PR, tag `v0.1.0`**

```bash
gh pr merge --merge --delete-branch
git checkout main && git pull
git tag v0.1.0 && git push origin v0.1.0
```

---

# Phase B — dashboard foundation (tokens, shadcn, test harness)

> All dashboard tasks: `cd dashboard`, branch `feat/design-system` off `main`.

### Task B1: Install tokens + fonts, wire `index.css`

**Files:**
- Modify: `dashboard/package.json` (deps), `dashboard/src/index.css`

- [ ] **Step 1: Branch and install**

```bash
cd dashboard && git checkout main && git pull && git checkout -b feat/design-system
npm i "@kaleem/tokens@git+ssh://git@github.com/kaleem-lms/tokens.git#v0.1.1"
npm i @fontsource-variable/fraunces @fontsource/inter @fontsource/ibm-plex-sans-arabic
```

- [ ] **Step 2: Replace `src/index.css`**

```css
@import "tailwindcss";
@import "@kaleem/tokens/tokens.css";
@import "@kaleem/tokens/theme.css";

/* font files (token families reference these) */
@import "@fontsource-variable/fraunces";
@import "@fontsource/inter/400.css";
@import "@fontsource/inter/500.css";
@import "@fontsource/inter/600.css";
@import "@fontsource/inter/700.css";
@import "@fontsource/ibm-plex-sans-arabic/400.css";
@import "@fontsource/ibm-plex-sans-arabic/500.css";
@import "@fontsource/ibm-plex-sans-arabic/600.css";
@import "@fontsource/ibm-plex-sans-arabic/700.css";

/* dark theme is toggled by the `.dark` class on <html> (set by ThemeProvider) */
@custom-variant dark (&:where(.dark, .dark *));

@layer base {
  body { background-color: var(--color-background); color: var(--color-foreground); font-family: var(--font-sans); }
  :where([dir="rtl"]) body { font-family: var(--font-arabic); }
}
```

- [ ] **Step 3: Verify the dev build boots and is branded**

Run: `npm run dev` then open the root route.
Expected: page background is cream `#FAF7F0`, text near-black green. No console errors about missing `@kaleem/tokens`.

- [ ] **Step 4: Commit**

```bash
git add package.json package-lock.json src/index.css
git commit -m "feat: consume @kaleem/tokens + self-hosted fonts"
```

### Task B2: `cn()` helper

**Files:**
- Create: `dashboard/src/lib/cn.ts`, `dashboard/src/lib/cn.test.ts` (test added with harness in B3 — write file now)

- [ ] **Step 1: Write `cn.ts`**

```ts
import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
```

- [ ] **Step 2: Commit**

```bash
git add src/lib/cn.ts && git commit -m "feat: cn() class helper"
```

### Task B3: Test harness (Vitest + Testing Library + jest-axe)

**Files:**
- Modify: `dashboard/package.json` (devDeps + scripts)
- Create: `dashboard/vitest.config.ts`, `dashboard/src/test/setup.ts`

- [ ] **Step 1: Install dev deps**

```bash
npm i -D vitest@^3 jsdom @testing-library/react @testing-library/dom @testing-library/user-event @testing-library/jest-dom jest-axe @types/jest-axe
```

- [ ] **Step 2: Add scripts to `package.json`**

```json
"scripts": {
  "dev": "vite",
  "build": "tsc && vite build",
  "preview": "vite preview",
  "test": "vitest run",
  "test:watch": "vitest"
}
```

- [ ] **Step 3: Write `vitest.config.ts`**

```ts
import react from "@vitejs/plugin-react-swc";
import path from "node:path";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [react()],
  resolve: { alias: { "@": path.resolve(__dirname, "./src") } },
  test: { environment: "jsdom", globals: true, setupFiles: ["./src/test/setup.ts"] },
});
```

- [ ] **Step 4: Write `src/test/setup.ts`**

```ts
import "@testing-library/jest-dom/vitest";
import { expect } from "vitest";
import { toHaveNoViolations } from "jest-axe";

expect.extend(toHaveNoViolations);
```

- [ ] **Step 5: Write a trivial test to prove the harness runs (`src/lib/cn.test.ts`)**

```ts
import { describe, expect, it } from "vitest";
import { cn } from "./cn";

describe("cn", () => {
  it("merges and dedupes tailwind classes", () => {
    expect(cn("px-2", "px-4")).toBe("px-4");
    expect(cn("text-fg", false && "hidden")).toBe("text-fg");
  });
});
```

- [ ] **Step 6: Run — expect PASS**

Run: `npm test`
Expected: 2 assertions pass.

- [ ] **Step 7: Commit**

```bash
git add package.json package-lock.json vitest.config.ts src/test/setup.ts src/lib/cn.test.ts
git commit -m "test: vitest + testing-library + jest-axe harness"
```

### Task B4: Initialize shadcn against our tokens

**Files:**
- Create: `dashboard/components.json`
- Modify: `dashboard/src/index.css` (shadcn may append a base layer — keep our token imports on top)

- [ ] **Step 1: Run shadcn init (non-interactive where possible)**

```bash
npx shadcn@latest init
```
Answer prompts: style = default; base color = neutral (we override via tokens); CSS variables = yes; CSS file = `src/index.css`; alias `@/components` → keep, but we will NOT use `components/ui` — set components alias to `@/ui`; utils alias = `@/lib/cn` (matches Task B2). If the wizard rewrites `index.css`, re-apply the token `@import`s from B1 at the very top.

- [ ] **Step 2: Verify `components.json` points at our aliases**

Expected `components.json` contains `"aliases": { "components": "@/ui", "utils": "@/lib/cn", ... }` and `"tailwind": { "cssVariables": true }`.

- [ ] **Step 3: Confirm build still boots branded**

Run: `npm run dev`
Expected: still cream background; no regressions.

- [ ] **Step 4: Commit**

```bash
git add components.json src/index.css
git commit -m "feat: shadcn configured against kaleem tokens (@/ui, cssVariables)"
```

---

# Phase C — theming, i18n/RTL, primitives

### Task C1: `ThemeProvider` (light/dark, persisted, no flash)

**Files:**
- Create: `dashboard/src/lib/theme.tsx`, `dashboard/src/lib/theme.test.tsx`
- Modify: `dashboard/index.html` (inline no-flash script)

- [ ] **Step 1: Write the failing test (`theme.test.tsx`)**

```tsx
import { act, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it } from "vitest";
import { ThemeProvider, useTheme } from "./theme";

function Probe() {
  const { theme, setTheme } = useTheme();
  return <button onClick={() => setTheme(theme === "dark" ? "light" : "dark")}>{theme}</button>;
}

afterEach(() => { localStorage.clear(); document.documentElement.classList.remove("dark"); });

describe("ThemeProvider", () => {
  it("toggles the .dark class on <html> and persists", async () => {
    render(<ThemeProvider><Probe /></ThemeProvider>);
    await userEvent.click(screen.getByRole("button"));
    expect(document.documentElement.classList.contains("dark")).toBe(true);
    expect(localStorage.getItem("kaleem-theme")).toBe("dark");
  });
});
```

- [ ] **Step 2: Run — expect FAIL** (`Cannot find module './theme'`)

Run: `npm test -- theme`

- [ ] **Step 3: Implement `theme.tsx`**

```tsx
import { createContext, useContext, useEffect, useState } from "react";

type Theme = "light" | "dark";
const STORAGE_KEY = "kaleem-theme";
const ThemeContext = createContext<{ theme: Theme; setTheme: (t: Theme) => void } | null>(null);

function resolveInitial(): Theme {
  const stored = localStorage.getItem(STORAGE_KEY);
  if (stored === "light" || stored === "dark") return stored;
  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [theme, setThemeState] = useState<Theme>(resolveInitial);
  useEffect(() => {
    document.documentElement.classList.toggle("dark", theme === "dark");
    localStorage.setItem(STORAGE_KEY, theme);
  }, [theme]);
  return <ThemeContext.Provider value={{ theme, setTheme: setThemeState }}>{children}</ThemeContext.Provider>;
}

export function useTheme() {
  const ctx = useContext(ThemeContext);
  if (!ctx) throw new Error("useTheme must be used within ThemeProvider");
  return ctx;
}
```

- [ ] **Step 4: Add the no-flash script to `index.html`** (in `<head>`, before the module script)

```html
<script>
  (function () {
    try {
      var t = localStorage.getItem("kaleem-theme");
      if (t === "dark" || (!t && matchMedia("(prefers-color-scheme: dark)").matches))
        document.documentElement.classList.add("dark");
    } catch (e) {}
  })();
</script>
```

- [ ] **Step 5: Run — expect PASS**

Run: `npm test -- theme`

- [ ] **Step 6: Commit**

```bash
git add src/lib/theme.tsx src/lib/theme.test.tsx index.html
git commit -m "feat: ThemeProvider (light/dark, persisted, no-flash)"
```

### Task C2: i18n (react-i18next) + string catalogs

**Files:**
- Create: `dashboard/src/lib/i18n.ts`, `dashboard/src/locales/en/common.json`, `dashboard/src/locales/ar/common.json`

- [ ] **Step 1: Install**

```bash
npm i i18next react-i18next
```

- [ ] **Step 2: Write catalogs**

`src/locales/en/common.json`:
```json
{
  "auth": {
    "welcomeBack": "Welcome back",
    "signInSubtitle": "Sign in to continue your studies.",
    "email": "Email",
    "password": "Password",
    "signIn": "Sign in",
    "newToKaleem": "New to kaleem? Create an account"
  },
  "theme": { "toggle": "Toggle theme" },
  "locale": { "toggle": "Switch language" }
}
```

`src/locales/ar/common.json`:
```json
{
  "auth": {
    "welcomeBack": "مرحبًا بعودتك",
    "signInSubtitle": "سجّل الدخول لمتابعة دراستك.",
    "email": "البريد الإلكتروني",
    "password": "كلمة المرور",
    "signIn": "تسجيل الدخول",
    "newToKaleem": "جديد على كَلِيم؟ أنشئ حسابًا"
  },
  "theme": { "toggle": "تبديل السمة" },
  "locale": { "toggle": "تغيير اللغة" }
}
```

- [ ] **Step 3: Write `i18n.ts`**

```ts
import i18n from "i18next";
import { initReactI18next } from "react-i18next";
import enCommon from "@/locales/en/common.json";
import arCommon from "@/locales/ar/common.json";

export const SUPPORTED = ["en", "ar"] as const;
export type Locale = (typeof SUPPORTED)[number];
export const RTL_LOCALES: Locale[] = ["ar"];

const stored = (typeof localStorage !== "undefined" && localStorage.getItem("kaleem-locale")) as Locale | null;

i18n.use(initReactI18next).init({
  resources: { en: { common: enCommon }, ar: { common: arCommon } },
  lng: stored && SUPPORTED.includes(stored) ? stored : "en",
  fallbackLng: "en",
  defaultNS: "common",
  interpolation: { escapeValue: false },
});

export default i18n;
```

- [ ] **Step 4: Commit**

```bash
git add package.json package-lock.json src/lib/i18n.ts src/locales
git commit -m "feat: i18n setup (en + ar) with login strings"
```

### Task C3: `DirectionProvider` (sync `<html dir>`/`lang` to locale)

**Files:**
- Create: `dashboard/src/lib/direction.tsx`, `dashboard/src/lib/direction.test.tsx`

- [ ] **Step 1: Write the failing test**

```tsx
import { render } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import i18n from "./i18n";
import { DirectionProvider } from "./direction";

afterEach(async () => { await i18n.changeLanguage("en"); });

describe("DirectionProvider", () => {
  it("sets dir=rtl and lang=ar when locale is Arabic", async () => {
    await i18n.changeLanguage("ar");
    render(<DirectionProvider><span /></DirectionProvider>);
    expect(document.documentElement.getAttribute("dir")).toBe("rtl");
    expect(document.documentElement.getAttribute("lang")).toBe("ar");
  });
  it("sets dir=ltr for English", async () => {
    await i18n.changeLanguage("en");
    render(<DirectionProvider><span /></DirectionProvider>);
    expect(document.documentElement.getAttribute("dir")).toBe("ltr");
  });
});
```

- [ ] **Step 2: Run — expect FAIL**

Run: `npm test -- direction`

- [ ] **Step 3: Implement `direction.tsx`**

```tsx
import { useEffect } from "react";
import { useTranslation } from "react-i18next";
import { RTL_LOCALES, type Locale } from "./i18n";

export function DirectionProvider({ children }: { children: React.ReactNode }) {
  const { i18n } = useTranslation();
  const lng = i18n.language as Locale;
  useEffect(() => {
    const dir = RTL_LOCALES.includes(lng) ? "rtl" : "ltr";
    document.documentElement.setAttribute("dir", dir);
    document.documentElement.setAttribute("lang", lng);
    localStorage.setItem("kaleem-locale", lng);
  }, [lng]);
  return <>{children}</>;
}
```

- [ ] **Step 4: Run — expect PASS**

Run: `npm test -- direction`

- [ ] **Step 5: Commit**

```bash
git add src/lib/direction.tsx src/lib/direction.test.tsx
git commit -m "feat: DirectionProvider syncs <html dir>/lang to locale"
```

### Task C4: Button primitive (the canonical pattern)

**Files:**
- Create: `dashboard/src/ui/button.tsx`, `dashboard/src/ui/button.test.tsx`
- Modify: `dashboard/src/ui/index.ts`

- [ ] **Step 1: Add shadcn button, then move/own it**

```bash
npx shadcn@latest add button
```
shadcn writes to `@/ui` (per components.json alias) → `src/ui/button.tsx`.

- [ ] **Step 2: Replace the variant block in `src/ui/button.tsx` with kaleem variants**

```tsx
import { Slot } from "radix-ui"; // unified radix-ui v1 package; use Slot.Root
import { type VariantProps, cva } from "class-variance-authority";
import * as React from "react";
import { cn } from "@/lib/cn";

const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-semibold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:pointer-events-none disabled:opacity-50",
  {
    variants: {
      variant: {
        primary: "bg-primary text-primary-foreground hover:opacity-90",
        secondary: "bg-secondary text-secondary-foreground hover:opacity-90",
        outline: "border border-border bg-transparent hover:bg-secondary",
        ghost: "bg-transparent hover:bg-secondary",
        destructive: "bg-destructive text-destructive-foreground hover:opacity-90",
      },
      size: { sm: "h-9 px-3", md: "h-10 px-4", lg: "h-11 px-6", icon: "h-10 w-10" },
    },
    defaultVariants: { variant: "primary", size: "md" },
  },
);

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>, VariantProps<typeof buttonVariants> {
  asChild?: boolean;
}

export const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, asChild = false, ...props }, ref) => {
    const Comp = asChild ? Slot : "button";
    return <Comp ref={ref} className={cn(buttonVariants({ variant, size, className }))} {...props} />;
  },
);
Button.displayName = "Button";
export { buttonVariants };
```

- [ ] **Step 3: Export from the barrel (`src/ui/index.ts`)**

```ts
export { Button, buttonVariants, type ButtonProps } from "./button";
```

- [ ] **Step 4: Write `button.test.tsx`** (render, variant, keyboard, axe)

```tsx
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "jest-axe";
import { describe, expect, it, vi } from "vitest";
import { Button } from "./button";

describe("Button", () => {
  it("renders children and applies the destructive variant", () => {
    render(<Button variant="destructive">Delete</Button>);
    expect(screen.getByRole("button", { name: "Delete" }).className).toContain("bg-destructive");
  });
  it("fires onClick via keyboard (Enter)", async () => {
    const onClick = vi.fn();
    render(<Button onClick={onClick}>Go</Button>);
    screen.getByRole("button").focus();
    await userEvent.keyboard("{Enter}");
    expect(onClick).toHaveBeenCalledOnce();
  });
  it("has no axe violations", async () => {
    const { container } = render(<Button>Accessible</Button>);
    expect(await axe(container)).toHaveNoViolations();
  });
});
```

- [ ] **Step 5: Run — expect PASS**

Run: `npm test -- button`

- [ ] **Step 6: Commit**

```bash
git add src/ui/button.tsx src/ui/button.test.tsx src/ui/index.ts
git commit -m "feat(ui): Button primitive (kaleem variants) + tests"
```

### Task C5: Input + Label primitives

**Files:**
- Create: `dashboard/src/ui/input.tsx`, `dashboard/src/ui/label.tsx`, `dashboard/src/ui/input.test.tsx`
- Modify: `dashboard/src/ui/index.ts`

- [ ] **Step 1: Add shadcn input + label**

```bash
npx shadcn@latest add input label
```

- [ ] **Step 2: Ensure `src/ui/input.tsx` uses logical/token styles**

Replace the className with:
```tsx
import * as React from "react";
import { cn } from "@/lib/cn";

export const Input = React.forwardRef<HTMLInputElement, React.InputHTMLAttributes<HTMLInputElement>>(
  ({ className, type, ...props }, ref) => (
    <input
      ref={ref}
      type={type}
      className={cn(
        "flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm text-foreground",
        "placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
        "focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:opacity-50",
        "rtl:text-right",
        className,
      )}
      {...props}
    />
  ),
);
Input.displayName = "Input";
```

(Leave shadcn's `Label` as generated; it is already token/Radix-based and accessible.)

- [ ] **Step 3: Export from barrel**

```ts
export { Input } from "./input";
export { Label } from "./label";
```

- [ ] **Step 4: Write `input.test.tsx`** (typing, association via Label, axe)

```tsx
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { axe } from "jest-axe";
import { describe, expect, it } from "vitest";
import { Input } from "./input";
import { Label } from "./label";

describe("Input", () => {
  it("is labelable and accepts typed text", async () => {
    render(<><Label htmlFor="email">Email</Label><Input id="email" /></>);
    const field = screen.getByLabelText("Email");
    await userEvent.type(field, "a@b.com");
    expect(field).toHaveValue("a@b.com");
  });
  it("has no axe violations when labelled", async () => {
    const { container } = render(<><Label htmlFor="x">X</Label><Input id="x" /></>);
    expect(await axe(container)).toHaveNoViolations();
  });
});
```

- [ ] **Step 5: Run — expect PASS**, then commit

Run: `npm test -- input`
```bash
git add src/ui/input.tsx src/ui/label.tsx src/ui/input.test.tsx src/ui/index.ts
git commit -m "feat(ui): Input + Label primitives + tests"
```

### Task C6: Field + FormError (accessible field composition)

**Files:**
- Create: `dashboard/src/ui/field.tsx`, `dashboard/src/ui/field.test.tsx`
- Modify: `dashboard/src/ui/index.ts`

- [ ] **Step 1: Write the failing test**

```tsx
import { render, screen } from "@testing-library/react";
import { axe } from "jest-axe";
import { describe, expect, it } from "vitest";
import { Field } from "./field";
import { Input } from "./input";

describe("Field", () => {
  it("wires label, control, and error via aria-describedby", () => {
    render(<Field id="pw" label="Password" error="Too short"><Input type="password" /></Field>);
    const input = screen.getByLabelText("Password");
    const err = screen.getByText("Too short");
    expect(input).toHaveAttribute("aria-invalid", "true");
    expect(input.getAttribute("aria-describedby")).toBe(err.id);
    expect(err).toHaveAttribute("role", "alert");
  });
  it("has no axe violations", async () => {
    const { container } = render(<Field id="e" label="Email"><Input /></Field>);
    expect(await axe(container)).toHaveNoViolations();
  });
});
```

- [ ] **Step 2: Run — expect FAIL** (`Cannot find module './field'`)

Run: `npm test -- field`

- [ ] **Step 3: Implement `field.tsx`**

```tsx
import * as React from "react";
import { cn } from "@/lib/cn";
import { Label } from "./label";

export interface FieldProps {
  id: string;
  label: string;
  error?: string;
  className?: string;
  children: React.ReactElement<{ id?: string; "aria-invalid"?: boolean; "aria-describedby"?: string }>;
}

export function Field({ id, label, error, className, children }: FieldProps) {
  const errorId = `${id}-error`;
  const control = React.cloneElement(children, {
    id,
    "aria-invalid": error ? true : undefined,
    "aria-describedby": error ? errorId : undefined,
  });
  return (
    <div className={cn("flex flex-col gap-1.5", className)}>
      <Label htmlFor={id}>{label}</Label>
      {control}
      {error ? <FormError id={errorId}>{error}</FormError> : null}
    </div>
  );
}

export function FormError({ id, children }: { id?: string; children: React.ReactNode }) {
  return <p id={id} role="alert" className="text-sm text-destructive">{children}</p>;
}
```

- [ ] **Step 4: Export from barrel, run — expect PASS, commit**

```ts
export { Field, FormError, type FieldProps } from "./field";
```
Run: `npm test -- field`
```bash
git add src/ui/field.tsx src/ui/field.test.tsx src/ui/index.ts
git commit -m "feat(ui): Field + FormError with aria wiring + tests"
```

### Task C7: Card, Alert, Spinner primitives

**Files:**
- Create: `dashboard/src/ui/card.tsx` (shadcn), `dashboard/src/ui/alert.tsx` (shadcn), `dashboard/src/ui/spinner.tsx`, `dashboard/src/ui/spinner.test.tsx`
- Modify: `dashboard/src/ui/index.ts`

- [ ] **Step 1: Add shadcn card + alert**

```bash
npx shadcn@latest add card alert
```

- [ ] **Step 2: Write `spinner.tsx`** (no shadcn equivalent; accessible busy indicator)

```tsx
import { cn } from "@/lib/cn";

export function Spinner({ label = "Loading", className }: { label?: string; className?: string }) {
  return (
    <span role="status" aria-live="polite" className={cn("inline-flex items-center", className)}>
      <span
        aria-hidden="true"
        className="size-4 animate-spin rounded-full border-2 border-muted-foreground border-t-transparent motion-reduce:animate-none"
      />
      <span className="sr-only">{label}</span>
    </span>
  );
}
```

- [ ] **Step 3: Export the lot from barrel**

```ts
export { Card, CardHeader, CardTitle, CardDescription, CardContent, CardFooter } from "./card";
export { Alert, AlertTitle, AlertDescription } from "./alert";
export { Spinner } from "./spinner";
```

- [ ] **Step 4: Write `spinner.test.tsx`**

```tsx
import { render, screen } from "@testing-library/react";
import { axe } from "jest-axe";
import { describe, expect, it } from "vitest";
import { Spinner } from "./spinner";

describe("Spinner", () => {
  it("exposes an accessible status label", () => {
    render(<Spinner label="Signing in" />);
    expect(screen.getByRole("status")).toHaveTextContent("Signing in");
  });
  it("has no axe violations", async () => {
    const { container } = render(<Spinner />);
    expect(await axe(container)).toHaveNoViolations();
  });
});
```

- [ ] **Step 5: Run — expect PASS, commit**

Run: `npm test -- spinner`
```bash
git add src/ui/card.tsx src/ui/alert.tsx src/ui/spinner.tsx src/ui/spinner.test.tsx src/ui/index.ts
git commit -m "feat(ui): Card, Alert, Spinner primitives + Spinner test"
```

### Task C8: Theme toggle + Locale toggle

**Files:**
- Create: `dashboard/src/ui/theme-toggle.tsx`, `dashboard/src/ui/locale-toggle.tsx`
- Modify: `dashboard/src/ui/index.ts`

- [ ] **Step 1: Write `theme-toggle.tsx`**

```tsx
import { useTranslation } from "react-i18next";
import { useTheme } from "@/lib/theme";
import { Button } from "./button";

export function ThemeToggle() {
  const { theme, setTheme } = useTheme();
  const { t } = useTranslation();
  return (
    <Button variant="outline" size="icon" aria-label={t("theme.toggle")}
      onClick={() => setTheme(theme === "dark" ? "light" : "dark")}>
      <span aria-hidden="true">{theme === "dark" ? "☾" : "☀"}</span>
    </Button>
  );
}
```

- [ ] **Step 2: Write `locale-toggle.tsx`**

```tsx
import { useTranslation } from "react-i18next";
import { Button } from "./button";

export function LocaleToggle() {
  const { i18n, t } = useTranslation();
  const next = i18n.language === "ar" ? "en" : "ar";
  return (
    <Button variant="outline" size="sm" aria-label={t("locale.toggle")}
      onClick={() => i18n.changeLanguage(next)}>
      {next === "ar" ? "العربية" : "EN"}
    </Button>
  );
}
```

- [ ] **Step 3: Export from barrel, commit**

```ts
export { ThemeToggle } from "./theme-toggle";
export { LocaleToggle } from "./locale-toggle";
```
```bash
git add src/ui/theme-toggle.tsx src/ui/locale-toggle.tsx src/ui/index.ts
git commit -m "feat(ui): theme + locale toggles"
```

### Task C9: Auth layout shell

**Files:**
- Create: `dashboard/src/ui/auth-layout.tsx`, `dashboard/src/ui/auth-layout.test.tsx`
- Modify: `dashboard/src/ui/index.ts`

- [ ] **Step 1: Write the failing test**

```tsx
import { render, screen } from "@testing-library/react";
import { axe } from "jest-axe";
import { describe, expect, it } from "vitest";
import { AuthLayout } from "./auth-layout";

describe("AuthLayout", () => {
  it("renders the wordmark and a main landmark with children", () => {
    render(<AuthLayout><p>form</p></AuthLayout>);
    expect(screen.getByText("kaleem")).toBeInTheDocument();
    expect(screen.getByRole("main")).toHaveTextContent("form");
  });
  it("has no axe violations", async () => {
    const { container } = render(<AuthLayout><p>form</p></AuthLayout>);
    expect(await axe(container)).toHaveNoViolations();
  });
});
```

- [ ] **Step 2: Run — expect FAIL**, then implement `auth-layout.tsx`

```tsx
import { Card, CardContent } from "./card";
import { LocaleToggle } from "./locale-toggle";
import { ThemeToggle } from "./theme-toggle";

export function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-dvh bg-background text-foreground">
      <header className="flex items-center justify-between p-4">
        <span className="font-display text-2xl font-semibold text-primary">
          kaleem<span className="text-accent">.</span>
        </span>
        <div className="flex items-center gap-2"><LocaleToggle /><ThemeToggle /></div>
      </header>
      <main className="mx-auto flex w-full max-w-sm flex-col px-4 py-10">
        <Card><CardContent className="pt-6">{children}</CardContent></Card>
      </main>
    </div>
  );
}
```

- [ ] **Step 3: Export from barrel, run — expect PASS, commit**

```ts
export { AuthLayout } from "./auth-layout";
```
Run: `npm test -- auth-layout`
```bash
git add src/ui/auth-layout.tsx src/ui/auth-layout.test.tsx src/ui/index.ts
git commit -m "feat(ui): auth layout shell"
```

---

# Phase D — assembly, a11y/RTL gate, browser verification

### Task D1: Wire providers into the app root

**Files:**
- Modify: `dashboard/src/main.tsx` (wrap app), `dashboard/src/routes/__root.tsx` if providers belong there

- [ ] **Step 1: Wrap the router in providers** (in `main.tsx`, import `@/lib/i18n` for side-effect init, wrap with `ThemeProvider` + `DirectionProvider`)

```tsx
import "@/lib/i18n";
import { ThemeProvider } from "@/lib/theme";
import { DirectionProvider } from "@/lib/direction";
// inside render:
//   <ThemeProvider><DirectionProvider><RouterProvider router={router} /></DirectionProvider></ThemeProvider>
```

- [ ] **Step 2: Verify the app still boots**

Run: `npm run dev`
Expected: no errors; default English/LTR/light.

- [ ] **Step 3: Commit**

```bash
git add src/main.tsx src/routes/__root.tsx
git commit -m "feat: mount Theme + Direction + i18n providers at root"
```

### Task D2: `design-preview` route (mockup made real)

**Files:**
- Create: `dashboard/src/routes/design-preview.tsx`

- [ ] **Step 1: Build the login form from primitives only**

```tsx
import { createFileRoute } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { AuthLayout, Button, Field, Input } from "@/ui";

export const Route = createFileRoute("/design-preview")({ component: Preview });

function Preview() {
  const { t } = useTranslation();
  return (
    <AuthLayout>
      <h1 className="font-display text-xl font-semibold">{t("auth.welcomeBack")}</h1>
      <p className="mb-4 text-sm text-muted-foreground">{t("auth.signInSubtitle")}</p>
      <form className="flex flex-col gap-3">
        <Field id="email" label={t("auth.email")}><Input type="email" /></Field>
        <Field id="password" label={t("auth.password")}><Input type="password" /></Field>
        <Button type="submit" className="mt-2 w-full">{t("auth.signIn")}</Button>
      </form>
      <p className="mt-4 text-center text-sm text-primary">{t("auth.newToKaleem")}</p>
    </AuthLayout>
  );
}
```

- [ ] **Step 2: Run dev and verify all three modes by hand**

Run: `npm run dev` → open `/design-preview`.
Expected: (1) light/LTR English looks like the approved mockup; (2) theme toggle → dark renders correctly; (3) locale toggle → Arabic flips the whole layout to RTL, labels/inputs right-aligned, Arabic font applied.

- [ ] **Step 3: Commit**

```bash
git add src/routes/design-preview.tsx
git commit -m "feat: design-preview route (3-mode login, mockup made real)"
```

### Task D3: a11y + contrast + RTL automated gate

**Files:**
- Create: `dashboard/src/test/a11y.test.tsx`

- [ ] **Step 1: Write the gate test** (axe on the preview form, AA contrast on key pairings, RTL attribute under Arabic)

```tsx
import { render } from "@testing-library/react";
import { axe } from "jest-axe";
import { afterEach, describe, expect, it } from "vitest";
import i18n from "@/lib/i18n";
import { AuthLayout, Button, Field, Input } from "@/ui";

function relLum(hex: string) {
  const c = hex.replace("#", "");
  const ch = [0, 2, 4].map((i) => parseInt(c.slice(i, i + 2), 16) / 255)
    .map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
  return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2];
}
function ratio(a: string, b: string) {
  const [hi, lo] = [relLum(a), relLum(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

const sample = (
  <AuthLayout>
    <form>
      <Field id="email" label="Email"><Input type="email" /></Field>
      <Button>Sign in</Button>
    </form>
  </AuthLayout>
);

afterEach(async () => { await i18n.changeLanguage("en"); });

describe("design-system a11y gate", () => {
  it("auth form has no axe violations (LTR)", async () => {
    const { container } = render(sample);
    expect(await axe(container)).toHaveNoViolations();
  });
  it("auth form has no axe violations (RTL/Arabic)", async () => {
    await i18n.changeLanguage("ar");
    const { container } = render(sample);
    expect(document.documentElement.getAttribute("dir")).toBe("rtl");
    expect(await axe(container)).toHaveNoViolations();
  });
  it("key token pairings meet WCAG AA (4.5:1) in BOTH themes", () => {
    const pairs: Array<[string, string, string]> = [
      ["light primary btn", "#0E5C4F", "#FFFFFF"],
      ["light body text", "#16211D", "#FAF7F0"],
      ["light muted text", "#62736C", "#FAF7F0"],
      ["light destructive", "#C0432E", "#FFFFFF"],
      ["dark body text", "#ECEFEC", "#0E1715"],
      ["dark primary btn", "#07302A", "#4FB89F"],
      ["dark muted text", "#9DB0A8", "#0E1715"],
    ];
    for (const [name, fg, bg] of pairs) {
      expect(ratio(fg, bg), `${name} ${fg} on ${bg}`).toBeGreaterThanOrEqual(4.5);
    }
  });
});
```

- [ ] **Step 2: Run the gate**

Run: `npm test -- a11y`
Expected: all pass. **If a contrast pairing fails**, adjust the corresponding value in the tokens repo (Phase A), bump the tag, `npm install` the new ref here, and re-run. Do not weaken the 4.5 threshold.

- [ ] **Step 3: Run the full suite**

Run: `npm test`
Expected: every test green.

- [ ] **Step 4: Commit**

```bash
git add src/test/a11y.test.tsx
git commit -m "test: a11y + AA contrast (both themes) + RTL gate"
```

### Task D4: Lint, typecheck, build; PR the dashboard

- [ ] **Step 1: Lint + typecheck + build**

Run: `npx biome check src && npm run build`
Expected: no Biome errors; `tsc` clean; Vite build succeeds.

- [ ] **Step 2: Push and open PR to `main`**

```bash
git push -u origin feat/design-system
gh pr create --base main --title "feat: design system foundation + identity-slice primitives" \
  --body "Consumes @kaleem/tokens; shadcn-backed src/ui/ primitives (Button, Input, Label, Field/FormError, Card, Alert, Spinner); ThemeProvider (light/dark); i18n + DirectionProvider (full RTL); design-preview route; a11y/contrast/RTL gate green. Ref: design-system spec + ADR-0020."
```

- [ ] **Step 3: Merge after green CI**

```bash
gh pr merge --merge --delete-branch
```

---

# Phase E — marketing wiring + meta repo integration

### Task E1: Marketing consumes `@kaleem/tokens`

**Files:**
- Modify: `marketing/package.json`, `marketing/astro.config.mjs`, marketing global CSS, `marketing/src/pages/index.astro`

- [ ] **Step 1: Branch, install Tailwind v4 + tokens**

```bash
cd marketing && git checkout main && git pull && git checkout -b feat/consume-tokens
npm i "@kaleem/tokens@git+ssh://git@github.com/kaleem-lms/tokens.git#v0.1.1"
npm i @fontsource-variable/fraunces @fontsource/inter
npm i -D @tailwindcss/vite tailwindcss
```

- [ ] **Step 2: Add the Vite Tailwind plugin in `astro.config.mjs`**

```js
import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "astro/config";

export default defineConfig({ vite: { plugins: [tailwindcss()] } });
```

- [ ] **Step 3: Create `src/styles/global.css` and import it in the layout**

```css
@import "tailwindcss";
@import "@kaleem/tokens/tokens.css";
@import "@kaleem/tokens/theme.css";
@import "@fontsource-variable/fraunces";
@import "@fontsource/inter/400.css";
@import "@fontsource/inter/600.css";
```
Import it once in `src/layouts/Layout.astro` (`import "../styles/global.css";`).

- [ ] **Step 4: Prove tokens apply — add a branded hero element to `index.astro`**

```html
<section class="bg-background text-foreground p-16">
  <h1 class="font-display text-5xl font-semibold text-primary">kaleem<span class="text-accent">.</span></h1>
  <p class="text-muted-foreground">Learn the Islamic sciences, wherever you are.</p>
</section>
```

- [ ] **Step 5: Build to verify the token utilities compile in Astro**

Run: `npm run build`
Expected: build succeeds; `dist` CSS contains the cream background + emerald heading (visually confirm with `npm run preview`).

- [ ] **Step 6: Commit, push, PR to `main`, merge**

```bash
git add -A && git commit -m "feat: consume @kaleem/tokens (shared brand) + branded hero"
git push -u origin feat/consume-tokens
gh pr create --base main --title "feat: marketing consumes @kaleem/tokens" --body "Proves the shared token layer compiles in the Astro build. No page work beyond a branded hero."
gh pr merge --merge --delete-branch
```

### Task E2: CI access to the private tokens repo

**Files:**
- Modify: dashboard & marketing GitHub Actions workflow(s) that build the images (in those repos and/or `infra`)

- [ ] **Step 1: Provision a read-only credential**

Create a machine-user PAT (or a deploy key on the `tokens` repo) with read access. Add it as an Actions secret (e.g. `TOKENS_REPO_TOKEN`) in the dashboard and marketing repos.

- [ ] **Step 2: Make `npm install` use it for the git dependency**

In each build workflow, before `npm ci`, configure git to use the token for the tokens repo:
```yaml
- name: Auth to private tokens repo
  run: git config --global url."https://x-access-token:${{ secrets.TOKENS_REPO_TOKEN }}@github.com/".insteadOf "ssh://git@github.com/"
```
(Adjust the `insteadOf` to match the `git+ssh://` form used in package.json.)

- [ ] **Step 3: Verify a CI build succeeds**

Trigger the dashboard image build (push to its `main` already did, or re-run). Expected: `npm ci` resolves `@kaleem/tokens` and the image builds.

- [ ] **Step 4: Commit workflow changes via PR to each repo's `main`**

### Task E3: Add `tokens` submodule + bump pointers in the meta repo

**Files:**
- Modify (meta): `.gitmodules`, add `tokens/`, bump `dashboard`/`marketing` gitlinks
- Create (meta): `docs/architecture/design-system.md`
- Modify (meta): `STATE.md`

- [ ] **Step 1: Branch the meta repo off `develop`**

```bash
cd /home/abdulkhalek/Projects/kaleem && git checkout develop && git pull && git checkout -b feat/design-system-integration
```

- [ ] **Step 2: Add the tokens submodule and bump submodule pointers**

```bash
git submodule add git@github.com:kaleem-lms/tokens.git tokens
git -C dashboard fetch && git -C dashboard checkout main && git -C dashboard pull
git -C marketing fetch && git -C marketing checkout main && git -C marketing pull
git add .gitmodules tokens dashboard marketing
```

- [ ] **Step 3: Write `docs/architecture/design-system.md`**

Document: the token contract (shadcn variable names + kaleem extras), the consume-via-git-URL + bump-the-tag flow, the `tokens shared / components diverge` rule, the `import only from @/ui` boundary, theming (`.dark` on `<html>`), and the RTL/i18n model (`<html dir>` from locale, logical properties, no hardcoded strings). Link the spec and ADR-0020.

- [ ] **Step 4: Update `STATE.md`**

Mark the design-system spec shipped; set the next active work to the identity frontend slice; note `@kaleem/tokens@v0.1.0` is live and consumed by both surfaces.

- [ ] **Step 5: Commit, push, PR to `develop`**

```bash
git add docs/architecture/design-system.md STATE.md
git commit -m "feat: add @kaleem/tokens submodule; bump dashboard+marketing; design-system arch doc + STATE"
git push -u origin feat/design-system-integration
gh pr create --base develop --title "feat: integrate design system (submodule + pointers + docs)" --body "Adds tokens submodule, bumps dashboard/marketing pointers to the design-system commits, adds the design-system architecture doc, updates STATE.md."
```

- [ ] **Step 6: Merge after review**

```bash
gh pr merge --merge --delete-branch
```

---

## Definition of Done (D9)

- [ ] `@kaleem/tokens@v0.1.0` published (tagged on `main`), smoke test green.
- [ ] Dashboard consumes tokens; `src/ui/` primitives (Button, Input, Label, Field, FormError, Card, Alert, Spinner) + auth shell + theme/locale toggles built and unit-tested.
- [ ] ThemeProvider ships light **and** dark; no flash-of-wrong-theme.
- [ ] Full RTL: locale toggle flips `<html dir>`, layout mirrors, Arabic font applies; logical properties throughout.
- [ ] a11y gate green: axe clean (LTR + RTL), AA contrast asserted on key pairings in both themes.
- [ ] `design-preview` route verified by hand in the browser in all three modes.
- [ ] Marketing consumes tokens; Astro build compiles token utilities; branded hero renders.
- [ ] CI can install the private tokens package; dashboard + marketing images build.
- [ ] Deployed to staging via the existing frontend pipeline; `/design-preview` reachable on `app-staging`.
- [ ] `docs/architecture/design-system.md` written; `STATE.md` updated; weekly journal entry added.
- [ ] Boundary respected: features import UI only from `@/ui`.

## Out of scope (do not build here)

Identity screens themselves (next spec), marketing pages beyond the proof hero, the final Quran naskh font, full translation catalogs beyond the login strings, and any feature-specific component (Dialog, Dropdown, Tabs, Table, Toast, Select, Avatar, Badge) — add those when a feature first needs them.
