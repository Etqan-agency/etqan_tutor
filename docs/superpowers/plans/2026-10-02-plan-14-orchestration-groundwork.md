# Plan 14 — Orchestration Groundwork (Wave 0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make it safe for up to four phase sessions to build the roadmap in parallel: isolated dev stacks per worktree, shared lists that merge without conflict, and the ledger and launch tooling the conductor and phase orchestrators run on.

**Architecture:** Each phase works in a worktree with a git-ignored `.env.stream` that gives its compose project its own name and ports. Shared code lists get one marker comment per phase (B2–B11) so branches insert under their own marker. The dashboard's translation catalogue becomes one file per area. A standard-library Python ledger (`scripts/orchestration/ledger.py`), guarded by a file lock and committed on an `orchestration` branch, carries every cross-session fact; `launch-phase.sh` creates a phase's worktrees; two prompt files define the conductor's and the phase orchestrators' loops.

**Tech Stack:** bash, Python 3 standard library (`fcntl`, `argparse`, `unittest`), just 1.58, docker compose, Django (settings, pytest), React + Vite + i18next + vitest, Astro.

**Spec:** `docs/superpowers/specs/2026-10-02-parallel-orchestration-design.md`

**Starts after:** Plan 13 (`feat/features`) is merged in backend, dashboard and meta. Tasks 2 and 3 edit files Plan 13 also edits; re-read each file before editing and place markers by the rules here, not by line number.

**Branches:** `feat/orchestration` in meta (already holds the spec and this plan), `feat/orchestration` in backend, dashboard and marketing.

## Global Constraints

- Phase markers are exactly `── phase B2 ──` … `── phase B11 ──` (box-drawing U+2500), behind `#` in Python/TOML and `//` in TypeScript, in that order, ten per section.
- Stream slots are 1–4; slot 0 is the main checkout and has no `.env.stream`. Port = default + 100 × slot; the HTTP edge is 8080 + 100 × slot (slot 1 → 8180).
- With no `.env.stream`, every command behaves exactly as today (Caddy on 80, the same compose project name, the same URLs).
- Ledger code is Python 3 standard library only; it never imports Django or anything from the repos.
- Backend coverage ≥ 80 %; dashboard lines/statements ≥ 80, branches/functions ≥ 70.
- Commits end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## Review Focus

- A stream stack started while the main stack runs on port 80 — nothing collides, and the main stack is untouched (Task 1, `stream_env_test.sh` port table + manual check).
- A link in an email sent from a stream points at that stream's port, not port 80 (Task 1, compose interpolation check).
- Two sessions writing the ledger at the same moment — no lost update, no duplicate plan number (Task 4, concurrent `alloc-plan` test).
- A phase claiming a file another phase holds is refused; re-claiming its own claim is a no-op (Task 4, claim tests).
- Arabic plural forms (`_zero`, `_two`, `_few`, `_many`) do not break the `ar`/`en` parity test (Task 3, parity test strips plural suffixes).

---

### Task 1: Isolated dev stacks per worktree

**Files:**
- Create: `scripts/orchestration/stream-env.sh`
- Create: `scripts/orchestration/tests/stream_env_test.sh`
- Modify: `docker-compose.local.yml` (caddy ports; `x-django-env`; dashboard and marketing environment)
- Modify: `justfile` (dotenv settings at the top; `_urls`)
- Modify: `.env.example` (the port comment)
- Modify: `dashboard/vite.config.ts:28` (HMR client port)
- Modify: `marketing/astro.config.mjs:13` (HMR client port)

**Interfaces:**
- Produces: `bash scripts/orchestration/stream-env.sh <phase> <slot> [dir]` writes `<dir>/.env.stream` with `COMPOSE_PROJECT_NAME`, `ETQAN_HTTP_PORT`, `ETQAN_API_PORT`, `ETQAN_PG_PORT`, `ETQAN_REDIS_PORT`, `ETQAN_FLOWER_PORT`, `ETQAN_MAIL_UI_PORT`, `ETQAN_SMTP_PORT`, `ETQAN_URL_PORT_SUFFIX`, `E2E_APP_URL`, `E2E_DEMO_URL`, `E2E_OTHER_URL`. Exit 2 on bad arguments. Task 5's `launch-phase.sh` calls it.

- [ ] **Step 1: Write the failing test**

`scripts/orchestration/tests/stream_env_test.sh`:

```bash
#!/usr/bin/env bash
# stream-env.sh writes one stream's ports (spec 2026-10-02 §3.3).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../stream-env.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

bash "$script" b3 1 "$tmp"
env_file="$tmp/.env.stream"
expect() { grep -qx "$1" "$env_file" || fail "missing '$1' in: $(cat "$env_file")"; }
expect "COMPOSE_PROJECT_NAME=etqan-b3"
expect "ETQAN_HTTP_PORT=8180"
expect "ETQAN_API_PORT=8100"
expect "ETQAN_PG_PORT=5532"
expect "ETQAN_REDIS_PORT=6479"
expect "ETQAN_FLOWER_PORT=5655"
expect "ETQAN_MAIL_UI_PORT=8125"
expect "ETQAN_SMTP_PORT=1125"
expect "ETQAN_URL_PORT_SUFFIX=:8180"
expect "E2E_APP_URL=http://demo.etqan.localhost:8180"
expect "E2E_DEMO_URL=http://demo.etqan.localhost:8180"
expect "E2E_OTHER_URL=http://other.etqan.localhost:8180"

# No port is shared between any two slots, nor with the main stack (slot 0).
ports() { grep -E '^ETQAN_[A-Z_]+_PORT=' "$1" | cut -d= -f2; }
main_ports="80 8000 5432 6379 5555 8025 1025"
all="$main_ports"
for slot in 1 2 3 4; do
  bash "$script" "s$slot" "$slot" "$tmp"
  all="$all $(ports "$tmp/.env.stream" | tr '\n' ' ')"
done
dupes="$(tr ' ' '\n' <<<"$all" | grep -v '^$' | sort | uniq -d)"
[ -z "$dupes" ] || fail "ports shared between slots: $dupes"

# Bad arguments exit 2 and write nothing.
rm -f "$tmp/.env.stream"
for args in "b3 0" "b3 5" "B3 1" "b3 x" "b3"; do
  # shellcheck disable=SC2086
  if bash "$script" $args "$tmp" 2>/dev/null; then fail "accepted: $args"; fi
  [ ! -e "$tmp/.env.stream" ] || fail "wrote a file for: $args"
done
echo "stream_env_test: ok"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash scripts/orchestration/tests/stream_env_test.sh`
Expected: FAIL — `stream-env.sh: No such file or directory`.

- [ ] **Step 3: Write `stream-env.sh`**

```bash
#!/usr/bin/env bash
# Write <dir>/.env.stream for one orchestration stream (spec 2026-10-02 §3.3).
# `just` loads it (dotenv), so docker compose gets its own project name and
# ports, and the URLs (Vite/Astro HMR, emailed links, e2e) follow the port.
# Slot 0 is the main checkout, which has no .env.stream.
set -euo pipefail
usage() { echo "usage: stream-env.sh <phase> <slot 1-4> [dir]" >&2; exit 2; }
[ $# -ge 2 ] && [ $# -le 3 ] || usage
phase="$1"; slot="$2"; dir="${3:-.}"
[[ "$phase" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "phase must be lowercase letters, digits and dashes: $phase" >&2; exit 2; }
[[ "$slot" =~ ^[1-4]$ ]] || { echo "slot must be 1-4: $slot" >&2; exit 2; }
off=$((slot * 100))
http=$((8080 + off))
cat >"$dir/.env.stream" <<EOF
COMPOSE_PROJECT_NAME=etqan-$phase
ETQAN_HTTP_PORT=$http
ETQAN_API_PORT=$((8000 + off))
ETQAN_PG_PORT=$((5432 + off))
ETQAN_REDIS_PORT=$((6379 + off))
ETQAN_FLOWER_PORT=$((5555 + off))
ETQAN_MAIL_UI_PORT=$((8025 + off))
ETQAN_SMTP_PORT=$((1025 + off))
ETQAN_URL_PORT_SUFFIX=:$http
E2E_APP_URL=http://demo.etqan.localhost:$http
E2E_DEMO_URL=http://demo.etqan.localhost:$http
E2E_OTHER_URL=http://other.etqan.localhost:$http
EOF
echo "wrote $dir/.env.stream (slot $slot, http://demo.etqan.localhost:$http/)"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash scripts/orchestration/tests/stream_env_test.sh`
Expected: `stream_env_test: ok`

- [ ] **Step 5: Make compose, just and the dev servers read the stream's ports**

`docker-compose.local.yml`:

```yaml
x-django-env: &django-env
  DJANGO_SETTINGS_MODULE: config.settings.local
  DJANGO_READ_DOT_ENV_FILE: "True"
  DATABASE_URL: postgres://etqan:etqan@postgres:5432/etqan
  CELERY_BROKER_URL: redis://redis:6379/0
  DJANGO_TENANT_BASE_DOMAIN: etqan.localhost
  # An orchestration stream's edge is not on port 80 (.env.stream): emailed
  # links must carry its port. Empty outside a stream.
  DJANGO_TENANT_URL_TEMPLATE: http://{domain}${ETQAN_URL_PORT_SUFFIX:-}
  DJANGO_FRONTEND_URL: http://etqan.localhost${ETQAN_URL_PORT_SUFFIX:-}
```

```yaml
  caddy:
    image: caddy:2-alpine
    ports:
      - "${ETQAN_HTTP_PORT:-80}:80"
```

In the `dashboard` and `marketing` services' `environment:` lists, add:

```yaml
      - ETQAN_HMR_CLIENT_PORT=${ETQAN_HTTP_PORT:-80}
```

`dashboard/vite.config.ts` (server block):

```ts
    // The browser reaches Vite through Caddy: port 80, or an orchestration
    // stream's own port (ETQAN_HMR_CLIENT_PORT, from .env.stream).
    hmr: { clientPort: Number(process.env.ETQAN_HMR_CLIENT_PORT ?? 80) },
```

`marketing/astro.config.mjs` (vite.server):

```js
		server: {
			allowedHosts: true,
			hmr: { clientPort: Number(process.env.ETQAN_HMR_CLIENT_PORT ?? 80) },
		},
```

`justfile`, directly under the header comment:

```just
# Orchestration streams (docs/superpowers/specs/2026-10-02-parallel-orchestration-design.md §3.3):
# a phase worktree's git-ignored .env.stream sets COMPOSE_PROJECT_NAME and every
# port, so several stacks run side by side. Without the file nothing changes.
set dotenv-load := true
set dotenv-filename := ".env.stream"
```

`_urls` recipe — every URL gains the suffix:

```just
_urls:
    @echo "Academy site:    http://demo.etqan.localhost${ETQAN_URL_PORT_SUFFIX:-}/"
    @echo "Dashboard:       http://demo.etqan.localhost${ETQAN_URL_PORT_SUFFIX:-}/app/"
    @echo "API:             http://demo.etqan.localhost${ETQAN_URL_PORT_SUFFIX:-}/api/v1/"
    @echo "Staff admin:     http://etqan.localhost${ETQAN_URL_PORT_SUFFIX:-}/admin/"
    @echo "Mail / Flower:   http://mail.etqan.localhost${ETQAN_URL_PORT_SUFFIX:-}  http://flower.etqan.localhost${ETQAN_URL_PORT_SUFFIX:-}"
```

`.env.example` — replace the line `# Caddy, the local edge, always binds port 80 (http://*.etqan.localhost).` with:

```
# Caddy, the local edge, binds port 80 (http://*.etqan.localhost) unless
# ETQAN_HTTP_PORT says otherwise; scripts/orchestration/stream-env.sh writes a
# whole set into .env.stream for a parallel phase worktree.
# ETQAN_HTTP_PORT=80
```

- [ ] **Step 6: Verify compose interpolation both ways**

Run (from the meta root; `backend/.env` exists locally):

```bash
GH_TOKEN=x docker compose -f docker-compose.local.yml config | grep -E 'published: "80"|DJANGO_TENANT_URL_TEMPLATE: http://\{domain\}$|ETQAN_HMR_CLIENT_PORT: "80"'
bash scripts/orchestration/stream-env.sh b3 1 /tmp && set -a && . /tmp/.env.stream && set +a && \
GH_TOKEN=x docker compose -f docker-compose.local.yml config | grep -E 'name: etqan-b3|published: "8180"|DJANGO_TENANT_URL_TEMPLATE: http://\{domain\}:8180|ETQAN_HMR_CLIENT_PORT: "8180"'; rm /tmp/.env.stream
```

Expected: the first command prints the port-80 lines; the second prints the project name and all three `8180` lines.

- [ ] **Step 7: Prove two stacks side by side (manual)**

With the main stack up (`just dev-backend` in the meta root), create a throwaway worktree and start slot 1:

```bash
git worktree add /tmp/etqan-slot1 feat/orchestration
for s in backend dashboard marketing; do git -C $s worktree add --detach /tmp/etqan-slot1/$s HEAD; done
cp backend/.env /tmp/etqan-slot1/backend/.env
bash scripts/orchestration/stream-env.sh slot1 1 /tmp/etqan-slot1
(cd /tmp/etqan-slot1 && just setup && just dev-backend)
curl -sf http://demo.etqan.localhost/api/v1/site/branding/ >/dev/null && echo main-ok
curl -sf http://demo.etqan.localhost:8180/api/v1/site/branding/ >/dev/null && echo slot1-ok
curl -sf http://demo.etqan.localhost:8180/app/ | grep -q '<div id="root"' && echo slot1-app-ok
```

Expected: `main-ok`, `slot1-ok`, `slot1-app-ok`. Then tear down: `(cd /tmp/etqan-slot1 && just stop && docker compose -f docker-compose.local.yml down -v)`, `for s in backend dashboard marketing; do git -C $s worktree remove --force /tmp/etqan-slot1/$s; done`, `git worktree remove --force /tmp/etqan-slot1`.

- [ ] **Step 8: Commit (dashboard, marketing, then meta)**

```bash
git -C dashboard switch -c feat/orchestration && git -C dashboard add vite.config.ts && git -C dashboard commit -m "chore(dev): HMR client port follows the orchestration stream

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git -C marketing switch -c feat/orchestration && git -C marketing add astro.config.mjs && git -C marketing commit -m "chore(dev): HMR client port follows the orchestration stream

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git add scripts/orchestration docker-compose.local.yml justfile .env.example dashboard marketing
git commit -m "feat(orchestration): an isolated dev stack per phase worktree

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Phase sections in the backend's shared lists

**Files:**
- Create: `backend/etqan/platform/tests/test_phase_sections.py`
- Modify: `backend/config/settings/base.py` (end of `TENANT_APPS`)
- Modify: `backend/config/api_router.py` (before the `schema/` path)
- Modify: `backend/etqan/platform/features.py` (end of `REGISTRY`)
- Modify: `backend/etqan/access/registry.py` (end of `RESOURCES`)
- Modify: `backend/etqan/tenants/management/commands/seed_dev.py` (end of `seed_academy`'s `with` block)
- Modify: `backend/pyproject.toml` (the platform contract's `forbidden_modules`; the end of the file)

**Interfaces:**
- Produces: the marker sections every phase orchestrator inserts under (named in Task 5's `PHASE_PROMPT.md`).

- [ ] **Step 1: Write the failing test**

```python
"""Spec 2026-10-02 §6.1: every shared list keeps one marker per phase, in
order, so parallel phase branches each insert under their own marker and
merge without conflict. The files are read as text: nothing is imported."""

import re
from pathlib import Path

import pytest

BACKEND = Path(__file__).resolve().parents[3]
PHASES = [f"B{n}" for n in range(2, 12)]
MARKER = re.compile(r"── phase (B\d+) ──")
# path → how many sections of markers it holds.
SECTIONS = {
    "config/settings/base.py": 1,
    "config/api_router.py": 1,
    "etqan/platform/features.py": 1,
    "etqan/access/registry.py": 1,
    "etqan/tenants/management/commands/seed_dev.py": 1,
    "pyproject.toml": 2,
}


@pytest.mark.parametrize("relative", sorted(SECTIONS))
def test_every_phase_has_its_marker_in_order(relative):
    found = MARKER.findall((BACKEND / relative).read_text(encoding="utf-8"))
    assert found == PHASES * SECTIONS[relative]
```

- [ ] **Step 2: Run it to verify it fails**

Run: `just test-backend` with `-k phase_sections`, i.e.
`HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm django pytest etqan/platform/tests/test_phase_sections.py -v`
Expected: 6 FAIL (`assert [] == ['B2', …]`).

- [ ] **Step 3: Add the markers**

The ten-line block, in Python (indent to match the list it sits in):

```python
    # ── phase B2 ──
    # ── phase B3 ──
    # ── phase B4 ──
    # ── phase B5 ──
    # ── phase B6 ──
    # ── phase B7 ──
    # ── phase B8 ──
    # ── phase B9 ──
    # ── phase B10 ──
    # ── phase B11 ──
```

Placement:
1. `config/settings/base.py`: after `"etqan.access",`, before the `]` closing `TENANT_APPS`. Above the block add: `    # Parallel phases (spec 2026-10-02 §6.1): add a phase's apps under its own marker.`
2. `config/api_router.py`: after the `access/` path, before `# OpenAPI schema`. Same lead comment, with "routes" for "apps".
3. `etqan/platform/features.py`: the last lines of the `REGISTRY` tuple, before `)`. Lead comment: `    # Parallel phases: a phase flips its own lines above to _built in place; a feature TutorHamster lacks goes under its marker.`
4. `etqan/access/registry.py`: the last lines of `RESOURCES`, before `)`. Lead comment: `    # Parallel phases (spec 2026-10-02 §6.1): a phase's new resources go under its marker.`
5. `seed_dev.py`: inside `seed_academy`'s `with tenant_context(academy):` block, after `seed_notifications(NOTIFIED.get(subdomain))`, indented 8 spaces. Lead comment: `        # Parallel phases: a phase's seed steps go under its marker; its data and functions in its own module under etqan/tenants/seeds/.` Also create `backend/etqan/tenants/seeds/__init__.py` with the docstring `"""Demo seed steps added by the parallel phases (spec 2026-10-02 §6.1), one module per phase."""` so the first phase has the package to add its module to.
6. `pyproject.toml`, the contract `"platform imports no business modules"`: rewrite `forbidden_modules` one module per line, then the block (TOML comments, indented 4):

```toml
forbidden_modules = [
    "etqan.identity",
    "etqan.tenants",
    "etqan.site",
    "etqan.academy",
    "etqan.catalogue",
    "etqan.scheduling",
    "etqan.billing",
    "etqan.payroll",
    "etqan.notifications",
    "etqan.access",
    # Parallel phases (spec 2026-10-02 §6.1): every new app is forbidden to platform, under its phase's marker.
    # ── phase B2 ──
    # ── phase B3 ──
    # ── phase B4 ──
    # ── phase B5 ──
    # ── phase B6 ──
    # ── phase B7 ──
    # ── phase B8 ──
    # ── phase B9 ──
    # ── phase B10 ──
    # ── phase B11 ──
]
```

7. `pyproject.toml`, end of file: a blank line, then `# Parallel phases (spec 2026-10-02 §6.1): a phase's new contracts go under its marker.` and the ten markers unindented, each followed by a blank line (so a contract table inserted under one marker is separated from the next marker).

- [ ] **Step 4: Run the test, lint, boundaries and the seed**

Run: `HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f docker-compose.local.yml run --rm django pytest etqan/platform/tests/test_phase_sections.py -v`
Expected: 6 PASS.
Run: `just lint-backend && just check-boundaries && just seed`
Expected: ruff clean (ruff format leaves standalone comments in place; if it reports a diff, run `ruff format` and re-check the markers are still in order), import-linter `Contracts: N kept, 0 broken.`, `seed_dev` prints `exists: demo` / `exists: other`.

- [ ] **Step 5: Run the backend suite and commit**

Run: `just test-backend`
Expected: all pass, coverage ≥ 80 %.

```bash
git -C backend switch -c feat/orchestration
git -C backend add config/settings/base.py config/api_router.py etqan/platform/features.py etqan/access/registry.py etqan/tenants/management/commands/seed_dev.py etqan/tenants/seeds/__init__.py pyproject.toml etqan/platform/tests/test_phase_sections.py
git -C backend commit -m "chore: phase sections in the shared lists, for parallel phases

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Dashboard — one translation file per area; nav phase sections

**Files:**
- Create: `dashboard/src/lib/catalogue.ts`
- Create: `dashboard/src/lib/catalogue.test.ts`
- Create: `dashboard/src/locales/locales.test.ts`
- Create: `dashboard/src/locales/{en,ar}/<area>.json` (one per top-level key of today's `common.json`)
- Modify: `dashboard/src/lib/i18n.ts`
- Modify: `dashboard/src/features/shell/nav.ts` (`NAV_ITEMS` markers; `groupNavItems`)
- Modify: `dashboard/src/features/shell/nav.test.ts`

**Interfaces:**
- Produces: `catalogue(files: Record<string, Record<string, unknown>>, lng: string): Record<string, unknown>` — the `common` namespace for one language, keyed by file name.
- Produces: `groupNavItems(items)` groups by first appearance of each group (no longer only consecutive runs), so a phase's items under its own marker still join their existing group.

- [ ] **Step 1: Write the failing tests**

`dashboard/src/lib/catalogue.test.ts`:

```ts
import { catalogue } from "./catalogue";

const files = {
	"../locales/en/billing.json": { title: "Invoices" },
	"../locales/en/nav.json": { invoices: "Invoices" },
	"../locales/ar/billing.json": { title: "الفواتير" },
	"../locales/en/README.md": { ignored: true },
};

describe("catalogue", () => {
	it("keys each file of one language by its name", () => {
		expect(catalogue(files, "en")).toEqual({
			billing: { title: "Invoices" },
			nav: { invoices: "Invoices" },
		});
	});

	it("leaves out the other languages", () => {
		expect(catalogue(files, "ar")).toEqual({ billing: { title: "الفواتير" } });
	});

	it("is empty for a language with no files", () => {
		expect(catalogue(files, "fr")).toEqual({});
	});
});
```

`dashboard/src/locales/locales.test.ts`:

```ts
// Spec 2026-10-02 §6.1: one file per area; ar and en must stay key-for-key
// equal. Arabic has more plural forms than English, so plural suffixes are
// compared as one key.
const files = import.meta.glob<Record<string, unknown>>("./*/*.json", {
	eager: true,
	import: "default",
});

const PLURAL = /_(zero|one|two|few|many|other)$/;

function leaves(value: unknown, prefix: string): string[] {
	if (value === null || typeof value !== "object") {
		return [prefix.replace(PLURAL, "")];
	}
	return Object.entries(value as Record<string, unknown>).flatMap(([k, v]) =>
		leaves(v, `${prefix}.${k}`),
	);
}

function keysOf(lng: string): string[] {
	const keys = Object.entries(files)
		.filter(([path]) => path.startsWith(`./${lng}/`))
		.flatMap(([path, json]) =>
			leaves(json, path.slice(lng.length + 3, -".json".length)),
		);
	return [...new Set(keys)].sort();
}

describe("locales", () => {
	it("has one file per area, the same in both languages", () => {
		const names = (lng: string) =>
			Object.keys(files)
				.filter((p) => p.startsWith(`./${lng}/`))
				.map((p) => p.slice(lng.length + 3))
				.sort();
		expect(names("ar")).toEqual(names("en"));
		expect(names("en")).toContain("nav.json");
	});

	it("has the same keys in Arabic and English", () => {
		expect(keysOf("ar")).toEqual(keysOf("en"));
	});
});
```

In `dashboard/src/features/shell/nav.test.ts`, add:

```ts
import navSource from "./nav.ts?raw";

describe("groupNavItems by first appearance", () => {
	it("joins a later item to the group it first appeared in", () => {
		const a = { to: "/a", labelKey: "a", icon: Home, group: "billing" as const };
		const b = { to: "/b", labelKey: "b", icon: Home, group: "payroll" as const };
		const c = { to: "/c", labelKey: "c", icon: Home, group: "billing" as const };
		const top = { to: "/", labelKey: "home", icon: Home };
		expect(groupNavItems([top, a, b, c])).toEqual([
			{ group: undefined, items: [top] },
			{ group: "billing", items: [a, c] },
			{ group: "payroll", items: [b] },
		]);
	});

	it("keeps ungrouped items where they stand", () => {
		const top = { to: "/", labelKey: "home", icon: Home };
		const a = { to: "/a", labelKey: "a", icon: Home, group: "billing" as const };
		const end = { to: "/account", labelKey: "account", icon: Home };
		expect(groupNavItems([top, a, end])).toEqual([
			{ group: undefined, items: [top] },
			{ group: "billing", items: [a] },
			{ group: undefined, items: [end] },
		]);
	});
});

describe("NAV_ITEMS phase sections", () => {
	it("has one marker per phase, in order (spec 2026-10-02 §6.1)", () => {
		const found = [...navSource.matchAll(/── phase (B\d+) ──/g)].map((m) => m[1]);
		expect(found).toEqual(
			Array.from({ length: 10 }, (_, i) => `B${i + 2}`),
		);
	});
});
```

(Import `Home` from `lucide-react` and `groupNavItems` from `./nav` if the file does not already.)

- [ ] **Step 2: Run them to verify they fail**

Run: `cd dashboard && pnpm vitest run src/lib/catalogue.test.ts src/locales/locales.test.ts src/features/shell/nav.test.ts`
Expected: catalogue — cannot resolve `./catalogue`; locales — `names("en")` lacks `nav.json`; nav — the first-appearance test gets two `billing` groups and the marker test gets `[]`.

- [ ] **Step 3: Split the catalogues**

Run from `dashboard/` (reads both files before writing, because the `common` key becomes the new `common.json`):

```bash
node -e '
const fs = require("fs");
for (const lng of ["en", "ar"]) {
  const dir = `src/locales/${lng}`;
  const whole = JSON.parse(fs.readFileSync(`${dir}/common.json`, "utf8"));
  fs.unlinkSync(`${dir}/common.json`);
  for (const [key, value] of Object.entries(whole)) {
    fs.writeFileSync(`${dir}/${key}.json`, JSON.stringify(value, null, "\t") + "\n");
  }
}'
ls src/locales/en src/locales/ar
```

Expected: 18 files in each (`access.json` … `website.json`).

- [ ] **Step 4: Write `catalogue.ts` and load it in `i18n.ts`**

`dashboard/src/lib/catalogue.ts`:

```ts
/** Spec 2026-10-02 §6.1: each top-level key of the `common` namespace lives
 * in its own file, `locales/<lng>/<key>.json`, so parallel phases add a file
 * instead of editing one shared catalogue. No `t()` call changes. */
export type CatalogueFiles = Record<string, Record<string, unknown>>;

const PATH = /\/locales\/([^/]+)\/([^/]+)\.json$/;

export function catalogue(
	files: CatalogueFiles,
	lng: string,
): Record<string, unknown> {
	const out: Record<string, unknown> = {};
	for (const [path, contents] of Object.entries(files)) {
		const match = path.match(PATH);
		if (match && match[1] === lng) out[match[2]] = contents;
	}
	return out;
}
```

`dashboard/src/lib/i18n.ts` — replace the two JSON imports and the `resources` line:

```ts
import i18n from "i18next";
import { initReactI18next } from "react-i18next";
import { type CatalogueFiles, catalogue } from "@/lib/catalogue";

const files: CatalogueFiles = import.meta.glob("../locales/*/*.json", {
	eager: true,
	import: "default",
});
```

```ts
	resources: {
		en: { common: catalogue(files, "en") },
		ar: { common: catalogue(files, "ar") },
	},
```

- [ ] **Step 5: Group by first appearance; add the nav markers**

`groupNavItems` in `nav.ts`:

```ts
/** Groups items by the first appearance of their group, keeping that order;
 * ungrouped items stand alone where they are. A phase's items listed under
 * its own marker (spec 2026-10-02 §6.1) still join their group. */
export function groupNavItems(
	items: NavItem[],
): { group?: NavGroup; items: NavItem[] }[] {
	const groups: { group?: NavGroup; items: NavItem[] }[] = [];
	for (const item of items) {
		const existing =
			item.group === undefined
				? undefined
				: groups.find((g) => g.group === item.group);
		if (existing) existing.items.push(item);
		else groups.push({ group: item.group, items: [item] });
	}
	return groups;
}
```

In `NAV_ITEMS`, directly before `{ to: "/account", labelKey: "auth.account", icon: User },`:

```ts
	// Parallel phases (spec 2026-10-02 §6.1): a phase's items go under its own
	// marker; groupNavItems still files them with their group.
	// ── phase B2 ──
	// ── phase B3 ──
	// ── phase B4 ──
	// ── phase B5 ──
	// ── phase B6 ──
	// ── phase B7 ──
	// ── phase B8 ──
	// ── phase B9 ──
	// ── phase B10 ──
	// ── phase B11 ──
```

- [ ] **Step 6: Run the tests, the full suite, coverage and lint**

Run: `cd dashboard && pnpm vitest run src/lib/catalogue.test.ts src/locales/locales.test.ts src/features/shell/nav.test.ts`
Expected: all PASS.
Run: `pnpm tsc --noEmit && pnpm test:coverage && pnpm lint`
Expected: clean; thresholds met; every existing screen test still finds its strings (the catalogue's shape is unchanged).
Run (stack up): open `http://demo.etqan.localhost/app/`, sign in as the demo admin, switch to Arabic and back.
Expected: labels in both languages, no raw keys such as `nav.invoices`.

- [ ] **Step 7: Commit**

```bash
git -C dashboard add src/lib/catalogue.ts src/lib/catalogue.test.ts src/lib/i18n.ts src/locales src/features/shell/nav.ts src/features/shell/nav.test.ts
git -C dashboard commit -m "chore(i18n): one catalogue file per area; nav phase sections

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: The ledger tool

**Files:**
- Create: `scripts/orchestration/ledger.py`
- Create: `scripts/orchestration/tests/test_ledger.py`

**Interfaces:**
- Produces (CLI, every command takes `--dir <ledger worktree>`, default `$ETQAN_LEDGER_DIR` or `<main checkout's parent>/etqan_tutor-wt/_ledger`):
  - `init` — writes `orchestration/ledger.json`, `orchestration/LEDGER.md`, `.gitignore`.
  - `show [--json]`, `eligible` (prints `free=<n>` then eligible phase codes, priority order).
  - `phase <code> [--status S] [--slot N] [--worktree P] [--branch B] [--spec PATH] [--slice ID] [--task TEXT]`
  - `slice <id> [--phase CODE] [--requires a,b] [--status S] [--spec P] [--plan P] [--prs TEXT]`
  - `alloc-plan <slice>` (prints the number), `ready <slice>` (exit 0, or 1 and the unmet slices)
  - `queue <slice>`, `next` (prints the slice put in flight, or nothing), `merged <slice> --head repo=sha …`, `bounce <slice> --reason TEXT`
  - `decide <phase> TEXT --affects a,b --source TEXT`, `claim <phase> TARGET --reason TEXT`, `release <phase> TARGET`, `request <phase> APP TEXT`, `escalate <phase> KIND TEXT`, `resolve <id> TEXT`
- Python functions (tests call them): `empty() -> dict`, `set_phase`, `add_slice`, `set_slice`, `alloc_plan`, `unmet`, `enqueue`, `take_next`, `mark_merged`, `bounce`, `decide`, `claim`, `release`, `request`, `escalate`, `resolve`, `eligible(data) -> tuple[int, list[str]]`, `render(data) -> str`, `LedgerError`.

- [ ] **Step 1: Write the failing tests**

`scripts/orchestration/tests/test_ledger.py`:

```python
"""The orchestration ledger (spec 2026-10-02 §4). Run with
`python3 -m unittest discover -s scripts/orchestration/tests`."""

import json
import subprocess
import sys
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE.parent / "ledger.py"
sys.path.insert(0, str(HERE.parent))

import ledger as L  # noqa: E402


def cli(directory, *args):
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--dir", str(directory), *args],
        capture_output=True,
        text=True,
    )


class PhasesAndSlots(unittest.TestCase):
    def test_empty_ledger_lists_every_phase_waiting(self):
        data = L.empty()
        self.assertEqual(list(data["phases"]), [f"B{n}" for n in range(2, 12)])
        self.assertTrue(all(p["status"] == "waiting-deps" for p in data["phases"].values()))
        self.assertEqual(data["next_plan_number"], 15)

    def test_a_slot_is_held_by_one_active_phase(self):
        data = L.empty()
        L.set_phase(data, "B2", status="spec", slot=1)
        with self.assertRaisesRegex(L.LedgerError, "slot 1 is held by B2"):
            L.set_phase(data, "B3", status="spec", slot=1)

    def test_a_merged_phase_frees_its_slot(self):
        data = L.empty()
        L.set_phase(data, "B8", status="spec", slot=3)
        L.set_phase(data, "B8", status="merged")
        self.assertIsNone(data["phases"]["B8"]["slot"])
        L.set_phase(data, "B6", status="spec", slot=3)

    def test_unknown_status_and_slot_are_refused(self):
        data = L.empty()
        with self.assertRaises(L.LedgerError):
            L.set_phase(data, "B2", status="done")
        with self.assertRaises(L.LedgerError):
            L.set_phase(data, "B2", slot=5)

    def test_eligible_needs_dependency_specs_and_free_slots(self):
        data = L.empty()
        free, codes = L.eligible(data)
        self.assertEqual((free, codes), (4, ["B2", "B3", "B8", "B9"]))
        for slot, code in enumerate(["B2", "B3", "B8", "B9"], start=1):
            L.set_phase(data, code, status="spec", slot=slot)
        self.assertEqual(L.eligible(data), (0, []))
        L.set_phase(data, "B2", spec="docs/b2.md")
        L.set_phase(data, "B8", status="merged")
        # B6 and B5 now qualify (B4 also needs B3's spec); one slot is free.
        self.assertEqual(L.eligible(data), (1, ["B6"]))


class SlicesAndQueue(unittest.TestCase):
    def setUp(self):
        self.data = L.empty()
        L.add_slice(self.data, "B3a", phase="B3", requires=[])
        L.add_slice(self.data, "B4a", phase="B4", requires=["B2b", "B3a"])

    def test_a_slice_belongs_to_its_phase(self):
        with self.assertRaisesRegex(L.LedgerError, "must start with B2"):
            L.add_slice(self.data, "B3z", phase="B2", requires=[])

    def test_plan_numbers_are_allocated_once(self):
        self.assertEqual(L.alloc_plan(self.data, "B3a"), 15)
        self.assertEqual(L.alloc_plan(self.data, "B3a"), 15)
        self.assertEqual(L.alloc_plan(self.data, "B4a"), 16)

    def test_unmet_lists_unmerged_and_unknown_requirements(self):
        self.assertEqual(L.unmet(self.data, "B4a"), ["B2b", "B3a"])
        L.enqueue(self.data, "B3a")
        L.take_next(self.data)
        L.mark_merged(self.data, "B3a", {"backend": "abc"})
        self.assertEqual(L.unmet(self.data, "B4a"), ["B2b"])
        self.assertEqual(self.data["main_heads"], {"backend": "abc"})

    def test_one_slice_in_flight_at_a_time(self):
        L.add_slice(self.data, "B3b", phase="B3", requires=[])
        L.enqueue(self.data, "B3a")
        L.enqueue(self.data, "B3b")
        self.assertEqual(L.take_next(self.data), "B3a")
        with self.assertRaisesRegex(L.LedgerError, "B3a is in flight"):
            L.take_next(self.data)
        L.bounce(self.data, "B3a", "CI red")
        self.assertEqual(self.data["slices"]["B3a"]["status"], "build")
        self.assertEqual(L.take_next(self.data), "B3b")

    def test_queueing_twice_is_refused(self):
        L.enqueue(self.data, "B3a")
        with self.assertRaises(L.LedgerError):
            L.enqueue(self.data, "B3a")

    def test_a_third_bounce_escalates(self):
        for _ in range(3):
            L.enqueue(self.data, "B3a")
            L.take_next(self.data)
            L.bounce(self.data, "B3a", "CI red")
        kinds = [e["kind"] for e in self.data["escalations"]]
        self.assertEqual(kinds, ["queue-failures"])


class ClaimsDecisionsEscalations(unittest.TestCase):
    def test_a_claim_held_by_another_phase_is_refused(self):
        data = L.empty()
        L.claim(data, "B3", "etqan.catalogue.models", "price field")
        L.claim(data, "B3", "etqan.catalogue.models", "again")  # own: no-op
        self.assertEqual(len(data["claims"]), 1)
        with self.assertRaisesRegex(L.LedgerError, "claimed by B3"):
            L.claim(data, "B2", "etqan.catalogue.models", "x")
        with self.assertRaises(L.LedgerError):
            L.release(data, "B2", "etqan.catalogue.models")
        L.release(data, "B3", "etqan.catalogue.models")
        self.assertEqual(data["claims"], [])

    def test_requests_go_to_the_owner(self):
        data = L.empty()
        rid = L.request(data, "B4", "scheduling", "session class field")
        self.assertEqual(rid, "R1")
        self.assertEqual(data["requests"][0]["owner"], "B2")
        L.request(data, "B4", "unowned_app", "x")
        self.assertEqual(data["requests"][1]["owner"], "conductor")

    def test_decisions_and_escalations_are_numbered(self):
        data = L.empty()
        self.assertEqual(L.decide(data, "B3", "wallet on Student", ["B4"], "audit §2"), "D1")
        self.assertEqual(L.escalate(data, "B3", "money", "live Stripe keys?"), "E1")
        with self.assertRaises(L.LedgerError):
            L.escalate(data, "B3", "whim", "x")
        L.resolve(data, "E1", "use test keys")
        self.assertEqual(data["escalations"][0]["status"], "resolved")

    def test_render_shows_open_escalations_and_the_queue(self):
        data = L.empty()
        L.add_slice(data, "B3a", phase="B3", requires=[])
        L.enqueue(data, "B3a")
        L.escalate(data, "B3", "money", "live keys?")
        text = L.render(data)
        self.assertIn("| B3a |", text)
        self.assertIn("live keys?", text)


class Cli(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        subprocess.run(["git", "init", "-q", "-b", "orchestration", str(self.dir)], check=True)
        for key, value in (("user.name", "t"), ("user.email", "t@t")):
            subprocess.run(["git", "-C", str(self.dir), "config", key, value], check=True)

    def tearDown(self):
        self.tmp.cleanup()

    def test_init_then_each_write_is_a_commit(self):
        self.assertEqual(cli(self.dir, "init").returncode, 0)
        self.assertEqual(cli(self.dir, "phase", "B2", "--status", "spec", "--slot", "1").returncode, 0)
        log = subprocess.run(
            ["git", "-C", str(self.dir), "log", "--format=%s"], capture_output=True, text=True
        ).stdout.splitlines()
        self.assertEqual(log, ["ledger: phase B2", "ledger: init"])
        self.assertIn("| B2 |", (self.dir / "orchestration/LEDGER.md").read_text())
        status = subprocess.run(
            ["git", "-C", str(self.dir), "status", "--porcelain"], capture_output=True, text=True
        ).stdout
        self.assertEqual(status, "")  # .lock is ignored

    def test_errors_exit_1_without_writing(self):
        cli(self.dir, "init")
        cli(self.dir, "phase", "B2", "--slot", "1", "--status", "spec")
        before = (self.dir / "orchestration/ledger.json").read_text()
        result = cli(self.dir, "phase", "B3", "--slot", "1", "--status", "spec")
        self.assertEqual(result.returncode, 1)
        self.assertIn("slot 1 is held by B2", result.stderr)
        self.assertEqual((self.dir / "orchestration/ledger.json").read_text(), before)

    def test_ready_exit_code(self):
        cli(self.dir, "init")
        cli(self.dir, "slice", "B4a", "--phase", "B4", "--requires", "B3a")
        result = cli(self.dir, "ready", "B4a")
        self.assertEqual((result.returncode, result.stdout.strip()), (1, "B3a"))

    def test_concurrent_writers_lose_nothing(self):
        cli(self.dir, "init")
        slices = [f"B3{chr(97 + i)}" for i in range(10)]
        for sid in slices:
            cli(self.dir, "slice", sid, "--phase", "B3")
        with ThreadPoolExecutor(max_workers=10) as pool:
            numbers = list(pool.map(lambda s: cli(self.dir, "alloc-plan", s).stdout.strip(), slices))
        self.assertEqual(sorted(int(n) for n in numbers), list(range(15, 25)))
        data = json.loads((self.dir / "orchestration/ledger.json").read_text())
        self.assertEqual(data["next_plan_number"], 25)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them to verify they fail**

Run: `python3 -m unittest discover -s scripts/orchestration/tests -v`
Expected: ERROR — `ModuleNotFoundError: No module named 'ledger'`.

- [ ] **Step 3: Write `ledger.py`**

```python
#!/usr/bin/env python3
"""The orchestration ledger (docs/superpowers/specs/2026-10-02-parallel-orchestration-design.md §4).

One JSON file every session edits under an exclusive file lock; after each
change LEDGER.md is re-rendered and both are committed on the
`orchestration` branch. Standard library only."""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import json
import subprocess
import sys
from pathlib import Path

PHASES = {
    "B2": ("Scheduling depth", []),
    "B3": ("Money depth", []),
    "B4": ("Payroll depth", ["B2", "B3"]),
    "B5": ("Communication", ["B2"]),
    "B6": ("Learning", ["B2"]),
    "B7": ("Add-on sales", ["B3"]),
    "B8": ("Marketing extras", []),
    "B9": ("Platform extras", []),
    "B10": ("AI", ["B6"]),
    "B11": ("Apps", ["B2", "B3", "B4", "B5"]),
}
PRIORITY = ("B2", "B3", "B8", "B9", "B6", "B5", "B4", "B7", "B10", "B11")
SLOTS = 4
STATUSES = ("waiting-deps", "spec", "plan", "build", "review", "queued", "merged", "paused")
INACTIVE = ("waiting-deps", "merged")
SLICE_STATUSES = ("spec", "plan", "build", "review", "queued", "in-flight", "merged")
OWNERSHIP = {
    "scheduling": "B2",
    "billing": "B3",
    "catalogue.pricing": "B3",
    "payroll": "B4",
    "notifications": "B5",
    "site": "B8",
    "identity.auth": "B9",
}
ESCALATION_KINDS = (
    "money",
    "irreversible-data",
    "shared-decision",
    "queue-failures",
    "production",
    "stalled",
)
FIRST_PLAN = 15
MAX_BOUNCES = 3


class LedgerError(Exception):
    """A refused change; the CLI prints it and exits 1 without writing."""


def empty() -> dict:
    return {
        "phases": {
            code: {
                "title": title,
                "status": "waiting-deps",
                "requires": list(requires),
                "slot": None,
                "worktree": None,
                "branch": None,
                "spec": None,
                "current_slice": None,
                "current_task": None,
            }
            for code, (title, requires) in PHASES.items()
        },
        "slices": {},
        "next_plan_number": FIRST_PLAN,
        "ownership": dict(OWNERSHIP),
        "claims": [],
        "shared_decisions": [],
        "requests": [],
        "queue": [],
        "in_flight": None,
        "main_heads": {},
        "escalations": [],
    }


def _phase(data: dict, code: str) -> dict:
    try:
        return data["phases"][code]
    except KeyError:
        raise LedgerError(f"unknown phase {code}") from None


def _slice(data: dict, sid: str) -> dict:
    try:
        return data["slices"][sid]
    except KeyError:
        raise LedgerError(f"unknown slice {sid}") from None


def set_phase(data: dict, code: str, **fields) -> None:
    phase = _phase(data, code)
    status = fields.get("status")
    if status is not None and status not in STATUSES:
        raise LedgerError(f"unknown status {status}; one of {', '.join(STATUSES)}")
    slot = fields.get("slot")
    if slot is not None:
        if not 1 <= slot <= SLOTS:
            raise LedgerError(f"slot must be 1-{SLOTS}")
        for other_code, other in data["phases"].items():
            if other_code != code and other["slot"] == slot and other["status"] not in INACTIVE:
                raise LedgerError(f"slot {slot} is held by {other_code}")
    phase.update({key: value for key, value in fields.items() if value is not None})
    if phase["status"] == "merged":
        phase["slot"] = None


def add_slice(data: dict, sid: str, *, phase: str, requires: list[str]) -> None:
    _phase(data, phase)
    if not (sid.startswith(phase) and sid[len(phase):].isalpha()):
        raise LedgerError(f"slice {sid} must start with {phase} and end in letters")
    entry = data["slices"].setdefault(
        sid,
        {"phase": phase, "status": "spec", "requires": [], "plan_number": None,
         "spec": None, "plan": None, "prs": None, "bounces": 0},
    )
    if requires:
        entry["requires"] = list(requires)


def set_slice(data: dict, sid: str, **fields) -> None:
    entry = _slice(data, sid)
    status = fields.get("status")
    if status is not None and status not in SLICE_STATUSES:
        raise LedgerError(f"unknown slice status {status}")
    entry.update({key: value for key, value in fields.items() if value is not None})


def alloc_plan(data: dict, sid: str) -> int:
    entry = _slice(data, sid)
    if entry["plan_number"] is None:
        entry["plan_number"] = data["next_plan_number"]
        data["next_plan_number"] += 1
    return entry["plan_number"]


def unmet(data: dict, sid: str) -> list[str]:
    return [
        need for need in _slice(data, sid)["requires"]
        if data["slices"].get(need, {}).get("status") != "merged"
    ]


def enqueue(data: dict, sid: str) -> None:
    entry = _slice(data, sid)
    if sid in data["queue"] or data["in_flight"] == sid:
        raise LedgerError(f"{sid} is already queued")
    entry["status"] = "queued"
    data["queue"].append(sid)


def take_next(data: dict) -> str | None:
    if data["in_flight"]:
        raise LedgerError(f"{data['in_flight']} is in flight")
    if not data["queue"]:
        return None
    sid = data["queue"].pop(0)
    data["in_flight"] = sid
    data["slices"][sid]["status"] = "in-flight"
    return sid


def _in_flight(data: dict, sid: str) -> dict:
    if data["in_flight"] != sid:
        raise LedgerError(f"{sid} is not in flight")
    data["in_flight"] = None
    return data["slices"][sid]


def mark_merged(data: dict, sid: str, heads: dict[str, str]) -> None:
    _in_flight(data, sid)["status"] = "merged"
    data["main_heads"].update(heads)


def bounce(data: dict, sid: str, reason: str) -> None:
    entry = _in_flight(data, sid)
    entry["status"] = "build"
    entry["bounces"] += 1
    entry["last_bounce"] = reason
    if entry["bounces"] == MAX_BOUNCES:
        escalate(data, entry["phase"], "queue-failures", f"{sid} bounced {MAX_BOUNCES} times: {reason}")


def _next_id(items: list, prefix: str) -> str:
    return f"{prefix}{len(items) + 1}"


def decide(data: dict, phase: str, text: str, affects: list[str], source: str) -> str:
    _phase(data, phase)
    did = _next_id(data["shared_decisions"], "D")
    data["shared_decisions"].append(
        {"id": did, "phase": phase, "decision": text, "affects": affects, "source": source}
    )
    return did


def claim(data: dict, phase: str, target: str, reason: str) -> None:
    _phase(data, phase)
    for held in data["claims"]:
        if held["target"] == target:
            if held["phase"] == phase:
                return
            raise LedgerError(f"{target} is claimed by {held['phase']}")
    data["claims"].append({"target": target, "phase": phase, "reason": reason})


def release(data: dict, phase: str, target: str) -> None:
    for held in data["claims"]:
        if held["target"] == target and held["phase"] == phase:
            data["claims"].remove(held)
            return
    raise LedgerError(f"{phase} holds no claim on {target}")


def request(data: dict, phase: str, app: str, what: str) -> str:
    _phase(data, phase)
    rid = _next_id(data["requests"], "R")
    owner = data["ownership"].get(app, "conductor")
    data["requests"].append(
        {"id": rid, "from": phase, "app": app, "owner": owner, "what": what, "status": "open"}
    )
    return rid


def escalate(data: dict, phase: str, kind: str, question: str) -> str:
    _phase(data, phase)
    if kind not in ESCALATION_KINDS:
        raise LedgerError(f"unknown escalation kind {kind}; one of {', '.join(ESCALATION_KINDS)}")
    eid = _next_id(data["escalations"], "E")
    data["escalations"].append(
        {"id": eid, "phase": phase, "kind": kind, "question": question,
         "status": "open", "answer": None}
    )
    return eid


def resolve(data: dict, eid: str, answer: str) -> None:
    for item in data["escalations"]:
        if item["id"] == eid:
            item.update(status="resolved", answer=answer)
            return
    raise LedgerError(f"unknown escalation {eid}")


def eligible(data: dict) -> tuple[int, list[str]]:
    phases = data["phases"]
    active = sum(1 for p in phases.values() if p["status"] not in INACTIVE)
    free = max(SLOTS - active, 0)
    ready = [
        code for code in PRIORITY
        if phases[code]["status"] == "waiting-deps"
        and all(phases[need]["spec"] for need in phases[code]["requires"])
    ]
    return free, ready[:free]


def _cell(value) -> str:
    if value is None:
        return ""
    if isinstance(value, list):
        return ", ".join(str(v) for v in value)
    return str(value).replace("|", "\\|")


def _table(headers: list[str], rows: list[list]) -> list[str]:
    lines = ["| " + " | ".join(headers) + " |", "|" + "---|" * len(headers)]
    lines += ["| " + " | ".join(_cell(c) for c in row) + " |" for row in rows]
    return lines + [""]


def render(data: dict) -> str:
    out = ["# Orchestration ledger", "",
           "Generated by `scripts/orchestration/ledger.py` from `ledger.json`; never edit by hand.", "",
           f"In flight: **{data['in_flight'] or '—'}** · Queue: {', '.join(data['queue']) or '—'} · "
           f"Next plan number: {data['next_plan_number']}", "", "## Phases", ""]
    out += _table(
        ["Phase", "Title", "Status", "Slot", "Slice", "Task", "Requires", "Spec"],
        [[c, p["title"], p["status"], p["slot"], p["current_slice"], p["current_task"],
          p["requires"], p["spec"]] for c, p in data["phases"].items()],
    )
    out += ["## Slices", ""]
    out += _table(
        ["Slice", "Phase", "Status", "Plan", "Requires", "PRs", "Bounces"],
        [[s, e["phase"], e["status"], e["plan_number"], e["requires"], e["prs"], e["bounces"]]
         for s, e in data["slices"].items()],
    )
    out += ["## Open escalations", ""]
    out += _table(["Id", "Phase", "Kind", "Question"],
                  [[e["id"], e["phase"], e["kind"], e["question"]]
                   for e in data["escalations"] if e["status"] == "open"])
    out += ["## Shared decisions", ""]
    out += _table(["Id", "Phase", "Decision", "Affects", "Source"],
                  [[d["id"], d["phase"], d["decision"], d["affects"], d["source"]]
                   for d in data["shared_decisions"]])
    out += ["## Claims and requests", ""]
    out += _table(["Target", "Phase", "Reason"],
                  [[c["target"], c["phase"], c["reason"]] for c in data["claims"]])
    out += _table(["Id", "From", "App", "Owner", "What", "Status"],
                  [[r["id"], r["from"], r["app"], r["owner"], r["what"], r["status"]]
                   for r in data["requests"]])
    out += ["## Trunk heads", ""]
    out += _table(["Repo", "Commit"], [[r, h] for r, h in sorted(data["main_heads"].items())])
    return "\n".join(out)


def default_dir() -> Path:
    common = subprocess.run(
        ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    return Path(common).parent.parent / "etqan_tutor-wt" / "_ledger"


@contextlib.contextmanager
def locked(directory: Path, *, write: bool):
    directory.mkdir(parents=True, exist_ok=True)
    with open(directory / ".lock", "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX if write else fcntl.LOCK_SH)
        yield


def load(directory: Path) -> dict:
    path = directory / "orchestration" / "ledger.json"
    if not path.exists():
        raise LedgerError(f"no ledger at {path}; run `ledger.py init`")
    return json.loads(path.read_text(encoding="utf-8"))


def save(directory: Path, data: dict, message: str) -> None:
    folder = directory / "orchestration"
    folder.mkdir(exist_ok=True)
    (folder / "ledger.json").write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (folder / "LEDGER.md").write_text(render(data) + "\n", encoding="utf-8")
    (directory / ".gitignore").write_text(".lock\n", encoding="utf-8")
    if (directory / ".git").exists():
        git = ["git", "-C", str(directory)]
        subprocess.run([*git, "add", "orchestration", ".gitignore"], check=True)
        unchanged = subprocess.run([*git, "diff", "--cached", "--quiet"]).returncode == 0
        if not unchanged:
            subprocess.run([*git, "commit", "-q", "-m", f"ledger: {message}"], check=True)


def _csv(value: str | None) -> list[str]:
    return [item for item in (value or "").split(",") if item]


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--dir", type=Path, default=None)
    sub = p.add_subparsers(dest="command", required=True)
    sub.add_parser("init")
    show = sub.add_parser("show")
    show.add_argument("--json", action="store_true")
    sub.add_parser("eligible")
    ph = sub.add_parser("phase")
    ph.add_argument("code")
    for flag in ("status", "worktree", "branch", "spec", "slice", "task"):
        ph.add_argument(f"--{flag}")
    ph.add_argument("--slot", type=int)
    sl = sub.add_parser("slice")
    sl.add_argument("id")
    for flag in ("phase", "requires", "status", "spec", "plan", "prs"):
        sl.add_argument(f"--{flag}")
    for name in ("alloc-plan", "ready", "queue"):
        sub.add_parser(name).add_argument("id")
    sub.add_parser("next")
    mg = sub.add_parser("merged")
    mg.add_argument("id")
    mg.add_argument("--head", action="append", default=[], help="repo=sha")
    bo = sub.add_parser("bounce")
    bo.add_argument("id")
    bo.add_argument("--reason", required=True)
    de = sub.add_parser("decide")
    de.add_argument("phase")
    de.add_argument("text")
    de.add_argument("--affects", default="")
    de.add_argument("--source", required=True)
    for name in ("claim", "release"):
        c = sub.add_parser(name)
        c.add_argument("phase")
        c.add_argument("target")
        if name == "claim":
            c.add_argument("--reason", required=True)
    rq = sub.add_parser("request")
    rq.add_argument("phase")
    rq.add_argument("app")
    rq.add_argument("text")
    es = sub.add_parser("escalate")
    es.add_argument("phase")
    es.add_argument("kind", choices=ESCALATION_KINDS)
    es.add_argument("text")
    rs = sub.add_parser("resolve")
    rs.add_argument("id")
    rs.add_argument("text")
    return p


READ_ONLY = ("show", "eligible", "ready")


def run(args: argparse.Namespace) -> tuple[int, str]:
    directory = args.dir or default_dir()
    write = args.command not in READ_ONLY
    with locked(directory, write=write):
        if args.command == "init":
            if (directory / "orchestration" / "ledger.json").exists():
                raise LedgerError("ledger already initialised")
            save(directory, empty(), "init")
            return 0, str(directory)
        data = load(directory)
        c = args.command
        out, message = "", c
        if c == "show":
            return 0, json.dumps(data, indent=2, ensure_ascii=False) if args.json else render(data)
        if c == "eligible":
            free, codes = eligible(data)
            return 0, "\n".join([f"free={free}", *codes])
        if c == "ready":
            missing = unmet(data, args.id)
            return (1 if missing else 0), "\n".join(missing)
        if c == "phase":
            set_phase(data, args.code, status=args.status, slot=args.slot, worktree=args.worktree,
                      branch=args.branch, spec=args.spec, current_slice=args.slice,
                      current_task=args.task)
            message = f"phase {args.code}"
        elif c == "slice":
            if args.id not in data["slices"]:
                if not args.phase:
                    raise LedgerError(f"new slice {args.id} needs --phase")
                add_slice(data, args.id, phase=args.phase, requires=_csv(args.requires))
            elif args.requires:
                data["slices"][args.id]["requires"] = _csv(args.requires)
            set_slice(data, args.id, status=args.status, spec=args.spec, plan=args.plan, prs=args.prs)
            message = f"slice {args.id}"
        elif c == "alloc-plan":
            out = str(alloc_plan(data, args.id))
            message = f"plan {out} for {args.id}"
        elif c == "queue":
            enqueue(data, args.id)
            message = f"queue {args.id}"
        elif c == "next":
            out = take_next(data) or ""
            if not out:
                return 0, ""
            message = f"in flight {out}"
        elif c == "merged":
            heads = dict(item.split("=", 1) for item in args.head)
            mark_merged(data, args.id, heads)
            message = f"merged {args.id}"
        elif c == "bounce":
            bounce(data, args.id, args.reason)
            message = f"bounce {args.id}"
        elif c == "decide":
            out = decide(data, args.phase, args.text, _csv(args.affects), args.source)
            message = f"decision {out}"
        elif c == "claim":
            claim(data, args.phase, args.target, args.reason)
            message = f"claim {args.target} for {args.phase}"
        elif c == "release":
            release(data, args.phase, args.target)
            message = f"release {args.target}"
        elif c == "request":
            out = request(data, args.phase, args.app, args.text)
            message = f"request {out}"
        elif c == "escalate":
            out = escalate(data, args.phase, args.kind, args.text)
            message = f"escalation {out}"
        elif c == "resolve":
            resolve(data, args.id, args.text)
            message = f"resolve {args.id}"
        save(directory, data, message)
        return 0, out


def main(argv: list[str] | None = None) -> int:
    try:
        code, out = run(parser().parse_args(argv))
    except LedgerError as error:
        print(f"ledger: {error}", file=sys.stderr)
        return 1
    if out:
        print(out)
    return code


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m unittest discover -s scripts/orchestration/tests -v`
Expected: all PASS (the concurrent test proves the lock: ten distinct numbers 15–24).

- [ ] **Step 5: Commit**

```bash
git add scripts/orchestration/ledger.py scripts/orchestration/tests/test_ledger.py
git commit -m "feat(orchestration): the ledger, one locked JSON file committed per change

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Launching phases, the two prompts, CI and docs

**Files:**
- Create: `scripts/orchestration/bootstrap-ledger.sh`
- Create: `scripts/orchestration/launch-phase.sh`
- Create: `scripts/orchestration/tests/launch_phase_test.sh`
- Create: `scripts/orchestration/CONDUCTOR.md`
- Create: `scripts/orchestration/PHASE_PROMPT.md`
- Modify: `.github/workflows/ci.yml` (`infra-scripts` job)
- Modify: `CLAUDE.md` (a "Parallel phases" section)
- Modify: `justfile` (`new-module` reminders)
- Modify: `docs/superpowers/specs/2026-10-02-parallel-orchestration-design.md` (§6.1 item 4: prompt paths)

**Interfaces:**
- Consumes: `stream-env.sh` (Task 1), `ledger.py` (Task 4).
- Produces: `bash scripts/orchestration/bootstrap-ledger.sh` (idempotent: creates the `_ledger` worktree on an orphan `orchestration` branch and runs `ledger.py init`); `bash scripts/orchestration/launch-phase.sh <phase> <branch-suffix> <slot>` (creates `<wt-root>/<phase>` with meta, backend, dashboard and marketing worktrees on `feat/<branch-suffix>`, copies `backend/.env`, writes `.env.stream`, prints the session command). `ETQAN_WT_ROOT` overrides `<main checkout's parent>/etqan_tutor-wt`.

- [ ] **Step 1: Write the failing test**

`scripts/orchestration/tests/launch_phase_test.sh`:

```bash
#!/usr/bin/env bash
# launch-phase.sh and bootstrap-ledger.sh against throwaway repos (spec 2026-10-02 §3, §6.1).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
scripts="$here/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git() { command git -c protocol.file.allow=always -c init.defaultBranch=main "$@"; }

# Remotes: three submodules on main, a meta repo on master.
for sub in backend dashboard marketing; do
  git init -q --bare "$tmp/remotes/$sub.git"
  git clone -q "$tmp/remotes/$sub.git" "$tmp/seed-$sub"
  echo "$sub" >"$tmp/seed-$sub/README"
  echo ".env" >"$tmp/seed-$sub/.gitignore"  # as backend/.gitignore does
  git -C "$tmp/seed-$sub" add README .gitignore && git -C "$tmp/seed-$sub" commit -qm init && git -C "$tmp/seed-$sub" push -q origin main
done
git init -q --bare "$tmp/remotes/meta.git"
git clone -q "$tmp/remotes/meta.git" "$tmp/seed-meta"
git -C "$tmp/seed-meta" switch -q -c master
for sub in backend dashboard marketing; do git -C "$tmp/seed-meta" submodule add -q "$tmp/remotes/$sub.git" "$sub"; done
mkdir -p "$tmp/seed-meta/scripts" && cp -r "$scripts" "$tmp/seed-meta/scripts/orchestration"
printf '.env.*\n__pycache__/\n' >"$tmp/seed-meta/.gitignore"  # as the meta .gitignore does
git -C "$tmp/seed-meta" add . && git -C "$tmp/seed-meta" commit -qm init && git -C "$tmp/seed-meta" push -q origin master

# The main checkout, as a developer has it.
git clone -q --recurse-submodules -b master "$tmp/remotes/meta.git" "$tmp/etqan_tutor"
echo "SECRET=1" >"$tmp/etqan_tutor/backend/.env"
main="$tmp/etqan_tutor"
export ETQAN_WT_ROOT="$tmp/wt"

# bootstrap-ledger is idempotent.
(cd "$main" && bash scripts/orchestration/bootstrap-ledger.sh >/dev/null)
(cd "$main" && bash scripts/orchestration/bootstrap-ledger.sh >/dev/null)
[ -f "$tmp/wt/_ledger/orchestration/ledger.json" ] || fail "no ledger"
[ "$(git -C "$tmp/wt/_ledger" branch --show-current)" = orchestration ] || fail "ledger not on orchestration"
[ "$(git -C "$tmp/wt/_ledger" log --format=%s | wc -l)" -eq 1 ] || fail "second bootstrap wrote again"

# launch-phase creates every worktree on the branch.
out="$(cd "$main" && bash scripts/orchestration/launch-phase.sh b3 b3a-pricing 2)"
dir="$tmp/wt/b3"
for repo in "" /backend /dashboard /marketing; do
  [ "$(git -C "$dir$repo" branch --show-current)" = feat/b3a-pricing ] || fail "$dir$repo not on feat/b3a-pricing"
done
[ -z "$(git -C "$dir" status --porcelain)" ] || fail "meta worktree dirty: $(git -C "$dir" status --porcelain)"
grep -qx "SECRET=1" "$dir/backend/.env" || fail "backend/.env not copied"
grep -qx "ETQAN_HTTP_PORT=8280" "$dir/.env.stream" || fail "no slot-2 .env.stream"
grep -q "PHASE_PROMPT.md" <<<"$out" || fail "no session command printed: $out"
grep -q "B3" <<<"$out" || fail "phase code not in the command: $out"

# A second launch of the same phase is refused.
if (cd "$main" && bash scripts/orchestration/launch-phase.sh b3 b3b-other 3 2>/dev/null); then fail "relaunch accepted"; fi
echo "launch_phase_test: ok"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash scripts/orchestration/tests/launch_phase_test.sh`
Expected: FAIL — `bootstrap-ledger.sh: No such file or directory`.

- [ ] **Step 3: Write the two scripts**

`scripts/orchestration/bootstrap-ledger.sh`:

```bash
#!/usr/bin/env bash
# Create the shared ledger worktree on an orphan `orchestration` branch and
# initialise the ledger (spec 2026-10-02 §4.1). Safe to run again.
set -euo pipefail
main="$(cd "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" && pwd)"
root="${ETQAN_WT_ROOT:-$(dirname "$main")/etqan_tutor-wt}"
ledger="$root/_ledger"
mkdir -p "$root"
if [ ! -d "$ledger" ]; then
  if git -C "$main" show-ref -q --verify refs/heads/orchestration; then
    git -C "$main" worktree add -q "$ledger" orchestration
  elif git -C "$main" ls-remote -q --exit-code --heads origin orchestration >/dev/null 2>&1; then
    git -C "$main" fetch -q origin orchestration:orchestration
    git -C "$main" worktree add -q "$ledger" orchestration
  else
    git -C "$main" worktree add -q --orphan -b orchestration "$ledger"
  fi
fi
if [ ! -f "$ledger/orchestration/ledger.json" ]; then
  python3 "$main/scripts/orchestration/ledger.py" --dir "$ledger" init
fi
echo "ledger: $ledger"
```

`scripts/orchestration/launch-phase.sh`:

```bash
#!/usr/bin/env bash
# Create one phase's worktrees and stack settings (spec 2026-10-02 §3.2-3.3),
# then print the command that starts its orchestrator session.
#   launch-phase.sh <phase e.g. b3> <branch suffix e.g. b3a-pricing> <slot 1-4>
set -euo pipefail
[ $# -eq 3 ] || { echo "usage: launch-phase.sh <phase> <branch-suffix> <slot 1-4>" >&2; exit 2; }
phase="$1"; suffix="$2"; slot="$3"
main="$(cd "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" && pwd)"
root="${ETQAN_WT_ROOT:-$(dirname "$main")/etqan_tutor-wt}"
dir="$root/$phase"
branch="feat/$suffix"
code="$(tr '[:lower:]' '[:upper:]' <<<"$phase")"
[ ! -e "$dir" ] || { echo "already exists: $dir" >&2; exit 1; }
mkdir -p "$root"
git -C "$main" fetch -q origin
git -C "$main" worktree add -q -b "$branch" "$dir" origin/master
for sub in backend dashboard marketing; do
  git -C "$main/$sub" fetch -q origin
  git -C "$main/$sub" worktree add -q -b "$branch" "$dir/$sub" origin/main
done
if [ -f "$main/backend/.env" ]; then cp "$main/backend/.env" "$dir/backend/.env"; fi
bash "$main/scripts/orchestration/stream-env.sh" "$phase" "$slot" "$dir" >/dev/null
cat <<EOF
Phase $code is ready in $dir (slot $slot, http://demo.etqan.localhost:$((8080 + slot * 100))/).
Start its orchestrator in a new terminal:

  cd $dir && claude "\$(sed -e 's/{{PHASE}}/$code/g' -e 's/{{SLOT}}/$slot/g' scripts/orchestration/PHASE_PROMPT.md)"
EOF
```

`chmod +x` both, and `stream-env.sh`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash scripts/orchestration/tests/launch_phase_test.sh`
Expected: `launch_phase_test: ok`

- [ ] **Step 5: Write the conductor's and the phase orchestrator's instructions**

`scripts/orchestration/PHASE_PROMPT.md`:

```markdown
You are the orchestrator for phase {{PHASE}} of etqan_tutor, running in stream slot {{SLOT}}.
Your worktree is the current directory; its `.env.stream` gives your dev stack its own ports.

Read first, in this order: `CLAUDE.md`; `docs/superpowers/specs/2026-10-02-parallel-orchestration-design.md`
(the rules you work under — it overrides any older rule that every merge needs the owner's approval);
the {{PHASE}} row of `docs/superpowers/specs/2026-09-24-parity-roadmap-design.md`; the audits
`docs/PHASE_1_SYSTEM_AUDIT.md` and `docs/TUTORHAMSTER_FEATURE_AUDIT_2026-09-24.md`; the ledger
(`python3 scripts/orchestration/ledger.py show`) — above all its shared decisions — and the specs of the
phases {{PHASE}} depends on.

Ledger: `python3 scripts/orchestration/ledger.py <command>` (run `--help`). Keep your phase row current
(`phase {{PHASE}} --status … --slice … --task …`) and your notes in the ledger worktree at
`orchestration/phases/{{PHASE}}.md` (then `git -C <ledger worktree> commit` it).

Loop, one slice at a time:
1. Brainstorm with the brainstorming skill, but answer every question yourself: from the audits, then
   earlier specs, then the ledger's shared decisions. Record each answer and its source (`audit §x`,
   `spec <file>`, or `[assumed]`) in the spec's decisions table. Never ask the owner. The first slice
   also writes the phase spec that splits {{PHASE}} into slices `{{PHASE}}a`, `{{PHASE}}b`, …; record
   its path with `phase {{PHASE}} --spec <path>` and each slice with `slice <id> --phase {{PHASE}}
   --requires <other phases' slices>`.
2. Dispatch a fresh spec-reviewer subagent against the audits and shared decisions; fix what it finds;
   then treat the spec as approved. A decision that affects another phase goes into the ledger with
   `decide`.
3. `alloc-plan <slice>` for the plan number; write the plan with writing-plans, file name
   `docs/superpowers/plans/<date>-plan-<n>-<topic>.md`, with a `Requires:` line naming the slices it
   needs. Build only tasks whose required slices are merged (`ready <slice>`); otherwise set
   `--status waiting-deps` on your phase and work on a slice that is ready.
4. Build with subagent-driven development (TDD, per-task reviews), then a final whole-slice review by a
   fresh reviewer. Only minor findings may be deferred (log them in your phase notes).
5. `just test`, `just lint` and the e2e suite against your stack must pass; then `queue <slice>`.
6. At every task boundary run `ledger.py show` (and read any message from the conductor). When your slice
   is in flight: rebase every touched repo onto `origin/main` (`origin/master` for meta), resolve
   conflicts by the spec's §6.2, regenerate generated files, rerun tests and e2e, push, open the PRs
   (backend, dashboard, marketing → `main`; meta → `master` with the submodule pointers at your branches),
   and record them with `slice <id> --prs "<urls>"`. The conductor merges.

Rules you never break:
- Every new feature is registered in `etqan/platform/features.py`, off by default.
- Add lines to shared lists only under your own `── phase {{PHASE}} ──` markers (settings
  `TENANT_APPS`, `config/api_router.py`, the feature registry, the access `RESOURCES`, `seed_academy`
  and `etqan/tenants/seeds/`, `pyproject.toml`, the dashboard's `NAV_ITEMS`). New translation areas are
  new files `dashboard/src/locales/{en,ar}/<area>.json`.
- Change models only in apps you own (see the ledger's `ownership`) or new apps; otherwise `request`,
  or `claim` a trivial additive field for one commit and `release` it.
- On a migration clash after a rebase, delete your unmerged migration and regenerate it; never `--merge`.
- Service signature changes are additive only.
- Never edit `STATE.md`, CI workflows, Caddyfiles or the meta submodule pointers on `master`; never
  touch production or mutate TutorHamster's demo. New e2e specs are `e2e/{{PHASE}}-*.spec.ts`
  (lower-case phase).
- Escalate only the spec's §8 cases (`escalate {{PHASE}} <kind> "<question>"`) and keep working on
  something else meanwhile.
```

`scripts/orchestration/CONDUCTOR.md`:

```markdown
You are the conductor of the parallel phases of etqan_tutor, running in the main checkout.
Your rules are `docs/superpowers/specs/2026-10-02-parallel-orchestration-design.md`; read it and
`CLAUDE.md` first. You write no product code. Ledger: `python3 scripts/orchestration/ledger.py <command>`.

Once: `bash scripts/orchestration/bootstrap-ledger.sh`.

Loop (use /loop or ScheduleWakeup, about every 20 minutes, sooner while a slice is in flight):
1. Start phases: `ledger.py eligible`. For each code listed, pick a free slot (1–4) and a branch suffix
   (`<phase>a-<topic>`), run `bash scripts/orchestration/launch-phase.sh <phase> <suffix> <slot>`, record
   it with `ledger.py phase <CODE> --status spec --slot <n> --worktree <dir> --branch feat/<suffix>`, and
   tell the owner the printed command to start the session in a new terminal.
2. Merge queue: if nothing is in flight, `ledger.py next`. Tell the phase (SendMessage to its session if
   it is listed by ListAgents; the phase also polls the ledger). Wait for its PRs in the ledger, then
   `gh pr checks --watch` on the meta PR. Green: merge backend → dashboard → marketing with
   `gh pr merge --merge`, bump the submodule pointers on `master` to the merged commits, merge the meta
   PR, `ledger.py merged <slice> --head backend=<sha> --head dashboard=<sha> …`, append a paragraph to
   the ledger worktree's `orchestration/MERGES.md` and commit it, `git push origin orchestration`.
   Red: `ledger.py bounce <slice> --reason "<failing job>"`.
3. If `master` CI goes red after a merge, revert that merge in every repo, bump the pointers, push, and
   bounce the slice. Never fix forward on a red trunk.
4. Settle shared-decision conflicts from the audits (`ledger.py decide`), or escalate
   (`shared-decision`). Answer `request`s to unowned apps yourself on `master` through the queue.
5. Pause a phase that made no progress for two queue rounds (`phase <CODE> --status paused`) and
   escalate it (`stalled`). Keep `STATE.md` current after each merge.
6. When a phase's last slice merges, `ledger.py phase <CODE> --status merged`, remove its worktrees
   (`git worktree remove`, in each submodule and meta) and its stack (`just stop` in it, then
   `docker compose -f docker-compose.local.yml down -v`), and start the next eligible phase.
Report to the owner only open escalations and a short note per merge.
```

- [ ] **Step 6: Wire CI, docs and the spec**

`.github/workflows/ci.yml`, `infra-scripts` job — append to the shellcheck file list `scripts/orchestration/*.sh scripts/orchestration/tests/*.sh`, and add a step after the existing tests:

```yaml
      - name: orchestration scripts
        run: |
          bash scripts/orchestration/tests/stream_env_test.sh
          bash scripts/orchestration/tests/launch_phase_test.sh
          python3 -m unittest discover -s scripts/orchestration/tests -v
```

`CLAUDE.md`, after "## Rules":

```markdown
## Parallel phases
Phases B2–B11 are built by parallel sessions under
`docs/superpowers/specs/2026-10-02-parallel-orchestration-design.md`: one conductor
(`scripts/orchestration/CONDUCTOR.md`) and one orchestrator per phase
(`scripts/orchestration/PHASE_PROMPT.md`), coordinated by `scripts/orchestration/ledger.py`.
Shared lists carry `── phase Bn ──` markers: add lines only under your phase's marker.
Translations are one file per area in `dashboard/src/locales/<lng>/`.
```

`justfile`, `new-module` reminders — replace lines 1 and 2 of the echoed list:

```just
    @echo "  1. Add 'etqan.{{name}}' to TENANT_APPS under your phase's '── phase Bn ──' marker"
    @echo "  2. Add import-linter contracts in pyproject.toml under your phase's marker, and the app to the platform contract's forbidden list"
```

Spec §6.1 item 4: replace `a phase-session prompt file (\`orchestration/PHASE_PROMPT.md\`) that every orchestrator starts from` with `the prompt files every session starts from (\`scripts/orchestration/PHASE_PROMPT.md\`, \`scripts/orchestration/CONDUCTOR.md\`)`.

- [ ] **Step 7: Run every orchestration test and shellcheck; commit**

Run:

```bash
bash scripts/orchestration/tests/stream_env_test.sh
bash scripts/orchestration/tests/launch_phase_test.sh
python3 -m unittest discover -s scripts/orchestration/tests -v
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:v0.11.0 scripts/orchestration/*.sh scripts/orchestration/tests/*.sh
```

Expected: three `ok`/`OK` lines and no shellcheck output.

```bash
git add scripts/orchestration .github/workflows/ci.yml CLAUDE.md justfile docs/superpowers/specs/2026-10-02-parallel-orchestration-design.md
git commit -m "feat(orchestration): launch phases, the conductor and phase prompts, CI

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Merge Plan 14 and open wave 1

**Files:**
- Modify: `STATE.md`

- [ ] **Step 1: Final review, PRs, merge**

Run a fresh whole-branch review (requesting-code-review) over meta, backend, dashboard and marketing `feat/orchestration`. Fix critical and important findings. Push all four branches; open PRs (backend, dashboard, marketing → `main`; meta → `master` with pointers at the PR branches); wait for meta CI green (`gh pr checks --watch`); merge backend, dashboard, marketing, bump the pointers on the meta branch to the merged commits, merge meta.

- [ ] **Step 2: Bootstrap the ledger and record wave 0**

```bash
git switch master && git pull --recurse-submodules
bash scripts/orchestration/bootstrap-ledger.sh
L="python3 scripts/orchestration/ledger.py"
$L decide B2 "R7 dropped: phases are designed from the audits; unobserved behaviour is marked [assumed]" --affects B2,B4,B5,B6,B11 --source "spec 2026-10-02 PO-2"
git -C ../etqan_tutor-wt/_ledger push -u origin orchestration
```

- [ ] **Step 3: Update `STATE.md` and launch wave 1**

Rewrite `STATE.md` "Where we are" to: Plan 13 and Plan 14 merged; the phases now run in parallel under the 2026-10-02 spec; `ledger.py show` is the live position; follow-ups unchanged. Commit and push on `master`. Then, as conductor, run `ledger.py eligible` (expect `free=4`, `B2 B3 B8 B9`) and launch each (`launch-phase.sh b2 b2a-<topic> 1`, `b3 … 2`, `b8 … 3`, `b9 … 4`), recording each in the ledger and handing the owner the four printed commands.
