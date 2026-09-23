# Docker dev environment — full-parity, one command

- **Date:** 2026-06-13
- **Status:** draft
- **Type:** D1 spec (developer-experience / infra)
- **Related:** ADR-0019 (same-site auth), ADR-0015 (Postgres volume layout), ADR-0014 (git-flow)

## Problem

The local dev story is half-containerized and leaks two real bugs:

1. **Root-owned files.** Backend containers run as `root` and write into bind mounts, so
   host files (`backend/.coverage`, `.ruff_cache`, etc.) end up owned by `root:root` —
   the classic Docker ownership error. The user hits permission failures editing or
   deleting them.
2. **Auth model is never exercised locally.** ADR-0019 chose *same-site subdomains*
   (`app-`/`api-` sharing `Domain=.kaleem.academy` cookies). Dev runs the frontends on
   host ports (`localhost:5173` → `localhost:8000`), which is *cross-origin* — so
   cookie / CSRF / CORS bugs only surface on staging.

Additionally, dashboard and marketing run on the host (`pnpm dev`), so there is no single
"bring up everything" command and no machine-to-machine parity.

## Goal

One command (`just dev`) brings up the entire stack — backend, dashboard, marketing,
supporting services — in Docker, behind a Traefik reverse proxy that mirrors the ADR-0019
subdomain/cookie model, with **zero root-owned files** on the host. Identical on any Linux
machine.

## Non-goals

- No changes to the production images or `infra/docker-compose.production.yml`. ADR-0019's
  nginx-served frontend images stay exactly as they are.
- No macOS/Windows file-watching support (polling). Target is Linux; native inotify is
  used.
- No per-developer compose override file unless a concrete need appears.

## Decisions

### D-1 — Ownership: run dev containers as the host UID/GID

Each `dev` build stage creates a user from build-args `UID` / `GID`; Compose passes the
host's `UID`/`GID`. Everything the container writes into a bind mount is owned by the
developer. This is applied to **all** dev services (backend + both frontends), which also
fixes the existing root-owned-file problem. (Rejected: runtime-only `user:` — named
volumes/image dirs come back root-owned; chown-on-boot entrypoint — slow and masks the
cause.)

### D-2 — node_modules in a named volume, source bind-mounted

Source is bind-mounted for HMR; `node_modules` lives in a per-service **named volume** so
the container's Linux/arch-native binaries (esbuild, swc) never collide with the host's,
and the host `node_modules` (for IDE language servers) is left untouched. Native inotify
means no polling.

### D-3 — Traefik-fronted subdomains on `*.kaleem.localhost`

```
Traefik :80 ─┬─ app.kaleem.localhost    → dashboard (Vite dev)
             ├─ api.kaleem.localhost    → django
             ├─ kaleem.localhost        → marketing (Astro dev)
             ├─ mail.kaleem.localhost   → mailpit
             └─ flower.kaleem.localhost → flower
```

`*.localhost` resolves to `127.0.0.1` via systemd-resolved (Arch) — **no `/etc/hosts`
edits**. Cookies on `Domain=.kaleem.localhost` flow across `app`/`api` like prod. Reuses
the Traefik already vendored in `infra/`. (Fallback if a machine lacks `*.localhost`
resolution: one dnsmasq/`/etc/hosts` line — documented, not automated.)

### D-4 — Tests/lint run in-container, host path kept as escape hatch

`just test` / `just lint` gain `docker compose exec` variants for true CI parity. The
existing host-path targets remain for fast IDE-integrated runs; the host `.venv` /
`node_modules` stay for language servers.

## Components / changes

| File | Change |
| --- | --- |
| `docker-compose.local.yml` | Add `traefik`, `dashboard`, `marketing` services; add Traefik labels + `UID`/`GID` build-args to all dev services |
| `dashboard/Dockerfile` | New `dev` stage above the production stage: deps install (keeps the `tokens_token` BuildKit secret), non-root user from `UID`/`GID`, `pnpm dev` |
| `marketing/Dockerfile` | Same `dev` stage pattern |
| `dashboard/vite.config.ts` | `server.host: true`, `server.allowedHosts: ['app.kaleem.localhost']`, `server.hmr.clientPort: 80` (HMR ws through Traefik) |
| `marketing/astro.config.mjs` | `server.host: true` + `vite.server.hmr` + allowed hosts |
| `backend` dev settings | Add `*.kaleem.localhost` to `CORS_ALLOWED_ORIGINS` / `CSRF_TRUSTED_ORIGINS`; session-cookie `Domain=.kaleem.localhost` |
| `infra/traefik/traefik.dev.yml` | Dev entrypoint (:80) + Docker provider (or inline labels) |
| `.env` (meta root) | `UID`, `GID`, `VITE_API_URL=http://api.kaleem.localhost`; gitignored, documented in `.env.example` |
| `justfile` | `just dev` = `docker compose up` (foreground); `stop`, `rebuild`; in-container `test`/`lint` variants |

### Subtle bits that must be correct

- **HMR through the proxy.** Vite/Astro HMR is a websocket; with Traefik terminating on
  `:80` the client must connect back on port 80 → `server.hmr.clientPort: 80`. Without
  this, the page loads but never hot-reloads.
- **Vite host allow-list.** Vite rejects unknown `Host` headers; `app.kaleem.localhost`
  must be in `server.allowedHosts`.
- **Cookie domain.** `Domain=.kaleem.localhost` (leading dot) is what makes the cookie
  span `app`/`api`. Getting this wrong silently breaks login — the whole point of D-3 is
  to make that failure visible in dev.
- **Private tokens dep.** The `dev` stages reuse the existing `--mount=type=secret,id=tokens_token`
  install; the token is never baked into a layer.

## Risks

- **`*.localhost` multi-label resolution** isn't universal across all resolvers. Mitigated
  by D-3's documented dnsmasq fallback; verified on the target Arch/systemd-resolved box
  during implementation.
- **Cookie/CORS misconfig** is subtle (ADR-0019 calls this out). Mitigated by a manual
  login smoke test through `app.kaleem.localhost` as the acceptance check.
- **First `up` is slower** (builds two more images, populates node_modules volumes).
  One-time; subsequent ups are warm.

## Acceptance / Definition of Done

1. Fresh clone → `just setup && just dev` brings up all services; no manual host edits.
2. `app.kaleem.localhost`, `kaleem.localhost`, `api.kaleem.localhost/admin/` all load
   through Traefik.
3. Editing a dashboard/marketing source file hot-reloads in the browser.
4. A login flow through `app.kaleem.localhost` sets a `.kaleem.localhost` cookie and an
   authenticated `api.kaleem.localhost` XHR succeeds (same-site auth proven locally).
5. **No new root-owned files** appear in any bind mount after a full dev session +
   `just test`.
6. `just test` / `just lint` pass in-container.
7. Docs: `docs/developer-guide/` updated with the one-command workflow; `STATE.md` /
   journal updated.
