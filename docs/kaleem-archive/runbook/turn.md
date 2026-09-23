# Runbook — TURN relay (coturn)

**What this is.** A TURN server relays WebRTC media when the two peers cannot
reach each other directly. Roughly **one connection in six** cannot go
peer-to-peer — symmetric NAT, carrier-grade NAT, corporate egress filtering —
and without a relay those calls do not fail gracefully, they simply never
connect. coturn is not optional infrastructure for kaleem; it is the difference
between "video works" and "video works for most people".

Unlike the signaling service, coturn **does** carry media bytes. It is also the
one kaleem component deliberately exposed on raw UDP rather than behind Traefik.

Shipped in Phase C3c. Spec:
`docs/superpowers/specs/2026-09-06-phase-c3c-turn-design.md`.

## Environment variables

| Variable | Read by | Purpose |
| --- | --- | --- |
| `DJANGO_TURN_SECRET` | Django **and** coturn | The HMAC key behind every ephemeral credential. One entry in `.env.production` feeds both. If they disagree, every allocation gets a `401` and every relayed call fails while both services look healthy. |
| `DJANGO_TURN_URLS` | Django only | Comma-separated ICE URLs handed to the browser, e.g. `stun:turn-staging.kaleem.academy:3478,turn:turn-staging.kaleem.academy:3478?transport=udp,turn:turn-staging.kaleem.academy:3478?transport=tcp`. |
| `TURN_REALM` | coturn only | The TURN realm, e.g. `kaleem.academy`. |

`SignalingProvider` **fails closed** without `DJANGO_TURN_SECRET` and
`DJANGO_TURN_URLS`: it raises `ImproperlyConfigured` and no one can join a
lesson. That is deliberate — a silently relay-less deployment would work for
five people in six and be blamed on their wifi.

## ⚠ Why the secret is a command-line argument, not a config line

`infra/coturn/turnserver.conf` does **not** contain `static-auth-secret` or
`realm`. They are passed in `docker-compose.production.yml` as
`--static-auth-secret=${DJANGO_TURN_SECRET}` and `--realm=${TURN_REALM}`.

**coturn performs no variable expansion in its config file.** Writing
`static-auth-secret=${DJANGO_TURN_SECRET}` there does not read the environment
— it sets the shared secret to the *literal nine-character string*
`${DJANGO_TURN_SECRET}`. That is not a broken deploy, it is an **open relay**:
the secret becomes a publicly guessable constant, and anyone who can read the
repository can mint valid credentials and use kaleem's relay as a proxy and a
DDoS amplifier. Docker Compose *does* expand `${...}`, which is why the two
settings live on the command line.

Do not "tidy" them back into the conf file.

The accepted cost: the secret is visible in `docker inspect` and in the host
process list. That is inside an existing trust boundary — the same value
already sits in `.env.production` on the same box, and docker socket access
there is already root-equivalent.

## First-time setup

1. **Generate the secret** and put the *same* value in `.env.production` on the
   VPS:
   ```bash
   openssl rand -base64 48
   ```
   Then set `DJANGO_TURN_SECRET`, `TURN_REALM` and `DJANGO_TURN_URLS`. Diff
   against `infra/.env.production.example` before deploying — that file is a
   template on disk, not a deployment mechanism.

2. **Create the DNS record — it MUST be DNS-only (grey cloud).**
   `turn-staging.kaleem.academy` → the VPS IP, proxy **disabled**.
   Cloudflare cannot proxy UDP. A proxied (orange-cloud) record does not
   produce a helpful error; allocations simply never succeed, and the browser
   reports a generic ICE failure that looks like a client bug.

   ⚠ A DNS-only record **publishes the origin IP** that the proxied records
   currently hide. That is a real, accepted consequence of self-hosting TURN.

3. **Open the firewall at the provider**, not just in the container:
   | Port | Protocol | Purpose |
   | --- | --- | --- |
   | 3478 | UDP | the normal path |
   | 3478 | TCP | for egress filters that drop UDP |
   | 49152–49999 | UDP | relay allocations |

4. **Bring it up.** coturn is a shared service, not part of a colour:
   ```bash
   docker compose -f docker-compose.production.yml up -d coturn
   ```
   It holds no deploy-versioned code, so `scripts/ship.sh` deliberately leaves
   it alone — restarting it on every ship would drop live relay allocations for
   nothing.

## Verifying it actually relays

A green container proves nothing. Prove an allocation:

```bash
# Mint a credential the way Django does:
#   username = "<unix-expiry>:<user-id>"
#   password = base64(HMAC-SHA1(DJANGO_TURN_SECRET, username))
turnutils_uclient -T -u '<expiry>:<user-id>' -w '<password>' \
  -p 3478 turn-staging.kaleem.academy
```

To prove the whole media path, open a page with two `RTCPeerConnection`s and
`iceTransportPolicy: "relay"`, fed the `ice_servers` from a real join response.
Relay-only forces every candidate through coturn, so a successful connection
proves the path end to end.

**Mutation-check it.** Change one character of the secret and re-run. If it
still succeeds, you are not testing what you think you are.

## Symptoms

| Symptom | Cause |
| --- | --- |
| Every allocation returns `401` | `DJANGO_TURN_SECRET` differs between Django and coturn, or it was left in `turnserver.conf` and is being read literally. |
| Allocations succeed, no media arrives | The relay range is open in coturn and **closed at the provider firewall**. Check 49152–49999/UDP. |
| Allocations never succeed, no error | The DNS record is Cloudflare-proxied. It must be grey-cloud. |
| Joins 500 with `ImproperlyConfigured` | `DJANGO_TURN_SECRET` or `DJANGO_TURN_URLS` missing from the API container. Failing closed is intended. |
| Calls connect for most people, fail for some | Expected today: there is no `turns:` listener, so a TLS-443-only egress filter still blocks the relay. Tracked in `ISSUES.md` under *Blocks launch*. |

## Known gaps

- **No `turns:` on 5349 or 443.** Traefik owns 443 on this box. Users behind a
  TLS-443-only egress filter still cannot call. Closing it needs a second IP or
  a dedicated TURN host.
- **No capacity planning or bandwidth metering.** One VPS, staging only.
- **Production TURN does not exist**, because production does not exist.

## Related

- `docs/runbook/signaling.md` — the WebSocket signaling service
- `docs/runbook/deploy.md` — blue-green deploy flow
- ADR-0034 — custom WebRTC in v1
- ADR-0035 — signaling as its own deployable
