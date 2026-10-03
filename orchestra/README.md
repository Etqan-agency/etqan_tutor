# Orchestra

The local dashboard for the parallel phases
(`docs/superpowers/specs/2026-10-03-orchestra-dashboard-design.md`).

- `just orchestra` — build the web app if needed and serve `http://127.0.0.1:7700`.
- `just orchestra-dev` — work on the UI (Vite on :5174, the API proxied).
- `just orchestra-test` — server and web tests, types, lint, build.

It listens on 127.0.0.1 only, refuses other Hosts and Origins, and every change needs the
token the server puts in the page. It keeps no state: the ledger
(`scripts/orchestration/ledger.py`), `claude agents` and git are the truth, so restarting it
loses nothing. Sessions are Claude Code background sessions started by
`scripts/orchestration/start-session.sh`; take one over in a terminal with `claude attach <id>`.
