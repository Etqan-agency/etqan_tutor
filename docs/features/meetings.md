# Video meetings: session links, Zoom, Jitsi and the host link

Every session can carry a `meeting_url` that the teacher, student, parent and supervisor
use to join the lesson. A link can come from three places:

- someone typed it, on the slot, on the teacher's profile or on a hand-added session;
- the meetings job made a Zoom meeting, on the academy's own Zoom account or in Etqan's
  Zoom host pool;
- the meetings job made a free Jitsi room when Zoom is not available.

The teacher of a Zoom session can ask for a fresh **host (start) link**. That link is a
host credential, so it is never stored. Account setup, the resolver and metering are
covered in [integrations.md](integrations.md). This page covers how sessions get and use
links.

## Concepts

| Field / model | Purpose |
|---|---|
| `Session.meeting_url` | The join link everyone uses. Blank means "no link yet". |
| `Session.meeting_provider` | `"zoom"`, `"jitsi"`, or `""` for a link someone typed. |
| `Session.meeting_ref` | The Zoom meeting id. Used for the host link and the host pool. Never a start link. |
| `ScheduleSlot.meeting_url` | Optional per-slot link that generated sessions copy. |
| `TeacherProfile.default_meeting_url` (identity) | Fallback for generated, regular hand-added and trial sessions. |
| `integrations.HostBooking` (public schema) | Which Etqan pool host holds which time range, per academy and meeting id. |
| `integrations.services.video.Meeting` | `(url, provider, ref)` returned by `create_meeting` / `jitsi_meeting`. |

## How it works

**Links set when a session is created**

- Generation (`scheduling/services/generation.py:_new_session`) uses `slot.meeting_url`,
  or else the default link of the teacher who teaches that date (the substitute's, when
  there is one).
- Hand-added sessions (`services/manual.py`) and trial sessions (`services/trials.py`)
  take the `meeting_url` given in the request. Regular and trial sessions fall back to
  the teacher's default link.
- A typed link is never replaced by the job.

**Provisioning** (`scheduling/services/meetings.py:provision_meetings`)

1. The job runs only when `integrations.services.meetings_wanted()` is true. That means
   the `zoom_api` feature is on, or the academy has its own enabled video (Zoom) account.
2. It takes a per-academy, non-blocking Postgres advisory lock. If another run holds the
   lock, this run skips the academy. The lock is released in `finally`.
3. `_release_moved`: a pool-hosted Zoom session whose `HostBooking` no longer matches its
   start and length (it was postponed or edited) loses its link, so it gets a new
   meeting. The booking is released only when none of the meeting's sessions still fit
   it. The academy's own Zoom meetings have no booking and always "fit".
4. `_due`: sessions that are scheduled, not archived, have a blank `meeting_url`, start
   between now − 4 h and now + 24 h, and have not ended yet.
5. Sessions are grouped into **classes** by (teacher, `starts_at`, `minutes`). Each
   class gets one meeting, so a group lesson shares a link. The topic is
   "`<course name_en>` · `<teacher name>`".
6. `integrations.services.create_meeting(topic, starts_at, minutes)` makes the meeting:
   - nothing resolves for `video`: a Jitsi room `JITSI_BASE_URL/Etqan<uuid>`;
   - the academy's own account: Zoom on that account, hosted by its `host_user` (or
     `"me"`);
   - Etqan's default: it reserves the first pool host (`host_users`) with no overlapping
     booking (one meeting per host at a time, under a global advisory lock in a durable
     transaction), creates the Zoom meeting, stores the meeting id on the booking and
     adds a `zoom_meeting` webhook route. When no host is free, it falls back to Jitsi.
7. If Zoom fails (`VideoError`), the class waits for the next run. If it starts within 30
   minutes, it gets a Jitsi room instead.
8. The link is written with one `UPDATE … WHERE meeting_url = ''`. If that writes 0 rows,
   or raises, a just-made Zoom meeting is released so no orphan booking holds a pool
   host.

**Host link** (`scheduling/services/meetings.py:host_link_for`)

- Only the session's own teacher can get it. Anyone else gets 404, and so does a
  session with no link or a cancelled session. The view also refuses while an admin is
  impersonating (`NotImpersonating`) and sends `Cache-Control: no-store`.
- For a Zoom session, `integrations.services.host_link(ref, join_url)` reads the meeting
  from Zoom on the account that video resolves to. It returns `start_url` only when the
  meeting's `join_url` still matches the session's. Otherwise the endpoint returns the
  join link with `host: false`.
- The start link is never stored, logged or listed. Session payloads expose only
  `meeting_host` (true for a Zoom session that has a ref).

**Other readers**: supervisors get `meeting_url` from `POST /supervision/<id>/open/`
(from 10 minutes before the start until the session ends).

**Metering**: Zoom's `meeting.ended` event arrives at `/api/v1/webhooks/zoom/` on the
**base domain** (`backend/config/urls_public.py` → `integrations/api/webhooks.py`). Only
meetings Etqan made for an academy have a route. For those, the event records
`video`/`minute` usage through `etqan_billing.services.record_usage` (source `etqan`).
See [etqan-billing.md](etqan-billing.md).

## API

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/api/v1/sessions/<id>/host-link/` | the session's teacher, not impersonated | `{"url", "host"}`: a fresh Zoom start link (`host: true`) or the join link |
| GET | `/api/v1/sessions/`, `/api/v1/sessions/<id>/` | see [sessions.md](sessions.md) | `meeting_url`, `meeting_host` in each row |
| PATCH | `/api/v1/slots/<id>/` | `subscription.update` | Change a slot's `meeting_url` (its untouched sessions are regenerated) |
| POST | `/api/v1/webhooks/zoom/` (base domain only) | Zoom (HMAC `x-zm-signature`) | URL validation and `meeting.ended` metering |

There is no endpoint to edit one existing session's link. Change the slot's link, which
regenerates its untouched sessions, or the teacher's default link for future sessions.

## Dashboard

- `dashboard/src/features/scheduling/bits.tsx` renders the meeting button. It shows
  nothing for a cancelled session or one with no link. When `meeting_host` is true and
  the viewer is the session's teacher, it calls `openHostLink`; everyone else gets a
  plain link.
- `dashboard/src/features/scheduling/hostLink.ts:openHostLink` opens a blank tab during
  the click (so popup blockers allow it), fetches the host link and navigates the tab to
  it. If the fetch fails, it falls back to the join link. Nothing is cached.
- Zoom account setup is in the integrations screens ([integrations.md](integrations.md)).

## Background jobs

- `scheduling.provision_meetings` (`backend/etqan/scheduling/tasks.py`) runs **every 5
  minutes** (`crontab(minute="*/5")`, `expires` 290 s, soft limit 240 s). It loops over
  academies with `for_each_academy(..., atomic=False)`: no outer transaction, because
  Zoom is called. Each class is written in its own statement.

## Configuration

- Env `JITSI_BASE_URL` (default `https://meet.jit.si`), in `backend/config/settings/base.py`.
- Feature `zoom_api` (off by default) lets an academy use Etqan's Zoom pool. With an
  academy's own connected Zoom account, meetings are made even while the feature is off.
- Academy Zoom account config: `account_id`, `client_id`, `host_user`, secret
  `client_secret`. Etqan's `PlatformAccount` for `video` adds `host_users` (the pool)
  and `webhook_secret`. All of these are stored through `etqan.integrations`, never in
  scheduling.

## Code map

- `backend/etqan/scheduling/services/meetings.py`: provisioning and the host link
- `backend/etqan/scheduling/tasks.py`: the Celery task
- `backend/etqan/scheduling/api/session_views.py:HostLinkView`
- `backend/etqan/integrations/services/video.py`: `create_meeting`,
  `meetings_wanted`, `jitsi_meeting`, `meeting_fits`, `release_meeting`, `host_link`,
  `zoom_event`
- `backend/etqan/integrations/providers/zoom.py`: Zoom API calls
- `dashboard/src/features/scheduling/hostLink.ts`, `bits.tsx`

## Design history

- [Integrations and Etqan billing spec](../superpowers/specs/2026-10-07-integrations-and-etqan-billing-design.md): the video row, the host pool (owner D21) and the host link rule (D23).
- [Integrations slice 3 plan (Zoom and Connect)](../superpowers/plans/2026-10-09-plan-integrations-3-zoom-connect.md): D6–D10 (fields, provisioning, Jitsi fallback, metering).
- [Plan 4 spec](../superpowers/specs/2026-09-24-subscriptions-scheduling-design.md) §3.5: the original "slot link, else teacher default" rule, still used at generation.
