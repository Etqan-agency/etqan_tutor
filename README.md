# etqan_tutor

Multi-academy tutoring operations SaaS by Etqan Agency. Each academy gets its own
workspace (PostgreSQL schema + subdomain); academy admins manage students, teachers,
subscriptions, schedules, sessions, billing and payroll.

Forked from Kaleem (history preserved); Kaleem's docs live in `docs/kaleem-archive/`.

## Quick start

    git clone --recursive https://github.com/Etqan-agency/etqan_tutor.git
    cd etqan_tutor
    just setup   # build, migrate all schemas, seed demo academies
    just dev

- Academy site: http://demo.etqan.localhost/
- Academy dashboard: http://demo.etqan.localhost/app/  (admin@demo.test / e2e-EtqanTest-2026)
- Second academy: http://other.etqan.localhost/ and /app/  (admin@other.test)
- Etqan staff console: http://etqan.localhost/admin/  (`docker compose -f docker-compose.local.yml run --rm django python manage.py createsuperuser`)
- Mail: http://mail.etqan.localhost

If ports are taken, set ETQAN_*_PORT in .env. Caddy (caddy/Caddyfile.local) is the
edge on port 80: on every academy host `/api`, `/accounts`, `/health`, `/media` go to
Django, `/app` to the dashboard, everything else to the marketing site. To try a custom
domain, map it to 127.0.0.1 in /etc/hosts and register it for an academy.

Create an academy from the CLI:

    docker compose -f docker-compose.local.yml run --rm django \
      python manage.py create_academy --name "Noor" --subdomain noor --admin-email admin@noor.test

## Docs

- Product spec: `docs/superpowers/specs/2026-09-23-etqan-tutor-v1-design.md`
- Plans: `docs/superpowers/plans/`
- Source analysis: `docs/PHASE_1_SYSTEM_AUDIT.md`, `docs/PHASE_2_SYSTEM_DESIGN.md`
