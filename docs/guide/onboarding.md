# Onboarding

Your first day on etqan_tutor: get the stack running, find your way around, and ship a
change the way the team does.

## 1. Access you need

- Read access to the private repos in the `Etqan-agency` org (all named `etqan_tutor*`):
  the meta repo, `backend`, `dashboard`, `infra` and `tokens`.
- A GitHub token the build can use for the private `@etqan/tokens` package. Either
  `export GH_TOKEN=<PAT with read access to Etqan-agency/etqan_tutor_tokens>` or run
  `gh auth login`. The `just` recipes look for one and stop with instructions if neither works.
- Docker with Compose v2, [`just`](https://github.com/casey/just), and `gh`. Node 22 with pnpm
  10 and Python 3.13 are only needed to run tools on the host. Everything else runs in
  containers.

## 2. Run it

```sh
git clone --recursive https://github.com/Etqan-agency/etqan_tutor.git
cd etqan_tutor
just setup   # submodules, images, migrate_schemas, seed demo academies
just dev     # whole stack behind Caddy; Ctrl-C stops it (just dev-backend = detached)
```

| URL | What |
|---|---|
| http://demo.etqan.localhost/ | Demo academy's public site (Astro) |
| http://demo.etqan.localhost/app/ | Demo academy dashboard |
| http://demo.etqan.localhost/api/v1/docs/ | Swagger UI for the API |
| http://other.etqan.localhost/app/ | A second academy, for checking isolation |
| http://etqan.localhost/admin/ | Etqan staff admin (create a superuser first, below) |
| http://mail.etqan.localhost | Mailpit: every email the stack sends |
| http://flower.etqan.localhost | Celery queues |

`*.localhost` resolves to 127.0.0.1 in modern browsers and with systemd-resolved. If ports
80 and the others are taken, set `ETQAN_*_PORT` in `.env`.

**Seeded accounts.** `just seed` runs `manage.py seed_dev` (DEBUG only, safe to re-run).

| Who | Login |
|---|---|
| Demo admin | `admin@demo.test` / `e2e-EtqanTest-2026` |
| Other academy admin | `admin@other.test` / same password |
| Teachers, parents, students, staff | `bilal@`, `maryam@` (teachers), `omar@`, `huda@` (parents), `yusuf@` (student), `sara@demo.test` (staff supervisor). They are created without a password. Use *forgot password* on the login page and open the reset email in Mailpit, or set one in `just shell` |

Etqan staff superuser:

```sh
docker compose -f docker-compose.local.yml run --rm django python manage.py createsuperuser
```

Another academy:

```sh
docker compose -f docker-compose.local.yml run --rm django \
  python manage.py create_academy --name "Noor" --subdomain noor --admin-email admin@noor.test
```

Handy recipes: `just logs django`, `just shell` (Django shell), `just migrate`,
`just rebuild` (after dependency changes). If a dependency changed and the dashboard
misbehaves, drop the `node_modules` volumes too.

## 3. Learn the system

Read these in order:

1. [Architecture](architecture.md): repos, request path, tenancy, module boundaries,
   permissions, the dashboard.
2. [`CLAUDE.md`](../../CLAUDE.md): the binding rules, short. The same file is used by
   people and by AI agents.
3. [Feature reference](../features/README.md): one page per feature, describing how it
   works now.
4. [Adding a feature](adding-a-feature.md) and [Testing](testing.md) before your first PR.

Then click through the demo academy as each role (admin, teacher, parent, student) with the
matching feature page open beside you.

## 4. How work is done

**Spec → plan → code.** Anything more than a small fix starts with a design spec in
`docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` and an implementation plan in
`docs/superpowers/plans/`. Check the product spec's non-goals before adding scope: this is a
CRUD-first product, so keep it simple.

**TDD.** Write the failing test first. Coverage floors are enforced in CI: backend 80%;
dashboard and marketing 80% lines/statements and 70% branches/functions.

**Keep the docs current.** When you change how a feature behaves, update its page in
`docs/features/` in the same PR. Specs are not edited after the fact.

### Git workflow

Trunks: `master` in the meta repo, `main` in each submodule.

1. In each repo you touch, branch `feat/<topic>` (or `fix/<topic>`) off the trunk.
2. Commit with [Conventional Commits](https://www.conventionalcommits.org/)
   (`feat(billing): …`, `fix: …`, `docs: …`).
3. Open a PR in the submodule (`backend`, `dashboard`…) and get CI green.
4. After it merges, in the meta repo: branch, check out the merged commit in the submodule,
   commit the new pointer with its path given explicitly (`git commit backend -m "chore: bump backend"`,
   never `git commit -a`, which also picks up stray pointer changes), and open the meta PR.
   With `gh` in the meta repo pass `--repo Etqan-agency/etqan_tutor`, because the repo is a fork
   and `gh` otherwise targets the parent.
5. Never `--no-verify` or force-push shared branches.

The meta repo's CI runs everything: backend, dashboard, marketing, Caddy, end-to-end, infra
scripts and a secret scan. Every green `master` deploys to staging; see
[Deploy](runbooks/deploy.md).

### The parallel-phase tooling

`scripts/orchestration/`, `orchestra/`, `just orchestra` and the `── phase Bn ──` markers in
shared lists were how phases B2–B11 were built by parallel AI sessions. All phases are
merged. You don't need any of it for normal work, but keep the markers when you edit those
lists: add new lines at the end of the relevant list.

## 5. Where to ask and look

- Current state and open follow-ups: [`STATE.md`](../../STATE.md).
- Why something is the way it is: the feature page's *Design history*, then the spec.
- Inherited decisions: [`docs/kaleem-archive/adr/`](../kaleem-archive/adr/). These are from
  Kaleem, the project this was forked from, and still apply unless replaced.
