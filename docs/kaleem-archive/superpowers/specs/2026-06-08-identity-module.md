---
name: identity-module
phase: A
modules: [identity]
status: shipped
created: 2026-06-08
closed: 2026-06-09
---

## Goal

Build the identity module: a single `User` model (via django-allauth, email-based auth) with three
optional profile types — `StudentProfile`, `TeacherProfile`, `ParentProfile`. A user may hold
multiple profile types. The parent↔child relationship links parent users to student users they
manage. This is the foundation every other module builds on.

Reference: [kaleem-product-spec](2026-06-08-kaleem-product-spec.md) — Actors section.

---

## User flows

### Registration — Adult Student
1. User visits `/register`.
2. Fills in: full name, email, password.
3. Selects account type: "I am a student".
4. Submits → verification email sent.
5. User clicks verification link → account active.
6. Redirected to onboarding: set time preferences + teacher gender preference (collected here,
   stored in StudentProfile, used later by the matching engine).
7. Onboarding complete → dashboard.

### Registration — Parent
1. User visits `/register`.
2. Fills in: full name, email, password.
3. Selects account type: "I am a parent".
4. Submits → verification email sent.
5. Clicks verification link → account active.
6. Redirected to onboarding: add at least one child.
   - Child details: full name, (optionally) date of birth.
   - Per child: time preferences + teacher gender preference.
   - This creates a linked `User` + `StudentProfile` for the child.
   - Parent can add more children at any time from their dashboard.
7. Onboarding complete → dashboard.

### Child account access
- The child receives no registration email; their account is created by the parent.
- If the child is old enough to use the platform independently, the parent can set a password
  for the child's account (or the child can trigger a password-set email from the login page).
- Both child and parent can log in and manage the child's sessions independently.

### Registration — Teacher
- Teachers do not self-register. They apply (see Teacher Application flow in product spec).
- Admin creates the teacher's account upon approval and sends a password-set email.

### Login
1. User visits `/login`.
2. Email + password.
3. On success: redirect to dashboard.
4. Failed login: show generic error (do not reveal whether email exists).

### Password reset
- Standard allauth flow: enter email → receive link → set new password.

### Profile — who am I?
- A `User` may have: a `StudentProfile`, a `TeacherProfile`, a `ParentProfile`, or any
  combination (e.g. a user who is both a parent and a student).
- Profile type determines which dashboard views and navigation items are shown.

---

## Data model

### `User` (extends AbstractBaseUser via allauth)
| Field | Type | Notes |
|---|---|---|
| id | BigAutoField | PK |
| email | EmailField | unique, used for login |
| full_name | CharField | |
| is_active | bool | allauth manages |
| is_staff | bool | True = Admin |
| date_joined | DateTimeField | |

No username field. `AUTH_USER_MODEL = "identity.User"`.

### `StudentProfile`
| Field | Type | Notes |
|---|---|---|
| id | BigAutoField | PK |
| user | OneToOneField(User) | |
| time_preferences | JSONField | list of {day, start_time, end_time} slots |
| teacher_gender_preference | CharField | choices: male, female, no_preference |
| notes | TextField | optional, internal notes |

### `TeacherProfile`
| Field | Type | Notes |
|---|---|---|
| id | BigAutoField | PK |
| user | OneToOneField(User) | |
| availability | JSONField | list of {day, start_time, end_time} slots |
| is_in_pool | bool | True = eligible for matching |
| internal_notes | TextField | admin-only notes |

### `ParentProfile`
| Field | Type | Notes |
|---|---|---|
| id | BigAutoField | PK |
| user | OneToOneField(User) | |

### `ParentStudent` (parent↔child relationship)
| Field | Type | Notes |
|---|---|---|
| id | BigAutoField | PK |
| parent | ForeignKey(ParentProfile) | |
| student | ForeignKey(StudentProfile) | |
| created_at | DateTimeField | |

Constraints: `unique_together(parent, student)`. One parent may link to many students.
One student may have at most one parent (enforced at application level in v1).

### Mini ERD

```
User
 ├── StudentProfile (0..1)
 ├── TeacherProfile (0..1)
 └── ParentProfile  (0..1)
         │
         └── ParentStudent ──► StudentProfile
```

---

## API

All endpoints under `/api/identity/`.

### `POST /api/identity/register/`
Register a new adult student or parent.
```json
// Request
{
  "full_name": "Ahmad Ali",
  "email": "ahmad@example.com",
  "password": "...",
  "account_type": "student" | "parent"
}

// Response 201
{
  "id": 1,
  "email": "ahmad@example.com",
  "full_name": "Ahmad Ali",
  "account_type": "student"
}

// Error 400 — email already registered
{ "email": ["A user with this email already exists."] }
```

### `POST /api/identity/login/`
```json
// Request
{ "email": "...", "password": "..." }

// Response 200 — sets session cookie
{ "id": 1, "email": "...", "full_name": "...", "profiles": ["student"] }

// Error 400
{ "non_field_errors": ["Invalid credentials."] }
```

### `POST /api/identity/logout/`
Clears session. Returns 200.

### `GET /api/identity/me/`
Returns the current user and their profile types.
```json
{
  "id": 1,
  "email": "...",
  "full_name": "...",
  "profiles": ["parent"],
  "children": [
    { "id": 2, "full_name": "Yusuf Ali", "student_profile_id": 3 }
  ]
}
```

### `PATCH /api/identity/me/`
Update full_name or email (email change re-triggers verification).

### `POST /api/identity/me/student-profile/`
Set or update StudentProfile preferences.
```json
{
  "time_preferences": [
    { "day": "monday", "start_time": "17:00", "end_time": "20:00" }
  ],
  "teacher_gender_preference": "female"
}
```

### `POST /api/identity/children/`
Parent adds a child. Creates a User + StudentProfile + ParentStudent link.
```json
// Request
{
  "full_name": "Yusuf Ali",
  "time_preferences": [...],
  "teacher_gender_preference": "no_preference"
}

// Response 201
{ "child_user_id": 5, "student_profile_id": 3 }
```

### `GET /api/identity/children/`
Parent lists their linked children with basic profile info.

### `POST /api/identity/children/{student_profile_id}/set-password/`
Parent sets or resets a child's login password.
```json
{ "password": "..." }
```

### `POST /api/identity/invites/`
Parent generates a one-time invite code to link an existing student account.
```json
// Response 201
{ "code": "abc123", "expires_at": "2026-06-09T12:00:00Z" }
```
Code expires after 24h. One active invite per parent at a time.

### `POST /api/identity/invites/accept/`
Logged-in student accepts a parent invite.
```json
// Request
{ "code": "abc123" }

// Response 200
{ "parent_name": "Fatima Hassan", "linked": true }

// Error 400 — expired or invalid code
{ "code": ["Invalid or expired invite code."] }

// Error 400 — student already has a parent
{ "code": ["You are already linked to a parent account."] }
```

---

## Module boundaries

- **Owns:** `User`, `StudentProfile`, `TeacherProfile`, `ParentProfile`, `ParentStudent`.
- **Exposes via `identity.services`:**
  - `get_user(user_id)` → User
  - `get_student_profile(user_id)` → StudentProfile | None
  - `get_teacher_profile(user_id)` → TeacherProfile | None
  - `get_parent_profile(user_id)` → ParentProfile | None
  - `get_children(parent_user_id)` → list[StudentProfile]
  - `is_parent_of(parent_user_id, student_user_id)` → bool
  - `create_child(parent_user_id, full_name, preferences)` → StudentProfile
- **Does not import from:** any other business module.
- **Other modules import from:** `identity.services` only. Never `identity.models` directly.

---

## Out of scope

- Social login (Google, Apple) — later phase.
- MFA — allauth supports it, wire up later.
- Teacher self-registration — admin-created accounts only in v1.
- Profile photos.
- Student level / subject preferences — added when matching engine needs them (Phase C).
- Deactivating or deleting accounts.

---

## Test plan

### Happy path
- Adult student registers → email verified → StudentProfile created → preferences saved.
- Parent registers → adds two children → each child has StudentProfile + ParentStudent link.
- Login with correct credentials → session cookie set → `GET /api/identity/me/` returns correct profiles.
- Logout → session cleared → `GET /api/identity/me/` returns 403.
- Parent sets child password → child can log in with that password.
- `is_parent_of()` returns True for linked pairs, False for unlinked.

### Edge cases
- Register with duplicate email → 400 with clear error.
- Login with wrong password → 400, generic message (no email enumeration).
- Non-parent calling `POST /api/identity/children/` → 403.
- `is_parent_of()` called with a student the parent did not create → False.
- User with both StudentProfile and ParentProfile → `profiles` field returns both.

### Boundary
- Any other module calling `identity.models.User` directly → import-linter fails CI.

---

## Open questions

| # | Question | Status |
|---|---|---|
| IQ-01 | Should a student be allowed to link themselves to a parent after registration (parent sends invite)? | **Resolved: Yes.** Parent generates an invite link/code. Student accepts → ParentStudent link created. |
| IQ-02 | Max number of children per parent enforced at DB level or application level only? | **Resolved: No limit.** Application level only, no hard cap. |
