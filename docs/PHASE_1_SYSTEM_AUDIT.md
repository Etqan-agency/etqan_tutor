# Phase 1 — System Audit

**Subject system:** TutorHamster (demo instance — `https://www.demo.tutorhamster.com`)
**Audit scope:** Admin panel (`/admin`) authenticated as `super_admin`, plus unauthenticated inspection of the Teacher, Parent and Student panels and public routes.
**Audit dates:** 2026-09-15 and 2026-09-23
**Auditor access level:** `super_admin` (user `م.عبدالوهاب` / `demo@tutorhamster.com`)
**Method:** UI walkthrough, DOM/accessibility-tree extraction, authenticated same-origin `fetch()` of server-rendered pages, route probing, network-request inspection, and extraction of the Livewire component state backing the roles/permissions screen.

> **Scope rule observed:** this document describes *what exists*. It contains no design proposals, no technology recommendations, and no implementation plan. Where a behaviour could not be verified it is marked `UNKNOWN` rather than guessed.

**Evidence levels used throughout:** `CONFIRMED` (directly observed), `PROBABLE` (strongly implied by observed artefacts), `INFERRED` (reasonable reading of evidence), `UNKNOWN` (insufficient evidence).

---

## 1. Executive Summary

TutorHamster is a **multi-tenant-style, single-academy operations platform for online 1:1 and small-group tutoring**, strongly oriented toward Arabic/Qur'an teaching but not limited to it. It is a **commercial licensed product**, not bespoke software: the system reports a version number, a license ID, and an activation-code subsystem, and a vendor ("Olovix") is visible in internal settings and staff email addresses.

The product's centre of gravity is **not** content delivery (it is not an LMS in the Moodle sense). It is **academy operations**: selling packages, converting a package into a recurring weekly timetable, materialising that timetable into individual session records, tracking two-sided attendance on each session, and deriving both student billing and teacher payroll from those session records.

Structurally the system is:

* **Four separate authentication panels** — Admin, Teacher, Parent (all Filament/Livewire) and Student (a separate custom Blade + jQuery application with its own registration, OAuth and OTP password-reset flows).
* **~54 discoverable admin CRUD modules**, of which **only 34 appear in the sidebar**. Twenty are reachable only via context buttons on other screens or by direct URL.
* **71 permission-gated resources** in the authorization layer — i.e. the backend knows about ~17 more business objects than the admin navigation exposes.
* **34 feature flags** in a developer settings tab, which switch entire subsystems (homework, certificates, family accounts, consultations, supervision, donations, recorded courses, per-country pricing, Excel export, archives, contracts, …) on and off. The same codebase is evidently sold in tiers.
* **Deep third-party integration surface** configured entirely from the UI: Stripe, PayPal, country-specific manual payment methods, Zoom, kMeet, Jitsi (live classroom), WhatsApp (including group IDs), Google OAuth, Google reCAPTCHA, Google Gemini (AI content generation), TinyMCE, an IP geolocation API, a currency exchange-rate API, SMTP, a Qur'an chapters API, and a vendor "Olovix" device/client identity.

**The three engines that constitute the actual product value** (and which are the hardest parts of the domain) are:

1. **Schedule → session materialisation.** A subscription owns weekly recurring slots; a dedicated "today's sessions" board shows which of today's slots have not yet been turned into session records, and offers single and bulk (date-range) generation.
2. **Subscription consumption accounting.** Attended sessions, extra out-of-package sessions, total package sessions, progress %, freeze/suspension day allowance, renewal and archival.
3. **Attendance-derived teacher payroll.** Completed / student-absent / compensation / excused / trial sessions, per-course hourly rates, deductions, incentives, report-submission penalties, per-teacher currency, monthly salary invoices, and withdrawal requests.

**Most significant audit findings:**

* The admin UI **understates the system**: a fifth of its modules are hidden from navigation, and the permission layer references entities with no UI entry point at all.
* Session records carry **an unusually wide field set** (~50 attributes including separate teacher/student in/out timestamps, substitute teacher, supervisor attendance, per-session notification scheduling timestamps, meeting ID/password, and compensation linkage) and a **field-level activity log with revert capability**.
* **Authorization is genuinely enforced**, not cosmetic: at least one page (`/admin/quick-translate`) returns HTTP 403 to a `super_admin`.
* A **fourth actor type — "مشرف" (Supervisor)** — exists in the messaging layer and on session records (`supervisor_id`, `supervisor_attendance`, `is_session_opened_by_supervisor`) even though there is no Supervisor panel.
* **AI (Gemini) is woven into content workflows**, not bolted on: article body/SEO generation, course descriptions, category descriptions, employment-contract drafting, and **AI-generated monthly student reports**.

---

## 2. System Overview

### 2.1 Technology stack (CONFIRMED unless noted)

| Item | Value | Evidence |
|---|---|---|
| Application framework | Laravel **10.50.2** | `/admin/system-status` |
| PHP | **8.5.8** | `/admin/system-status` |
| Admin UI framework | **Filament 3.3.50** | asset query strings `?v=3.3.50.0`; `.fi-*` DOM classes |
| Frontend runtime | **Livewire 3** (`/livewire/update`), Alpine.js | network trace |
| Realtime | `filament/filament/echo.js` loaded → **Laravel Echo / broadcasting present** (PROBABLE: used by chat + notifications) | network trace |
| Product name / version | TutorHamster, **النسخة: 18** | `/admin/system-status` |
| License | `ID: OLO-VXXX`, status **مرخص** (licensed) | `/admin/system-status` |
| Vendor | **Olovix** (`abdelwhab@olovix.com`; `OLOVIX UID` / `OLOVIX DEVICE UID` settings; "نظام أولوفيكس الداخلي" flag) | users list, system settings |
| Demo environment | `local`, **debug mode enabled** | `/admin/system-status` |
| Live classroom | **Jitsi** — `https://meet.jit.si/external_api.js` | `/class/{uid}` source |

**Filament plugin surface observed in asset requests** (PROBABLE inventory): `amidesfahani/filament-tinyeditor`, `malzariey/filament-lexical-editor`, `dotswan/filament-grapesjs-v3` (drag-and-drop page builder), `codewithkyrian/filament-date-range`, `husam-tariq/filament-timepicker`, `njxqlus/filament-progressbar`, `swisnl/filament-backgrounds`, `tapp/filament-country-code-field`, `hasnayeen/themes`, plus `bezhanSalleh/filament-shield` (authorization) and a custom `app/sketchpad` asset.

### 2.2 Panels / surfaces

| ID | Surface | Path | Stack | Notes | Evidence |
|---|---|---|---|---|---|
| PANEL-001 | Admin | `/admin` | Filament | Full operations console. Audited in depth. | CONFIRMED |
| PANEL-002 | Teacher | `/teacher` → `/teacher/login` | Filament | Login page only observed (no credentials). No password-reset route (404). | CONFIRMED (existence) / UNKNOWN (contents) |
| PANEL-003 | Parent | `/parent` → `/parent/login` | Filament | Login page only observed. No password-reset route (404). | CONFIRMED (existence) / UNKNOWN (contents) |
| PANEL-004 | Student | `/student/login` | **Custom Blade + jQuery** (not Filament) | Own registration, Google OAuth, OTP reset. Richest public-facing surface. | CONFIRMED |
| PANEL-005 | Live classroom | `/class/{session_uid}` | Blade + Jitsi external API | Public-by-URL meeting room, renders session info overlay. | CONFIRMED |
| PANEL-006 | Public marketing site | `/`, `/courses`, `/pricing` | — | **Disabled on the demo**: redirects to `/system-only-error` ("Restricted Area"). Exists in the product (site settings, site pages, SEO fields, articles all target it). | CONFIRMED (disabled) / INFERRED (exists in production) |
| PANEL-007 | Simplified sessions view | `/onlyadmin/sessions-lite` | Filament page under a **separate route prefix** `/onlyadmin` | "النسخة المبسطة للحصص". `/onlyadmin` root itself is 404. | CONFIRMED |

`robots.txt` disallows `/admin`, `/teacher`, `/student`, `/parents` and references `/sitemap.xml` (which 404s on the demo) — corroborating a public site in production.

### 2.3 Localisation, theming, timezones

* **Languages:** Arabic (default), English, Spanish — switched via `/select-language/{ar|en|es}`. UI is **RTL-first**. Some subsystems are bilingual at the *data* level (FAQs have Arabic and English tabs; every automated notification template has Arabic and English variants). CONFIRMED.
* **Theming:** light / dark / system toggle; configurable primary colour; four named themes — Default, Dracula, Nord, Sunset (`/admin/themes`). CONFIRMED.
* **Timezones:** system timezone setting (`Africa/Cairo` on the demo), plus **per-student, per-teacher and per-parent timezone fields**, and a timezone captured automatically at student registration/login. Session forms explicitly state times are set in the system timezone; the weekly-schedule list is labelled "المواعيد (توقيت النظام)". CONFIRMED.
* **Currencies:** multi-currency is pervasive — packages have a currency and optional **per-country price overrides**; teachers are paid in their own currency (EGP and USD observed side by side in one payroll table); payments, expenses, deductions, incentives and invoices each carry a currency. An **Exchange Rate API** key exists in settings. CONFIRMED (multi-currency) / INFERRED (automatic conversion).

### 2.4 Navigation structure (sidebar, 11 groups / 34 entries)

```
لوحة التحكم (Dashboard)
الرسائل (Messages) · مجموعات المحادثة (Chat groups)
إدارة النظام      → الدورات · الباقات · الاشتراكات · الجدول الأسبوعي · الإشعارات
إدارة الحصص       → حصص اليوم الاساسية · سجلات الحصص · الحصص التجريبية
إدارة المستخدمين  → أولياء الأمور · المعلمين · الطلاب · المستخدمين
الإدارة           → أكواد النظام · طلبات التواصل
المالية           → طلبات سحب الرواتب · سجلات الدفع · المصروفات ·
                    رواتب المعلمين الشهرية · سجلات التبرعات · روابط الدفع
إدارة المناهج     → المحتوى التعليمي · المستويات · القرآن الكريم
إدارة الشهادات    → الشهادات · قوالب الشهادات
المحتوى           → المقالات · مكتبة الفيديوهات · الأسئلة الشائعة · آراء طلابنا
الكورسات المسجلة  → قوائم التشغيل · فيديوهات قوائم التشغيل
إدارة الاستشارات  → الاستشارات · طلبات الاستشارات
```

Sidebar entries display **live record-count badges**. A **"Quick Create"** control in the topbar offers: Student, Teacher, Family account, Subscription, Schedule, Notification. The **user menu** exposes: Profile, Two-Factor Authentication, View site, Site settings, File uploads, System settings, Roles & permissions, System status, Themes, Logout.

---

## 3. Feature Map

```text
TutorHamster
├── Authentication & Access (AUTH)
│   ├── Admin login / logout / remember-me
│   ├── Admin password reset request
│   ├── Two-factor authentication (setup, challenge, OTP verify)
│   ├── Teacher login (no self-service reset)
│   ├── Parent login (no self-service reset)
│   ├── Student login (email OR phone, remember-me)
│   ├── Student Google OAuth
│   ├── Student registration — standard 3-step wizard
│   ├── Student registration — "Enhanced" onboarding funnel
│   ├── Student password reset via OTP (email / phone / student UID)
│   ├── Quick-login impersonation (admin → student, admin → teacher)
│   ├── Quick-login link delivery (single + bulk)
│   └── Language switching (ar / en / es)
├── Authorization (RBAC)
│   ├── Roles CRUD (Filament Shield)
│   ├── 71 resource permission groups × 12 action verbs
│   ├── Page-level permissions (5) + custom page permissions (3)
│   ├── Widget-level permissions (5 + 1 custom)
│   └── Admin user ↔ role assignment
├── Dashboard & Analytics (DASH)
│   ├── Student stats · Subscription stats · Revenue stats · Session stats
│   ├── Student overview charts (age group, gender, country, account type, monthly signups)
│   └── Greeter widget
├── People (PEOPLE)
│   ├── Students (7-tab profile, XP, wallet, tags, status lifecycle)
│   ├── Family accounts (grouped students, payer designation)
│   ├── Groups (student cohorts)
│   ├── Parents (children linkage, WhatsApp flag)
│   ├── Teachers (7-tab profile, contracts, media, consultation opt-in)
│   ├── Employment contracts (AI-drafted)
│   ├── Honor board
│   └── Admin users
├── Catalogue (CATALOG)
│   ├── Courses (+ categories, SEO, schema, Qur'an linkage, certificates)
│   ├── Packages (sessions/week, duration, freeze days, per-country pricing)
│   ├── Levels & sub-levels / topics
│   ├── Level upgrade requests
│   ├── Qur'an chapters (API sync)
│   └── Educational content (per-course files)
├── Commerce (SUB)
│   ├── Subscriptions (5-tab: info, schedule, summary, levels, roster)
│   ├── Subscription renewal
│   ├── Subscription archive (expired)
│   ├── Soft delete ("delete keeping records") vs hard delete
│   └── System codes (activation / renewal / discount)
├── Scheduling & Delivery (SCHED)
│   ├── Weekly schedules (day/course/teacher/start/end repeater)
│   ├── Calendar expansion view + schedule download
│   ├── Today's sessions board (generation status per slot)
│   ├── Single + bulk (date-range) session generation
│   ├── Sessions (attendance, report, compensation, notifications)
│   ├── Simplified sessions view (/onlyadmin)
│   ├── Session archive (expired sessions)
│   ├── Trial sessions (lead → teacher match → outcome)
│   ├── Extra sessions (out-of-package)
│   ├── Session reports (behaviour/participation ratings)
│   ├── Session reviews
│   ├── Homework (file or text, student response, teacher comment)
│   ├── Per-session activity log with field-level diff + revert
│   └── Jitsi classroom rooms
├── Student Billing (BILL)
│   ├── Payment records (gateway + manual)
│   ├── Monthly student invoices (+ unpaid-invoice notification)
│   ├── Payment links (PayPal/Stripe, 5% service fee toggle)
│   ├── Country-specific manual payment methods (with instructions)
│   ├── Donations
│   └── Student wallet balance
├── Teacher Payroll (PAY)
│   ├── Per-course hourly rates (single + bulk assignment)
│   ├── Deductions · Incentives (fixed or %)
│   ├── Monthly salary computation from session records
│   ├── Salary projections
│   ├── Monthly salary invoices/receipts (+ teacher acknowledgement)
│   ├── Salary withdrawal requests
│   ├── Report-submission deduction rules
│   └── Expenses / net profit
├── Certificates (CERT)
│   ├── Certificate templates
│   └── Issued certificates (auto session count, admin message)
├── Communications (COMM)
│   ├── Internal messaging (student/teacher/supervisor/admin/broadcast)
│   ├── Chat groups
│   ├── Notification records (targets, channels, status)
│   ├── 12+ automated notification templates (ar + en)
│   ├── WhatsApp group routing (global + per-teacher override)
│   └── Per-user notification preference toggles
├── Marketing & Content (CNT)
│   ├── Articles (+ categories, AI generation, SEO, schema, attachments)
│   ├── Video library
│   ├── FAQs (ar/en)
│   ├── Student testimonials (text/audio/video)
│   ├── Site pages (GrapesJS builder + SEO)
│   ├── Advertisements (general / discount, expiry)
│   ├── URL redirects
│   └── Site settings (branding, social, legal texts, SEO, custom header/ad code)
├── Recorded Courses (RC)
│   ├── Playlists (pricing, discount, certificate, app-only flag)
│   ├── Playlist videos (link/file/live, order, downloadable)
│   ├── RC subscriptions (+ watched-video tracking)
│   ├── RC comments · RC reviews
├── Consultations (CONS)
│   ├── Consultation products (price, duration, delivery mode, participants)
│   ├── Consultation requests (booking, payment, attendance, reschedule)
│   ├── Consultation reviews · consultation schedules
│   └── Teacher profit-margin export
├── Inbound (LEAD)
│   ├── Contact requests
│   ├── Trial session requests (source, "how did you hear about us")
│   └── Request centre (permission exists; no reachable UI)
├── Reporting & Export (EXP)
│   ├── Monthly student reports (AI-generated)
│   ├── Excel exports: subscriptions, sessions, expired sessions, trial sessions,
│   │   teacher salaries, consultation requests, teacher profit margins
│   ├── Student data export
│   └── Schedule download
└── Platform (SYS)
    ├── System settings (9 tabs incl. 34 feature flags)
    ├── Site settings (4 tabs)
    ├── Integrations (Stripe, PayPal, Zoom, kMeet, WhatsApp, Google OAuth,
    │   reCAPTCHA, Gemini, TinyMCE, IP API, Exchange Rate API, SMTP, Olovix)
    ├── Themes
    ├── File uploads library
    ├── System status (version, license, env, cache clear, manual jobs)
    ├── Quick translate (403 — inaccessible)
    └── Translations / language lines (permission exists; no reachable UI)
```

---

## 4. Feature Inventory

Conventions: **Access** column states the role observed to have access. Because only two roles exist on the demo (`super_admin`, `Supervisor`) and the audit was performed as `super_admin`, access for other roles is `INFERRED` from the permission model unless stated. Every feature below is `CONFIRMED` to exist unless its row says otherwise.

### 4.1 Authentication & access — AUTH

| ID | Feature | Where | Inputs | Outputs / effects | Notes & evidence |
|---|---|---|---|---|---|
| AUTH-001 | Admin login | `/admin` | email, password, remember-me | Authenticated admin session | Filament login. "نسيت كلمة المرور؟" link present. CONFIRMED |
| AUTH-002 | Admin password reset request | `/admin/password-reset/request` | email (assumed) | UNKNOWN | Route exists and is linked from the login page, but an authenticated `fetch` of it redirected to `/parent/login`. Behaviour `UNKNOWN — requires unauthenticated test` |
| AUTH-003 | Two-factor authentication | `/admin/two-factor` | UNKNOWN | UNKNOWN | Page exists (HTTP 200, title "Two-Factor Authentication"). Permission keys `page_TwoFactor`, `page_LoginTwoFactor`, `page_TwoFactorySetup`, `page_OTPVerify` all exist → challenge, setup and OTP-verify screens are separate pages. CONFIRMED (exists) / UNKNOWN (mechanism: TOTP vs email/SMS OTP) |
| AUTH-004 | Teacher login | `/teacher/login` | email, password, remember | Teacher panel session | Filament panel. `/teacher/password-reset/request` → **404**, so teachers have **no self-service password reset**. CONFIRMED |
| AUTH-005 | Parent login | `/parent/login` | email, password, remember | Parent panel session | Same as above; `/parent/password-reset/request` → **404**. CONFIRMED |
| AUTH-006 | Student login | `/student/login` | **email *or* phone**, password, remember | Student session | Form also posts hidden `timezone`, `device_type`, `ip_address`, `fav_language` — this is the source of the Student record's device/IP/timezone/language fields. CONFIRMED |
| AUTH-007 | Student Google OAuth | `/student/auth/google` | Google account | Student session | Requires `GOOGLE_CLIENT_ID`/`SECRET` in system settings. CONFIRMED (route + settings) |
| AUTH-008 | Student registration (standard) | `/student/register` | 3-step wizard: **1 Personal Info** (name, email, age, phone) → **2 Details** (country, gender, account type) → **3 Security** (password, confirmation, consent checkbox) | Student record (PROBABLE: pending status) | CONFIRMED (form structure) |
| AUTH-009 | Student registration (Enhanced) | `/student/proregister` | Age-group choice first: **Minor → family account for multiple students**, **Adult → individual account**. Then name, email, DOB, phone (with country code splitting), gender, password, auto-detected timezone, country, derived age group, **desired start date**, **total hours per week**, **preferred class days (7 checkboxes)**, **intro call day + time**, **teacher preference** | Student record + scheduling preferences | This is the sales/onboarding funnel; it captures everything needed to propose a timetable and book an intro (trial) call. CONFIRMED |
| AUTH-010 | Student password reset (OTP) | `/student/password/forgot` | **Identifier type: Email / Phone number / Student ID (UID)** → identifier → **account selection when one phone matches several accounts** → **4-digit OTP** → new password + confirmation | Password changed | Full multi-step OTP flow with explicit multi-account disambiguation. CONFIRMED |
| AUTH-011 | Quick login (impersonation) | Students list, Teachers list — row action "دخول سريع" | — | Opens `/student/STD-#####` or `/teacher/TCH-#####` as that user | CONFIRMED. Public-code URLs; no confirmation dialog observed |
| AUTH-012 | Send quick-login link | Teachers list row action + **bulk action** "إرسال رابط الدخول السريع"; also a Students bulk action | Selected user(s) | Email/notification containing the quick-login link | CONFIRMED (actions exist) / UNKNOWN (channel, expiry) |
| AUTH-013 | Logout | Topbar user menu, all panels | — | Session destroyed | CONFIRMED |
| AUTH-014 | Language switch | `/select-language/{ar\|en\|es}` | — | Locale switched | CONFIRMED |
| AUTH-015 | Own profile edit | `/admin/profile` | name, email, new password | Admin account updated | Only 3 fields. CONFIRMED |

**Security-relevant observations (CONFIRMED):**

* Quick-login URLs are **guessable-shaped public codes** (`STD-68337`, `TCH-47359`). Whether they require an authenticated admin session was not tested — `UNKNOWN, HIGH priority`.
* Classroom URLs (`/class/S-I7T5J`) rendered full session details (teacher name, student name, subject, date, and the *viewing* user's name and email) and were fetched successfully; whether they are reachable unauthenticated was not isolated — `UNKNOWN, HIGH priority`.
* The `super_admin`'s own row in the users list shows **no edit/delete actions**, while the other user's row does → self-deletion appears blocked. `PROBABLE`.

### 4.2 Authorization — RBAC

| ID | Feature | Detail | Evidence |
|---|---|---|---|
| RBAC-001 | Roles CRUD | `/admin/shield/roles` — columns: title, guard name, permission count, updated at. Form: title, guard name, "select all", then one permission group per resource | CONFIRMED |
| RBAC-002 | Resource permissions | **71 resource groups × 12 verbs** = 852 permission records. Verbs: `view`, `view_any`, `create`, `update`, `restore`, `restore_any`, `replicate`, `reorder`, `delete`, `delete_any`, `force_delete`, `force_delete_any` (Arabic: عرض، عرض الكل، إضافة، تعديل، استرجاع، استرجاع الكل، استنساخ، إعادة ترتيب، حذف، حذف الكل، إجبار الحذف، إجبار حذف أي) | CONFIRMED — extracted from the role form's Livewire state |
| RBAC-003 | Exception: `role` | The `role` resource has only **6** verbs (`view`, `view_any`, `create`, `update`, `delete`, `delete_any`) — no restore/replicate/reorder/force-delete | CONFIRMED |
| RBAC-004 | Page permissions | `page_QuickTranslate`, `page_Themes`, `page_TwoFactor`, `page_LoginTwoFactor`, `page_SystemStatus` | CONFIRMED |
| RBAC-005 | Custom permissions | `page_OTPVerify`, `page_TwoFactorySetup`, `widget_GreeterWidget` | CONFIRMED |
| RBAC-006 | Widget permissions | `widget_StudentsStatsWidget`, `widget_SubscriptionsStatsWidget`, `widget_RevenueStatsWidget`, `widget_SessionsStatsWidget`, `widget_StudentsOverviewWidget` | CONFIRMED |
| RBAC-007 | Total permission surface | **856 distinct permission values** rendered on the role form; `super_admin` holds **847** | CONFIRMED (counts read from the page) |
| RBAC-008 | Role assignment | `/admin/users` create/edit — multi-select "الأدوار" | CONFIRMED |
| RBAC-009 | Enforcement | `/admin/quick-translate` returns **HTTP 403 "Unauthorized"** to `super_admin` | CONFIRMED — authorization is real and this page is gated by something beyond the role (INFERRED: a feature flag or vendor-only guard) |
| RBAC-010 | `request::center` anomaly | Permission group exists, **zero verbs granted to `super_admin`**, and `/admin/request-center` is 404 | CONFIRMED (observation) / INFERRED (feature disabled in this build) |

**The 71 permission-gated resources** (Arabic label → permission key):

`إعلان`→advertisement · `عقد عمل`→agreement · `مقال`→article · `فئة مقال`→article::category · `شهادة`→certificate · `قالب شهادة`→certificate::template · `استشارة`→consultation · `طلب استشارة`→consultation::request · `تقييم استشارة`→consultation::review · `موعد استشارة`→consultation::schedule · `طلب تواصل`→contact::request · `رسالة`→conversation · `مجموعة المحادثة`→conversation::group · `دورة`→course · `تصنيف الدورة`→course::category · `سجل تبرع`→donation::record · `محتوى تعليمي`→educational::content · `مصروف`→expense · `حصة (أرشيف)`→expired::sessions · `اشتراك (أرشيف)`→expired::subscription · `حصة إضافية`→extra::session · `حساب عائلة`→family::account · `الأسئلة الشائعة`→faq · `ملف`→file::upload · `مجموعة`→groups · `واجب`→homework · `تكريم`→honor::board · `فاتورة شهرية`→invoice · `ترجمات`→language::line · `المستوى`→level · `طلب رفع المستوى`→level::upgrade::request · `إشعار`→notification · `باقة`→package · `ولي أمر`→parent · `رابط دفع`→payment::link · `وسيلة دفع`→payment::method · `سجل دفع`→payment::record · `قائمة تشغيل`→play::lists · `فيديو قائمة التشغيل`→playlist::videos · `سورة`→quran::chapter · `تعليق`→rc::comments · `تقييم`→rc::reviews · `اشتراك (كورسات مسجلة)`→rc::subscriptions · `رابط`→redirect · `طلب`→request::center · `دور`→role · `طلب سحب راتب`→salary::withdrawal::request · `حصة`→session · `تقرير حصة`→session::report · `تقييم حصة`→session::review · `صفحة موقع`→site::page · `إعدادات الموقع`→site::setting · `طالب`→student · `تقرير طالب`→student::report · `شهادات الطلاب`→student::review · `اشتراك`→subscription · `كود نظام`→system::code · `إعدادات النظام`→system::setting · `معلم`→teacher · `أجر الساعة للمعلم`→teacher::course::rate · `خصم معلم`→teacher::deduction · `حافز معلم`→teacher::incentive · `راتب معلم شهري`→teacher::salary · `إيصال راتب شهري`→teacher::salary::invoice · `جدول مواعيد`→teacher::schedule · `رابط زووم`→teacher::zoom::link · `حصة اليوم الاساسية`→today::session · `حصة تجريبية`→trial::session · `مستخدم`→user · `فيديو`→video · `موعد`→weekly::schedule

### 4.3 Dashboard — DASH

| ID | Feature | Detail | Evidence |
|---|---|---|---|
| DASH-001 | Student stat cards | Total students · New students this month · **Student growth rate vs previous month (%)** | CONFIRMED |
| DASH-002 | Subscription stat cards | All subscriptions · Active · Expired (each links to a pre-filtered list, e.g. `?tableFilters[subscription_status][status]=incomplete`) | CONFIRMED |
| DASH-003 | Revenue stat cards | Revenue this month (from **completed** payment records) · Expenses this month · **Net profit this month** | CONFIRMED |
| DASH-004 | Session stat cards | Sessions this month · Sessions today · **Total sessions ever (live table + archive)** | CONFIRMED — the label explicitly says it sums the sessions table *and* the archive table |
| DASH-005 | Student overview charts | Age groups · Gender · Countries · Account type · Monthly registrations | CONFIRMED |
| DASH-006 | Greeter widget | Personalised greeting ("مرحباً {name}") | CONFIRMED |
| DASH-007 | Stat sparklines | Stat cards render mini charts (`stats-overview/stat/chart.js`) | CONFIRMED |

### 4.4 People — PEOPLE

#### PEOPLE-001 — Students (`/admin/students`)

* **Purpose:** the customer record and the anchor of subscriptions, sessions, billing and gamification.
* **List:** columns *Photo · Student name (+email) · Country · Account type · Student status*. Status tabs with counts: **نشط (active) · قيد الانتظار (pending) · تجريبي (trial) · قيد التقدم (in progress) · متوقف مؤقتا (paused) · غير نشط (inactive) · الكل**.
* **Filters:** Country, Nationality, Timezone, Account type, Status, plus a custom "الشرط" condition filter.
* **Header actions:** Add student · **Monthly reports** (`/admin/student-reports`) · **Export data**.
* **Row actions:** Edit · **Quick login**.
* **Bulk actions:** Delete selected · **Convert to active** · **Convert to inactive** · **Send quick-login link** · **Convert to family account** · **Create family account**.
* **Form — 7 tabs, 30 fields:**
  * *معلومات أساسية*: photo, name\*, date of birth\*, gender\*, **account type\*** (فرد/عائلة), age group, **registration date\***, tags (multi), active toggle.
  * *معلومات الاتصال*: email\*, **alias email**, phone\* (country code + `+` required per hint), postal code, country\*, nationality\*, timezone.
  * *معلومات تقنية*: device type, IP address.
  * *الحساب والأمان*: preferred language\*, status\*, password\*.
  * *التفضيلات*: 7 toggles — session notifications, chat notifications, payment reminders, schedule-update notifications, reports & homework notifications, **can create conversations**, **chat system enabled**.
  * *ولي الأمر*: parents (multi) + "new parent" toggle revealing either a new-parent sub-form or an existing-parent selector.
  * *الأرصدة والنقاط*: **wallet balance** (hint: used to pay invoices/subscriptions and to compensate students for sessions) and **XP points**.
* **Public identifier:** `STD-#####`.
* Evidence: CONFIRMED (all of the above directly observed).

#### PEOPLE-002 — Family accounts (`/admin/family-accounts`, hidden)

Fields: family name\*, **linked accounts\*** (only students whose account type is *عائلي*; "a student already linked cannot be added again"), **account responsible for payment\***, notes, active toggle. Reached from the Students screen and from Quick Create. CONFIRMED.

#### PEOPLE-003 — Groups (`/admin/groups`, hidden)

Fields: group name\*, **linked students\*** (individual or family accounts; a student already in a group cannot be added again), notes, active. Columns: group name, linked accounts, status. CONFIRMED.

#### PEOPLE-004 — Parents (`/admin/parents`)

Tabs: Basic data · Children & account · Extra settings · Password. Fields: name\*, email\*, phone\*, **registered on WhatsApp** toggle, children (multi-select), account active toggle, registration date\*, preferred language, timezone, password\* (**hint: minimum 8 characters** — the only explicit password rule seen anywhere). Filters: account status, WhatsApp. CONFIRMED.

#### PEOPLE-005 — Teachers (`/admin/teachers`)

* **List columns:** Photo · Teacher name (+email) · Gender + age · **Rating (★ scale with label, e.g. "ضعيف", "غير مقيم")** · Status. Row actions: Edit · Delete · **Quick login** · **Send quick-login link**. Filter: status.
* **Form — 7 tabs:**
  * *المعلومات الأساسية*: photo, name\*, gender\*, DOB, address\*, **identifier (auto-generated)**, preferred language\*, tags.
  * *معلومات الاتصال*: email\*, phone\*, second phone, timezone.
  * *المعلومات المالية*: **salary payout method\***, payment method details\*, **current balance**, note.
  * *السيرة والمهارات*: bio\*, **CV upload (PDF/Word/image)**, skills & subjects taught.
  * *الوسائط*: "add media" toggle → media file.
  * *عقود العمل*: contracts repeater (identifier, details, contract file).
  * *الإعدادات*: **offers consultations** toggle, enabled\*, **show on homepage\***, **rating\* (1–5)**, **dashboard style\***, **custom notification group** toggle, password\*.
* **Public identifier:** `TCH-#####`. CONFIRMED.

#### PEOPLE-006 — Employment contracts (`/admin/agreements`, hidden)

Fields: teacher\*, **details (with an "إنشاء صيغة العقد" AI generate action)**, contract file. CONFIRMED.

#### PEOPLE-007 — Honor board (`/admin/honor-boards`, hidden)

List page exists with "إضافة لوحة شرف جديدة"; the `/create` route 404s (the create form is `PROBABLE` a modal). Permission key `honor::board`. CONFIRMED (exists) / UNKNOWN (fields).

#### PEOPLE-008 — Admin users (`/admin/users`)

Columns: name, email, roles. Form: name\*, email\*, password\*, roles (multi). Filter: role. CONFIRMED.

### 4.5 Catalogue — CATALOG

| ID | Feature | Key fields / behaviour | Evidence |
|---|---|---|---|
| CATALOG-001 | Courses (`/admin/courses`) | 4 tabs. Media: banner, image-or-video, icon. Core: name\*, **slug\***, category\*, **teachers\* (multi)**, short description\* (**AI generate**), active, **visible\***, requirements, **lesson count\***, **certificate toggle**, **"linked to the Qur'an curriculum" toggle**, course language\* (Arabic/English/both), overview\* (**AI generate**). SEO tab: SEO title, SEO description (**AI generate**), keywords. Schema tab: schema codes repeater. List columns: name, teacher count, status, created. **Bulk: duplicate course, delete.** Slug-based URLs (`/admin/courses/{slug}/edit`) | CONFIRMED |
| CATALOG-002 | Course categories (`/admin/course-categories`, hidden) | icon, name\*, slug\*, description (**AI generate**) | CONFIRMED |
| CATALOG-003 | Packages (`/admin/packages`) | 4 tabs / 7 sections. image, name\*, description\*, **features\***, **weekly lesson count\***, **package type\*** (فردية/جماعية), **session duration\*** (30/45/60/other), **duration\* + unit\*** (day/month), **max package days\***, **allowed freeze days\***, hourly price, **discount %**, **price\***, currency\* (USD), active, **visible\***, **popular**, **per-country price overrides (repeater)**. List: name, price, duration, session duration, status. Filters: status, visibility. **Bulk: duplicate package, activate, deactivate** | CONFIRMED |
| CATALOG-004 | Levels (`/admin/levels`) | course\*, level name\*, **sub-levels repeater (with topics)**. Filter by course | CONFIRMED |
| CATALOG-005 | Level upgrade requests (`/admin/level-upgrade-requests`, hidden) | student\*, subscription\*, course\*, current level (read-only), **approve toggle**, **rejection reason\*** | CONFIRMED |
| CATALOG-006 | Qur'an chapters (`/admin/quran-chapters`) | simple name, Arabic name, complex name, revelation place, revelation order, verse count, start page, end page. **Header action: "مزامنة السور من API" (sync chapters from an external API)** | CONFIRMED |
| CATALOG-007 | Educational content (`/admin/educational-contents`) | "يمكنك رفع ملفات تعليميه للطلاب المشتركين في الكورسات" — per-course teaching files. Filter: course. `/create` returns 404 → creation is `PROBABLE` a modal | CONFIRMED (exists) / UNKNOWN (fields) |

### 4.6 Commerce — SUB

#### SUB-001 — Subscriptions (`/admin/subscriptions`)

* **List columns:** Account name · Teacher(s) · **Subscription progress (animated % bar)** · Payment status · Subscription date.
* **Status tabs:** النشطة · المنتهية · الموقوفة مؤقتا · الكل.
* **Filters:** deleted records, account type, teacher, subscription status, account ID, paid amount, payment method.
* **Header actions:** Add subscription · **Export to Excel** · **Subscription archive** (`/admin/expired-subscriptions`).
* **Row actions:** Edit · **التجديد (Renew)** · **المسح مع حفظ السجلات (delete keeping records — soft delete)** · **المسح النهائي (permanent delete)**.
* **Bulk actions:** Permanent delete · **Renew subscriptions** · Delete keeping records.
* **Form — 5 tabs:**
  * *معلومات الاشتراك*: subscription type\*, payment method\*, payment status\*, payment number\*, individual-subscription type\*, **start date\***, **duration\* (days)**, payment type\*, **subscription system\***, **auto-renew toggle**, **auto-invoice toggle**, then a **details repeater**: student\* (hint: *only students whose account type is individual appear here*), courses\*, and a nested repeater of **course\* + teacher\* + package\* + session duration (minutes)\*** — i.e. **one subscription can mix several courses, each with its own teacher and package**.
  * *الجدول الأسبوعي*: existing-schedule selector, student\*, schedule status, and a **timings repeater of up to 5+ rows: days\* (multi) · course\* · teacher\* · start time\* · end time**.
  * *ملخص الاشتراك*: current subscription mode\* (ساري / موقوف مؤقتًا / منتهي), **sessions attended\***, **extra sessions outside the package\***, **total sessions\***, total subscription hours, **paid amount\*** (hint: *this is the amount renewal will be based on; editable manually*), **original amount\*** (hint: *auto-computed from the sum of selected package prices*), **hourly price\***, **allowed suspension days\***, **weekly session count\***, preferred timings (free text), subscription notes.
  * *مستويات الطلاب*: per-student level + completed topics repeater.
  * *طلاب الاشتراك والحضور*: subscription roster and attendance.
* Evidence: CONFIRMED.

| ID | Feature | Detail | Evidence |
|---|---|---|---|
| SUB-002 | Subscription renewal | Row + bulk action. Opens a confirm dialog: *"تجديد الاشتراك — سيتم توجيهك إلى صفحة تجديد الاشتراك لإكمال العملية"* (you will be redirected to a renewal page). Buttons: متابعة / إلغاء | CONFIRMED (dialog) / **UNKNOWN — the renewal page URL and fields were not opened (would have mutated demo data)** |
| SUB-003 | Subscription archive | `/admin/expired-subscriptions`. Filters: account type, payment method, created-from, created-to. Bulk delete. Header: return to subscriptions | CONFIRMED |
| SUB-004 | Two-tier deletion | "delete keeping records" vs "permanent delete", plus a **"السجلات المحذوفة" (deleted records) filter** and `restore`/`force_delete` permission verbs → **soft deletes** | CONFIRMED (UI) / PROBABLE (soft-delete implementation) |
| SUB-005 | System codes | `/admin/system-codes`. Type\* (**activation / renewal / discount**), package\*, course\*, session count (auto from package), created date, **validity duration in days\***, status (unused / used / expired). Columns: type, code (e.g. `SYS-Y5OED`), expiry, created. Filters: type, status, discount type, used | CONFIRMED |

### 4.7 Scheduling & delivery — SCHED

#### SCHED-001 — Weekly schedules (`/admin/weekly-schedules`)

* **List columns:** Student · **Timings (system timezone)** rendered as `Day | from HH:MM to HH:MM | Course` lines · Subscription progress.
* **Status tabs:** النشطة · المتوقفة · المحذوفة · **ذات الاشتراك النشط** · **ذات الاشتراك المنتهي** · الكل.
* **Filters:** student, teacher, subscription type, group.
* **Header actions:** Add schedule · **توسيع التقويم (expand calendar)** · **تنزيل جميع الجداول (download all schedules)**.
* **Row actions:** Edit · **إلغاء تفعيل الجدول (deactivate)**.
* **Bulk actions:** restore selected · permanent delete · **تغيير جماعي (bulk change)** · deactivate selected · activate selected · **حذف مع نقل الحصص (delete and move its sessions)**.
* **Create form:** subscription type\* (radio) → student\* (**hint: "a schedule cannot be created for a student without an active subscription"**) → subscription\*.
* **Edit form sections:** subscription info (student, subscription details) · **المواعيد** repeater (days\*, course\*, start time\*, end time, teacher\*) · schedule status (current status, status) · **إعدادات جروب الإشعارات** (notify via group?, per-course group selection, WhatsApp group).
* Evidence: CONFIRMED.

#### SCHED-002 — Today's sessions board (`/admin/today-sessions`)

* Page title is dynamic: *"حصص اليوم الاساسية 🌿 {weekday} - {date} 🌿 {time}"*, with a banner *"كل التوقيتات التي يتم عرضها حسب توقيت 🌿Africa/Cairo 🌿"*.
* **Columns:** Student name · Account type · Teacher · Timings · Subscription progress · **الوقت المتبقي (time remaining)** · **حالة الجدولة (scheduling status)** · **حالة رابط الحصة (session-link status)**.
* Observed row values: scheduling status = **"لم يتم جدولتها"**, link status = **"لم يتم الجدولة"**, with a ❌ marker → slots exist but no session record has been materialised.
* **Actions:** **"جدولة جميع الحصص" (schedule all sessions)** and **"الجدولة المجمعة" (bulk scheduling)**.
* The bulk-scheduling modal (opened and inspected, **not submitted**): heading *"جدولة مجمعة للحصص"*, description *"سيتم إنشاء جدولة لجميع الحصص في الفترة المحددة. قد تستغرق العملية بعض الوقت."* ("this may take some time" → `PROBABLE` queued/long-running job), section **"تحديد فترة الجدولة"** with **تاريخ البداية** (pre-filled with today) and **تاريخ النهاية**, buttons تأكيد / إلغاء.
* Embedded widgets: sessions this month, sessions today, total sessions ever.
* Filters: teacher, student.
* Evidence: CONFIRMED.

#### SCHED-003 — Sessions (`/admin/sessions`)

* **List columns:** Student · Teacher · **Session type** · **Teacher attendance (state + timestamp)** · **Student attendance (state + timestamp)** · **Session status (+ scheduled datetime)**.
* **Status tabs:** الكل · أساسية · تعويض · مجدولة.
* **Filters:** student, teacher, session duration, from-time, to-time.
* **Header actions:** **النسخة المبسطة** (`/onlyadmin/sessions-lite`) · Create session · **Export to Excel** · **Session archive** (`/admin/expired-sessions`).
* **Row actions:** Edit · **سجل النشاط (activity log)** · **مراقبة (monitor → opens the Jitsi room)** · Delete · **تحويل إلى حضور (mark present)** · **تحويل إلى غياب (mark absent)** · **إلغاء الحصة (cancel session)**.
* **Bulk actions:** delete · mark present · mark absent · cancel.
* **Form — 5 tabs:**
  * *معلومات أساسية*: student\* (**hint: must be active, with a subscription and a weekly schedule**), subscription\*, weekly schedule\*, **day\*** (from the available schedule), teacher\* (**"teachers from the selected weekly schedule are shown"**), course\*, **default duration (minutes)\*** (**"auto-set from the subscription based on the selected course; editable"**), **actual duration (minutes)**.
  * *تفاصيل الحصة*: session creation date (**"used for salary calculation"**), session type (حصة عادية / حصة جماعية), **teacher in / teacher out / student in / student out times**, **teacher approval** (موافق/غير موافق/لم يتم التعيين, "set automatically on creation"), **created by** (المعلم/الطالب/الادارة), session link, **actual session timestamp** ("a fingerprint for each session; pressing the rocket icon sets it").
  * *الحضور والتقرير*: student attendance, teacher attendance, **session status\***, **report status\***, report body (**"sent by the teacher as notes to the administration and is not sent to…"** — truncated).
  * *الاشعارات*: **10 datetime fields** — early student reminder, student reminder, student attendance reminder, student absence notice, teacher reminder, early teacher reminder, teacher absence warning, teacher attendance reminder, teacher absence notice.
  * *التعويض*: **"هل هي حصة تعويضية؟"** toggle.
* Evidence: CONFIRMED.

#### SCHED-004 — Session activity log (`/admin/sessions/{id}/activities`)

Per-session audit trail titled *"سجل عمليات حصة"*, showing **actor · action (إنشاء/تحديث) · timestamp**, a field-level **الحقل / سابقاً / حالياً** diff table, and an **"أسترجاع" (restore/revert)** control per entry. CONFIRMED.

This screen exposed the **underlying session attribute names**, which are recorded here as the best available evidence of the data model (`CONFIRMED` as field names, `INFERRED` as column names):

`uid` (e.g. `S-I7T5J`) · `day` (e.g. **`friday_4`** — weekday plus an index) · `date` · `student` · `teacher` · `substitute teacher (المعلم البديل)` · `subscription` · `weekly schedule` · `course` · `group` · `supervisor_id` · `supervisor_attendance` · `is_session_opened_by_supervisor` · `session type` (`normal`) · `session status` (`scheduled`) · `student attendance` / `teacher attendance` (`not_set` → `present`) · `student excuse (عذر الطالب)` · `teacher approval` (`approved`) · `created by` (`admin`) · `is compensation` (`false`) · `compensation session date` · `default duration` / `actual duration` · `teacher in/out time` · `student in/out time` · `actual session timestamp` · `session link` · `meeting_id` · `meeting_password` · `report` · `report status` (`not_sent`) · `report_reminder_sent_at` · `notification_status` · `notification_group_id` · `notification_group_enabled` · the 9–10 reminder datetime fields · `session creation date`.

| ID | Feature | Detail | Evidence |
|---|---|---|---|
| SCHED-005 | Session archive | `/admin/expired-sessions`. **Columns: session ID, student, teacher, subject, session status, student attendance, teacher attendance, date, start time, end time, duration, compensation flag, archived date.** Filters add **"compensation sessions only"** and **"completed sessions only"**. Bulk: delete, **mark as completed**, **export data** | CONFIRMED |
| SCHED-006 | Simplified sessions | `/onlyadmin/sessions-lite` — "النسخة المبسطة للحصص" on a separate route prefix | CONFIRMED (exists) / UNKNOWN (contents) |
| SCHED-007 | Trial sessions | `/admin/trial-sessions`. Fields: student\*, auto-filled student data, **request source\*** (website / app / **API**), course\*, **number of students\***, **preferred teacher gender\*** (male/female/no preference), duration 1–180\*, session datetime\*, teacher (**with a "suggest" button for best match**), request date\*, status\* (scheduled/completed/cancelled), request status\*, session link\*, student attendance\*, teacher attendance\*, **"paid to teacher?" toggle**, **"how did you hear about us?"\*** (Facebook/Google/YouTube/web search/referral/other), "student rated the trial?" toggle, notes. Filters: student, course, teacher, teacher gender, status. Export to Excel | CONFIRMED |
| SCHED-008 | Extra sessions | `/admin/extra-sessions` (hidden). student\*, responsible teacher\*, datetime\*, duration\*, session link\*, student attendance, teacher attendance, session status, **"paid to teacher?" toggle**, notes | CONFIRMED |
| SCHED-009 | Session reports | `/admin/session-reports` (hidden). session\*, **behaviour & quality** and **participation quality** on a 5-point emoji scale (😊 ممتاز / 🙂 جيد / 😐 متوسط / 😕 دون المتوسط / 😞 ضعيف), notes, report status\* (sent / not sent) | CONFIRMED |
| SCHED-010 | Session reviews | `/admin/session-reviews` (hidden). List exists ("تقييمات الحصص", "إضافة تقييم"); `/create` 404 → `PROBABLE` modal | CONFIRMED (exists) / UNKNOWN (fields) |
| SCHED-011 | Homework | `/admin/homework` (hidden). 4 tabs: weekly-schedule data, homework content, **student response**, status. Fields: student\*, title\*, **type\* (file / text)**, file upload\*, student response, **student attachment**, **teacher comment**, status\* (incomplete / complete) | CONFIRMED |
| SCHED-012 | Teacher availability | `/admin/teacher-schedules` (hidden) — "مواعيد المعلمين", "إضافة مواعيد جديدة". `/create` 404 → `PROBABLE` modal | CONFIRMED (exists) / UNKNOWN (fields) |
| SCHED-013 | Teacher Zoom links | `/admin/teacher-zoom-links` (hidden). link type\*, teacher\*, link name\*, description, **meeting URL\***, **access type\*** | CONFIRMED |
| SCHED-014 | Jitsi classroom | `/class/{session_uid}`. Renders Session ID, Teacher, Student, Subject, Date, Time, Duration, Session Type, Status, Meeting ID, **and the current viewer's name/email/type**; info panel auto-hides after 10s. Uses `meet.jit.si/external_api.js` | CONFIRMED |

### 4.8 Student billing — BILL

| ID | Feature | Detail | Evidence |
|---|---|---|---|
| BILL-001 | Payment records (`/admin/payment-records`) | customer type\*, **transaction number** ("from the provider"), payment method\*, amount\*, currency\*, payment status\*, notes, payment date\*. Filters: payment method, customer type, payment status, currency. Header action → payment methods | CONFIRMED |
| BILL-002 | Manual payment methods (`/admin/payment-methods`, hidden) | **Per country**: country\*, "enable payment methods for this country" toggle, then a repeater of methods — name\*, active toggle, **logo image (200×200)**, **rich-text step-by-step instructions\***. Filters: country, status | CONFIRMED |
| BILL-003 | Monthly student invoices (`/admin/invoices`, hidden) | invoice number (**auto-generated if blank**), student\*, invoice type\*, invoice status\*, issue date\*, amount due\*, currency\*, **"service fee always enabled (5%)" toggle**, optional electronic payment method, transaction number, notes. Columns: invoice no., student, type, date, amount, status. Filters: student, from/to date. **Bulk action: "إرسال إشعار فاتورة غير مدفوعة" (send unpaid-invoice notification)** | CONFIRMED |
| BILL-004 | Payment links (`/admin/payment-links`) | 4 tabs. user type\* (**registered student / unregistered student**), **payment gateway\* (PayPal / Stripe)**, currency\*, amount\*, **"enable 5% service fee" toggle**, description. Filters: gateway, status, from/to date | CONFIRMED |
| BILL-005 | Donations (`/admin/donation-records`) | amount\*, payment method\*, transaction number, payment status\*. Observed row: `stripe`, `pi_3Tv0vRPaWhRY2Zyd3Xlwj0uI`, **مكتمل** → **live Stripe PaymentIntent IDs are stored** | CONFIRMED |
| BILL-006 | Expenses (`/admin/expenses`) | title\*, expense type\*, amount\*, currency\*, notes. Filters: type, currency. Feeds the dashboard net-profit card | CONFIRMED |
| BILL-007 | Student wallet | `الرصيد` on the student record — "used to pay invoices and subscriptions, and students can be compensated for sessions as balance in the system" | CONFIRMED |

### 4.9 Teacher payroll — PAY

| ID | Feature | Detail | Evidence |
|---|---|---|---|
| PAY-001 | Monthly salary board (`/admin/teacher-salaries`) | Title "رواتب المعلمين النشطين". Columns: **teacher · completed sessions · student-absence sessions · compensation sessions · total hours · salary (in the teacher's own currency)**. Default filter = current month (from / to). Row actions: **عرض (view)** · **إنشاء إيصال (create receipt)**. Bulk: **إنشاء إيصالات**. Header: **توقعات الرواتب (salary projections)** · Export to Excel. Explicit on-screen caveat: *"في الاصدار الحالي الرجاء مراجعه الرواتب بشكل يدوي للتاكد من عدد الحصص المدفوعه للمعلمين"* (**in the current version please verify salaries manually**) | CONFIRMED |
| PAY-002 | Salary computation inputs | The detail view exposes: from/to, **excused sessions (الحصص المعتذر عنها)**, **paid extra sessions**, **paid trial sessions**, **absence sessions**, **reports sent**, **reports not sent**, **total deductions**, **total incentives** | CONFIRMED |
| PAY-003 | Per-course hourly rates (`/admin/teacher-course-rates`, hidden) | teacher\* + **repeater of per-course rates**. Header actions: **"إضافة أجور لمعلم"** and **"إضافة أجور لمجموعة معلمين" (bulk rate assignment)** | CONFIRMED |
| PAY-004 | Deductions (`/admin/teacher-deductions`, hidden) | teacher\*, amount\*, currency\*, date\*, **reason\*** | CONFIRMED |
| PAY-005 | Incentives (`/admin/teacher-incentives`, hidden) | teacher\*, **type\* (fixed amount / percentage)**, value\*, currency\*, date\*, notes | CONFIRMED |
| PAY-006 | Salary invoices (`/admin/teacher-salary-invoices`, hidden) | teacher\*, receipt number\*, period start\*, period end\*, total hours, **status\* (pending / paid / cancelled)**, final salary\*, currency\*, **"teacher receipt-confirmation status"**, notes | CONFIRMED |
| PAY-007 | Withdrawal requests (`/admin/salary-withdrawal-requests`) | teacher\* (**hint: "choose a teacher with sufficient balance to withdraw"**), **amount in USD\***, request status\*, notes. Filters: status, teacher | CONFIRMED |
| PAY-008 | Report-submission deductions | System settings tab **"خصم التقارير"** + the `reports sent / not sent` payroll inputs → teachers are financially penalised for missing session reports | CONFIRMED (settings tab + inputs) / INFERRED (exact rule) |
| PAY-009 | Fixed-salary mode | Feature flag **"نظام راتب المعلم الثابت"** → an alternative to per-hour payroll | CONFIRMED (flag) / UNKNOWN (behaviour) |
| PAY-010 | Teacher balance | `الرصيد الحالي` on the teacher record; withdrawal requests draw against it | CONFIRMED |

### 4.10 Certificates — CERT

| ID | Feature | Detail | Evidence |
|---|---|---|---|
| CERT-001 | Certificate templates (`/admin/certificate-templates`) | title\*, short description, **template image (max 5 MB)** | CONFIRMED |
| CERT-002 | Issued certificates (`/admin/certificates`) | **type\*** (شهادة اتمام / شهادة تقدير / شهادة اعتزاز / **القوالب المخصصة**), student photo (max 2 MB), student\*, course\*, **completed session count (auto-filled from student + course)**, message from administration. Empty state: *"لا توجد الشهادات"* | CONFIRMED |
| CERT-003 | Certificate gating | Courses have a **"شهادة"** toggle ("allow students to obtain a certificate after completing the course"); playlists have **"شهادة معتمدة"**; feature flag **"نظام الشهادات الموثق"** (verified certificates) | CONFIRMED |

### 4.11 Communications — COMM

| ID | Feature | Detail | Evidence |
|---|---|---|---|
| COMM-001 | Internal messaging (`/admin/conversations`) | *"يمكن عرض جميع الرسائل المُرسلة عبر النظام، وتعديلها، وحذفها"*. Filters: **sender type / receiver type = طالب · معلم · مشرف · أدمن · الجميع**, created from/to. Columns include **المرفقات (attachments)** and **عدد القراء (read count)**. Bulk delete | CONFIRMED |
| COMM-002 | Chat groups (`/admin/conversation-groups`) | name\*, group image, **participants repeater**. Filters: created from/to | CONFIRMED |
| COMM-003 | Notification records (`/admin/notifications`) | **target\*** (مدير النظام / معلمين متعددين / طلاب متعددين / طالب محدد / معلم محدد / ولي أمر محدد / كل الطلاب / كل المعلمين / كل أولياء الأمور / **مجموعة**), message\*, **channels\* (checkbox list)**, **status (قيد الانتظار / مرسل / فشل — read-only)**, read flag (read-only). Columns: target type, target name, message, sent date. Row actions: view, delete. Filter: target type | CONFIRMED |
| COMM-004 | Automated notification templates | System settings → "التنبيهات" and "تفضيلات الاشعارات" tabs define **bilingual (ar + en) templates with individual on/off state** for: session reminder · **early reminder (2 hours before)** · lateness alert · student absence notice · teacher absence alert · subscription renewal · subscription nearing expiry · session started 5 minutes ago (teacher) · session ended 5 minutes ago (teacher) · subscription offers · student schedule update · teacher schedule update · trial sessions · **teacher report-submission reminder** | CONFIRMED |
| COMM-005 | WhatsApp routing | System settings → WhatsApp: admin WhatsApp number + a **repeater of group name/ID pairs**; teachers have a **"customise notification group"** toggle; weekly schedules have **per-course group selection** | CONFIRMED |
| COMM-006 | Per-user notification preferences | 7 toggles on the student record; notification toggles on teacher records | CONFIRMED |
| COMM-007 | Per-session notification scheduling | 10 datetime fields per session record plus `notification_status`, `report_reminder_sent_at` → each reminder is individually scheduled and stamped | CONFIRMED |
| COMM-008 | In-app notification stream | Filament notifications JS loaded; sidebar "الإشعارات (التلقائية)" | CONFIRMED |

### 4.12 Marketing & content — CNT

| ID | Feature | Detail | Evidence |
|---|---|---|---|
| CNT-001 | Articles (`/admin/articles`) | 5 tabs (basic / content / attachments / SEO / schema). cover image, title\*, category\*, slug\*, **short description\* (AI)**, publish date\*, published toggle, **view count**, **reaction count**, **content (AI generate/replace)**, attachments, **SEO title (AI)**, **SEO description (AI)**, **keywords (AI suggest)**, schema codes repeater. Filter: status | CONFIRMED |
| CNT-002 | Article categories (`/admin/article-categories`, hidden) | icon, name\*, slug\*, description (**AI**) | CONFIRMED |
| CNT-003 | Video library (`/admin/videos`) | 3 tabs. title\*, description, **video file\* (MP4/MOV, max 5 GB)**, **cover image\* (JPG/PNG/WEBP, 16:9)**, SEO title (**max 60 chars**), SEO description (**max 160 chars**), keywords (Enter to add), publish toggle, view count, reaction count | CONFIRMED |
| CNT-004 | FAQs (`/admin/faqs`) | 3 tabs: Arabic content, English content, settings. question(ar)\*, answer(ar)\* (rich text), Question(en), Answer(en)\* (rich text), active toggle, **sort order**. Filter: active only | CONFIRMED |
| CNT-005 | Student testimonials (`/admin/student-reviews`) | student name\*, **star count\*** (1–5 rendered as ⭐), **review type\* (نص / صوت / فيديو)** | CONFIRMED |
| CNT-006 | Site pages (`/admin/site-pages`, hidden) | page name\*, **page key\***, page title, meta title, meta description, keywords. Editing uses the **GrapesJS drag-and-drop builder** (asset evidence) | CONFIRMED (fields) / PROBABLE (builder binding) |
| CNT-007 | Advertisements (`/admin/advertisements`, hidden) | **banner\***, type\* (**عام / خصم**), title\*, body\*, **expiry date\*** | CONFIRMED |
| CNT-008 | URL redirects (`/admin/redirects`, hidden) | "إعادة توجيه الروابط"; `/create` 404 → `PROBABLE` modal. Feature flag "نظام اعاده توجيه الروابط" | CONFIRMED (exists) / UNKNOWN (fields) |
| CNT-009 | Site settings (`/admin/site-settings`) | 4 tabs — **Basic**: site name (en + ar)\*, **primary colour\***, logo, favicon, hero image, social share image, intro video, **site status\***, **custom Header code**, **custom ads code**, **site schema**. **Content**: about, privacy policy, terms & conditions, vision, mission, packages-page blurb, footer blurb. **Social**: Facebook, X, WhatsApp, phone, Gmail, public-service email, info email, Instagram, Telegram, SoundCloud, YouTube, LinkedIn, TikTok, Snapchat — **each with its own enable toggle**. **SEO**: address, site description, keywords | CONFIRMED |

### 4.13 Recorded courses — RC

| ID | Feature | Detail | Evidence |
|---|---|---|---|
| RC-001 | Playlists (`/admin/play-lists`) | 5 tabs. thumbnail\* (400×225), **intro video (max 100 MB)**, title\*, slug\*, description\*, **code\***, **total hours\***, **lesson count\***, **content language\*** (Arabic/English/Urdu/Turkish/French/Spanish), **price**, **discount**, content (**AI**), **terms & conditions\***, publish toggle, **accredited certificate toggle**, **"show in app only" toggle**. Filters: publish status, language, has discount | CONFIRMED |
| RC-002 | Playlist videos (`/admin/playlist-videos`) | thumbnail\*, playlist\*, code\*, title\*, slug\*, **video type\* (link / file / live stream)**, video URL\*, **duration\* (HH:MM:SS)**, **order\***, description, **status\* (draft / published / hidden)**, **downloadable toggle**. Filters: playlist, status, downloadable | CONFIRMED |
| RC-003 | RC subscriptions (`/admin/rc-subscriptions`, hidden) | 2 tabs. playlist\*, student\*, amount paid\*, **payment method\* (PayPal / Stripe / activation code)**, transaction number\*, **"certificate obtained" toggle**, **watched videos (searchable multi-select)**, notes | CONFIRMED |
| RC-004 | RC comments (`/admin/rc-comments`, hidden) | "التعليقات" | CONFIRMED (exists) / UNKNOWN (fields) |
| RC-005 | RC reviews (`/admin/rc-reviews`, hidden) | "التقييمات" | CONFIRMED (exists) / UNKNOWN (fields) |

### 4.14 Consultations — CONS

| ID | Feature | Detail | Evidence |
|---|---|---|---|
| CONS-001 | Consultation products (`/admin/consultations`) | 3 tabs. cover image, name\*, description\* (rich text), **price in USD\***, **duration (minutes)\***, **booking validity in days\*** ("must be used within e.g. 7 days after payment"), **participant count\***, **delivery mode\*** (video call / live chat / email), status\* (available / archived), enabled toggle, **featured toggle**, **reschedulable toggle**, **5% fee toggle**, **responsible teachers\* (multi)**. Filters: delivery mode, featured, status | CONFIRMED |
| CONS-002 | Consultation requests (`/admin/consultation-requests`) | 4 sections. student name\*, email\*, WhatsApp\*, request ID, consultation\*, **teacher linked to the consultation\***, session link, **session status\*** (scheduled / completed / absent), student timezone, **session datetime (system timezone) — "select a teacher first to see available slots"**, student attendance\*, teacher attendance\*, **request status\*** (قيد المراجعة / تم التأكيد وتأكيد الموعد / مكتمل / ملغي / **تم طلب اعاده الجدولة**), payment ID, amount paid, **payment gateway** (PayPal / Stripe / Manual / **Zelle / InstaPay / Telda / PayMob**). Filters: consultation, teacher, session status, student attendance, teacher attendance, gateway, from/to date. Header actions: **تصدير تقرير** and **تصدير هوامش ربح المعلمين (export teacher profit margins)** | CONFIRMED |
| CONS-003 | Consultation reviews / schedules | Permission groups `consultation::review`, `consultation::schedule` exist | CONFIRMED (permissions) / UNKNOWN (UI) |
| CONS-004 | Teacher opt-in | Teacher record has **"هل يقدم استشارات"** toggle, and consultations settings live in the teacher's Settings tab | CONFIRMED |

### 4.15 Inbound / leads — LEAD

| ID | Feature | Detail | Evidence |
|---|---|---|---|
| LEAD-001 | Contact requests (`/admin/contact-requests`) | person type\* ("أتواصل معكم بصفتي"), name\*, email\*, phone\*, country\*, **"do you have WhatsApp?" toggle**, message\*. Filters: language, has WhatsApp | CONFIRMED |
| LEAD-002 | Trial session requests | See SCHED-007 — captures **request source** (website/app/API) and **attribution ("how did you hear about us")** | CONFIRMED |
| LEAD-003 | Request centre | `request::center` permission group exists with **0 verbs granted** and `/admin/request-center` 404s. A notification observed on the demo reads *"طلب جديد في مركز الطلبات المع…"* → the subsystem exists and emits notifications but its UI is unreachable in this build | CONFIRMED (evidence) / INFERRED (disabled feature) |

### 4.16 Reporting & export — EXP

| ID | Feature | Detail | Evidence |
|---|---|---|---|
| EXP-001 | Monthly student reports (`/admin/student-reports`) | Reached from Students → "التقارير الشهرية". Columns: student name, student report, generation date. Create form: **select student\*** → **subscription details** and **session details** auto-populate ("الرجاء اختيار طالب أولاً" until a student is chosen) → report body with a **"توليد التقرير" (generate report)** action. Save options: Add / **Add & start adding more** / Cancel | CONFIRMED — AI-assisted report generation |
| EXP-002 | Excel exports | Subscriptions · Sessions · Expired sessions · Trial sessions · Teacher salaries · Consultation requests report · **Teacher profit margins** | CONFIRMED (actions exist) / UNKNOWN (file format details, columns) |
| EXP-003 | Student data export | Students header action "تصدير البيانات" | CONFIRMED (action) / UNKNOWN (format, fields) |
| EXP-004 | Schedule download | Weekly schedules header action "تنزيل جميع الجداول" | CONFIRMED (action) / UNKNOWN (format) |
| EXP-005 | Salary projections | Teacher salaries header action "توقعات الرواتب" — forward-looking payroll estimate | CONFIRMED (action) / UNKNOWN (screen; the guessed routes 404) |
| EXP-006 | Calendar expansion | Weekly schedules header action "توسيع التقويم" | CONFIRMED (action) / UNKNOWN (view) |

### 4.17 Platform — SYS

| ID | Feature | Detail | Evidence |
|---|---|---|---|
| SYS-001 | System settings (`/admin/system-settings`) | **132 fields across 9 top-level tabs**: إعدادات عامة · خصم التقارير · بوابات الدفع · التنبيهات · الاشتراكات والعروض · تفضيلات الاشعارات · **إعدادات المطور** · الخدمات الخارجية · (plus nested per-audience and per-template sub-tabs). General: **max postponement limit\***, system primary language\*, admin email\*, admin WhatsApp\*, system timezone\* | CONFIRMED |
| SYS-002 | **Feature flags (34)** | `نظام المستويات` · `نظام رفع الملفات` · `نظام اعاده توجيه الروابط` · `المساعد الذكي` (AI assistant) · `روابط الدفع` · `نظام الشهادات الموثق` · `نظام الحوافز والخصومات` · `نظام الاشراف العام` (supervision) · `نظام حسابات العائلات` · `نظام اولياء الامور` · `نظام الحصص المجانيه للمشتركين` · `نظام الواجبات` · `نظام تقارير الحصص` · `نظام المحادثات الداخلية` · `نظام الكورسات المسجله` · `نظام المقالات` · `نظام الاسعار المخصص حسب الدولة` · `نظام تصدير اكسيل` · `نظام الاستشارات` · `نظام أولوفيكس الداخلي` · `نظام المجموعات` · `نظام الارصده` · `نظام التبرع` · `نظام الاشعارات التلقائي` · `نظام العقود` · `نظام ارشيف الاشتراكات` · `نظام ارشيف الحصص` · `نظام الفواتير والايصالات` · `نظام خصومات التقارير` · `نظام راتب المعلم الثابت` · `نظام انتظار تسجيل الطالب` (student registration waiting list) · `نظام سجلات ايصالات الدفع` · `نظام زووم API` · `نظام روابط عامة` | CONFIRMED |
| SYS-003 | Payment gateway switches | PayPal · Stripe · **الدفع المحلي (local payment)** · **كود التفعيل (activation code)** · **الرسوم المطلوبة (required fees)** | CONFIRMED |
| SYS-004 | System status (`/admin/system-status`) | Version/license/env panel + actions: **مسح الكاش (clear cache)** · **ضبط الاشتراكات يدوياً (manually reconcile subscriptions)** · **إشعار المعلمين بالتقييم الشهري (notify teachers of the monthly review)** · a support link | CONFIRMED |
| SYS-005 | Themes (`/admin/themes`) | Primary colour + templates: Default, Dracula, Nord, Sunset | CONFIRMED |
| SYS-006 | File uploads (`/admin/file-uploads`) | "ملفات" library with "إضافة ملف". Gated by the `نظام رفع الملفات` flag | CONFIRMED (exists) / UNKNOWN (fields) |
| SYS-007 | Quick translate (`/admin/quick-translate`) | **HTTP 403 to `super_admin`**. Related permission `page_QuickTranslate` and resource `language::line` (ترجمات) exist; `/admin/language-lines` is 404 | CONFIRMED (403) / UNKNOWN (cause) |
| SYS-008 | Activity logging | Confirmed for sessions (`/admin/sessions/{id}/activities`) with field diffs and revert | CONFIRMED for sessions / UNKNOWN whether other entities have it |

---

## 5. User Roles & Permissions

### 5.1 Actor types observed

| Actor | Where it lives | Evidence |
|---|---|---|
| **Admin user** (`users` table, roles via Shield) | `/admin` | CONFIRMED |
| **Supervisor (مشرف)** | Appears as a **messaging participant type**, as `supervisor_id` / `supervisor_attendance` / `is_session_opened_by_supervisor` on sessions, and as the `نظام الاشراف العام` feature flag. The demo's `Supervisor` *role* is an admin-panel role. **No `/supervisor` panel exists (404).** | CONFIRMED (references) / UNKNOWN (how a supervisor signs in) |
| **Teacher** (`teachers`) | `/teacher` panel | CONFIRMED |
| **Student** (`students`) | `/student` custom app | CONFIRMED |
| **Parent** (`parents`) | `/parent` panel | CONFIRMED |

Teachers, students and parents are **separate entities with their own credentials**, not rows in the admin `users` table — each has its own password field on its own admin form and its own login panel.

### 5.2 Roles present on the demo

| Role | Guard | Permissions | Composition | Evidence |
|---|---|---|---|---|
| `super_admin` | web | **847** | Everything except `request::center` (0) and the 6 verbs that don't exist for `role` | CONFIRMED |
| `Supervisor` | web | **24** | Exactly two groups at 12 verbs each: **`advertisement`** and **`trial::session`** | CONFIRMED (read from the role's Livewire state) |

`Supervisor` on the demo is clearly a **sample role**, not a product-defined persona — the real product ships a permission matrix that an operator composes themselves.

### 5.3 Permission matrix (admin panel)

Because roles are fully composable, the meaningful matrix is **verb × resource**, not role × feature. The system's capability grid is:

| Verb (key) | Arabic | Available on |
|---|---|---|
| `view` | عرض | all 71 resources except where noted |
| `view_any` | عرض الكل | all 71 |
| `create` | إضافة | all 71 |
| `update` | تعديل | all 71 |
| `restore` | استرجاع | 70 (not `role`) |
| `restore_any` | استرجاع الكل | 70 |
| `replicate` | استنساخ | 70 |
| `reorder` | إعادة ترتيب | 70 |
| `delete` | حذف | all 71 |
| `delete_any` | حذف الكل | all 71 |
| `force_delete` | إجبار الحذف | 70 |
| `force_delete_any` | إجبار حذف أي | 70 |

Page-level: `page_QuickTranslate`, `page_Themes`, `page_TwoFactor`, `page_LoginTwoFactor`, `page_SystemStatus`, `page_OTPVerify`, `page_TwoFactorySetup`.
Widget-level: `widget_StudentsStatsWidget`, `widget_SubscriptionsStatsWidget`, `widget_RevenueStatsWidget`, `widget_SessionsStatsWidget`, `widget_StudentsOverviewWidget`, `widget_GreeterWidget`.

### 5.4 Cross-panel access (evidence-limited)

| Capability | Admin | Teacher | Parent | Student | Basis |
|---|:--:|:--:|:--:|:--:|---|
| Admin console | ✓ | | | | CONFIRMED |
| Own panel login | ✓ | ✓ | ✓ | ✓ | CONFIRMED |
| Self-service password reset | ? | ✗ | ✗ | ✓ | CONFIRMED (teacher/parent 404; student OTP flow) |
| Self-registration | ✗ | ✗ | ✗ | ✓ | CONFIRMED |
| Social login (Google) | ✗ | ? | ? | ✓ | CONFIRMED for student |
| Be impersonated by admin | — | ✓ | ✗ | ✓ | CONFIRMED (quick-login exists only on students & teachers lists) |
| Create sessions | ✓ | ✓ | ✗ | ✓ | INFERRED from the session field `تم انشاء الحصة بواسطة` = المعلم / الطالب / الادارة |
| Submit session reports | ✓ | ✓ | | | INFERRED from "this report is sent by the teacher" |
| Appear in chat | ✓ | ✓ | ✗ | ✓ | CONFIRMED from sender/receiver type filters (student, teacher, supervisor, admin) — **parents are not listed** |
| Receive notifications | ✓ | ✓ | ✓ | ✓ | CONFIRMED from notification target options |

> Everything in the Teacher, Parent and Student panels beyond their login screens is **UNKNOWN** — no credentials for those panels were available and the audit did not use impersonation (it would have mutated demo state and the risk of side effects was not justified). This is the single largest coverage gap.

---

## 6. User Flows

### FLOW-001 — Student acquisition (Enhanced registration) — `PROBABLE`

```
Trigger: visitor opens /student/proregister
Actor: prospective student / parent
Preconditions: public site enabled
  ↓
Choose age group
 ├── Minor  → "Family account for multiple students"  → account_type = family
 └── Adult  → "Individual account for one student"    → account_type = individual
  ↓
Browser auto-detects timezone (shown back as "Detected Timezone: …")
  ↓
Enter name*, email*, date of birth*, phone* (split into country code + number),
gender*, password*
  ↓
Enter scheduling preferences: desired start date, total hours per week,
preferred class days (7 checkboxes), intro-call day + time, teacher preference
  ↓
Submit
 ├── Success → Student record created
 │             (PROBABLE status = "قيد الانتظار" — a "student registration waiting
 │              list" feature flag exists)  →  admin notified
 │              (a notification "A new regi…" to مدير النظام was observed)
 │              →  student receives a welcome notification
 │                 (observed: "مرحباً Abdelwhab Anwr! 👋 تم…")
 └── Failure → UNKNOWN (validation messages not observed)
```

Side effects observed in the notification log: **admin notification on new registration** and **student welcome notification**, both `CONFIRMED` as records.

### FLOW-002 — Trial session lifecycle — `CONFIRMED (structure)`

```
Trigger: trial request (source = website | app | API) or admin creates one
  ↓
Capture: student, course, number of students, preferred teacher gender,
duration (1–180 min), desired datetime, attribution ("how did you hear about us")
  ↓
Assign teacher  ── admin may use the "suggest" button (best match)
  ↓
Session link issued;  status = مجدولة
  ↓
Session occurs → record student attendance + teacher attendance
  ↓
 ├── status = مكتملة  → optional "student rated the trial" flag
 │                    → "paid to teacher?" toggle feeds payroll
 │                    → conversion to a paid Subscription (INFERRED)
 └── status = ملغية
```

### FLOW-003 — Subscription creation — `CONFIRMED`

```
Trigger: admin → Subscriptions → "إضافة اشتراك جديد" (or Quick Create)
Preconditions: student exists and is active; packages, courses and teachers exist
  ↓
Tab 1  Subscription info
  · subscription type*, payment method*, payment status*, payment number*
  · individual-subscription type*, start date*, duration (days)*, payment type*,
    subscription system*, auto-renew, auto-invoice
  · details repeater: student*  →  courses*  →  per-course rows of
    {course*, teacher*, package*, session duration (min)*}
  ↓
Tab 2  Weekly schedule
  · link an existing schedule OR define timings:
    {days* (multi), course*, teacher*, start time*, end time} × N
  ↓
Tab 3  Summary  (largely auto-computed, manually overridable)
  · total sessions*  ← from selected packages
  · original amount*  ← sum of package prices
  · paid amount*      ← the figure renewal will use
  · hourly price*, allowed suspension days*, weekly session count*
  · sessions attended*, extra sessions outside package*
  ↓
Tab 4  Student levels  ·  Tab 5  Roster & attendance
  ↓
Save → subscription active; weekly schedule(s) now drive session generation
```

### FLOW-004 — Weekly schedule → session materialisation — `CONFIRMED`

```
Trigger: admin opens /admin/today-sessions (or acts on any date range)
Preconditions: active subscription + active weekly schedule
  ↓
Board lists every slot due today with
  scheduling status = "لم يتم جدولتها"  and  link status = "لم يتم الجدولة" (❌)
  ↓
Decision
 ├── "جدولة جميع الحصص"  → generate today's sessions
 └── "الجدولة المجمعة"   → modal "جدولة مجمعة للحصص"
                            · start date (defaults to today) + end date
                            · warning: "قد تستغرق العملية بعض الوقت"
                            · confirm / cancel
  ↓
For each slot: create a Session with
  uid (S-XXXXX), day (e.g. friday_4), date, student, teacher, course,
  subscription, weekly_schedule, default duration (from the subscription/course),
  session link → https://…/class/{uid}, meeting_id, meeting_password,
  teacher approval = approved, attendance = not_set, status = scheduled,
  report status = not_sent, created_by = admin,
  and the 10 reminder timestamps
  ↓
Board flips those rows to scheduled; session link becomes available
```

### FLOW-005 — Session delivery & attendance — `CONFIRMED (structure)`

```
Trigger: scheduled session time arrives
  ↓
Reminders fire on their scheduled timestamps
  (early reminder → reminder → attendance reminder → absence notice,
   independently for student and teacher)
  ↓
Participants open /class/{uid}  → Jitsi room (meeting_id / meeting_password)
  ↓
System stamps teacher_in / student_in ( … _out on leaving)
  ↓
Admin (or teacher) sets attendance
 ├── تحويل إلى حضور → attendance = present (+ timestamp)
 ├── تحويل إلى غياب → attendance = absent
 └── إلغاء الحصة    → status = cancelled
  ↓
Teacher submits a session report (behaviour + participation on a 5-point scale,
notes) → report status = sent
 └── if not submitted → report_reminder_sent_at set; counts toward
     "التقارير الغير مرسلة" in payroll → report deduction
  ↓
Side effects:
  · subscription "sessions attended" advances → progress %
  · session becomes payroll input for the teacher
  · every change appended to the session activity log (field-level, revertible)
  · absence may trigger a compensation session (is_compensation, compensation date)
```

### FLOW-006 — Monthly teacher payroll — `CONFIRMED (structure)` / `INFERRED (arithmetic)`

```
Trigger: admin opens /admin/teacher-salaries (defaults to the current month)
  ↓
For each active teacher the system aggregates, for the from→to window:
  completed sessions · student-absence sessions · compensation sessions
  · excused sessions · paid extra sessions · paid trial sessions
  · reports sent / not sent
  ↓
→ total hours  →  × per-course hourly rate (teacher_course_rate)
  ↓
  + incentives (fixed or %)   − deductions   − report deductions
  ↓
= salary, expressed in the teacher's own currency (EGP / USD observed)
  ↓
Decision
 ├── "إنشاء إيصال" (single) or bulk "إنشاء إيصالات"
 │     → teacher_salary_invoice {receipt no., period start/end, total hours,
 │        final salary, currency, status = pending|paid|cancelled,
 │        teacher receipt-confirmation status, notes}
 └── "توقعات الرواتب" → forward projection (screen not reached)
  ↓
Teacher requests a withdrawal (amount in USD) against their balance
  → salary_withdrawal_request {status, notes}
  ↓
On-screen caveat: the current version asks operators to verify salaries manually.
```

### FLOW-007 — Student billing — `CONFIRMED (structure)`

```
Subscription created (auto-invoice toggle) ── or ── admin creates an invoice
  ↓
Invoice {number (auto if blank), student, type, status, issue date,
         amount due, currency, 5% service fee (always on), notes}
  ↓
Payment route
 ├── Online: payment link (PayPal | Stripe, optional +5% fee)
 │     → payment_record {transaction number from provider, amount, currency,
 │        status}  (Stripe PaymentIntent IDs observed stored verbatim)
 ├── Manual: country-specific payment method with rich-text instructions
 │     → admin records the payment manually
 └── Wallet: student balance
  ↓
 ├── Paid      → revenue this month ↑ → dashboard net profit
 └── Unpaid    → bulk action "إرسال إشعار فاتورة غير مدفوعة"
```

### FLOW-008 — Subscription renewal — `PARTIAL`

```
Trigger: row action "التجديد" or bulk "تجديد الاشتراكات",
         or automatically when "تجديد تلقائي" is on (INFERRED)
  ↓
Confirm dialog: "سيتم توجيهك إلى صفحة تجديد الاشتراك لإكمال العملية"
  ↓
[UNKNOWN] dedicated renewal page — URL and fields not determined
  ↓
Renewal is priced from the subscription's "المبلغ المدفوع" field
  ↓
Prior cycle presumably moves to /admin/expired-subscriptions (archive)
```

### FLOW-009 — Consultation booking — `CONFIRMED (structure)`

```
Consultation product published (price USD, duration, validity days,
participants, delivery mode, responsible teachers)
  ↓
Request created {student name, email, WhatsApp, consultation, teacher}
  ↓
Select teacher → available slots appear → pick datetime (system timezone)
  ↓
Payment {gateway: PayPal|Stripe|Manual|Zelle|InstaPay|Telda|PayMob,
         payment ID, amount}
  ↓
Request status: قيد المراجعة → تم التأكيد وتأكيد الموعد
  ↓
Session link issued → session status scheduled → attendance recorded both sides
  ↓
 ├── مكتمل   → feeds "تصدير هوامش ربح المعلمين" (teacher profit margin)
 ├── ملغي
 └── تم طلب اعاده الجدولة  (only if the product is "reschedulable")
```

### FLOW-010 — Level progression — `CONFIRMED (structure)`

```
Course ──(optionally linked to the Qur'an curriculum)── Levels → sub-levels → topics
  ↓
Subscription tab "مستويات الطلاب" tracks current level + completed topics
  ↓
Level upgrade request {student, subscription, course, current level}
  ↓
 ├── approve toggle ON  → level raised
 └── approve OFF        → rejection reason* required
```

### FLOW-011 — Certificate issuance — `CONFIRMED (structure)`

```
Course has "شهادة" enabled  (or a playlist has "شهادة معتمدة")
  ↓
Admin → Certificates → Add
  ↓
Pick type (completion | appreciation | pride | custom template)
  ↓
Pick student* + course*  →  completed session count auto-fills
  ↓
Optional student photo + message from administration
  ↓
Certificate rendered from the selected certificate template image
```

### FLOW-012 — Student password recovery — `CONFIRMED`

```
/student/password/forgot
  ↓
Choose identifier type: Email | Phone number | Student ID (UID)
  ↓
Enter identifier → "Send Verification Code"
  ↓
Decision: multiple accounts share this phone?
 ├── yes → "Select Account" step
 └── no  → continue
  ↓
Enter 4-digit OTP  →  verify
  ↓
New password + confirmation  →  reset
```

### FLOW-013 — Notification dispatch — `CONFIRMED (structure)`

```
Trigger: event (session reminder, absence, renewal due, new registration,
         report reminder, monthly review, …) OR manual notification
  ↓
Resolve target: admin | specific/multiple/all students | teachers | parents | group
  ↓
Resolve channels (checkbox list on the notification form)
  ↓
Respect the recipient's per-user notification preference toggles
  ↓
Render the bilingual template (ar / en) from system settings
  ↓
Route: in-app record  and/or  email  and/or  WhatsApp
  (global group, or a teacher's custom group, or a schedule's per-course group)
  ↓
status: قيد الانتظار → مرسل | فشل      (+ read flag, read count for chat)
```

---

## 7. Domain Entities

Domain-level only — **no database schema is asserted**. Attributes listed are those observed in forms, tables or the activity log.

### 7.1 Core entity graph

```text
Student ──< StudentParent >── Parent
  │  ├── belongs to FamilyAccount (when account_type = family)
  │  ├── belongs to Group
  │  ├── has Wallet balance, XP points, Tags
  │  └── has many Subscriptions
  │
Subscription ──< SubscriptionDetail >── { Course, Teacher, Package }
  │  ├── has many WeeklySchedule
  │  ├── has many Session
  │  ├── has StudentLevel progress
  │  ├── has Invoice(s) / PaymentRecord(s)
  │  └── archives to ExpiredSubscription
  │
WeeklySchedule ──< ScheduleSlot { days, course, teacher, start, end } >
  │  └── materialises into Session
  │
Session ── Student, Teacher (+ SubstituteTeacher), Course, Subscription,
  │        WeeklySchedule, Group, Supervisor
  │  ├── SessionReport   (behaviour, participation, notes, status)
  │  ├── SessionReview
  │  ├── Homework
  │  ├── ActivityLog entries (field-level, revertible)
  │  └── archives to ExpiredSession
  │
Teacher
  ├── Agreement (employment contract)
  ├── TeacherCourseRate (per-course hourly rate)
  ├── TeacherDeduction · TeacherIncentive
  ├── TeacherSalary (monthly computation) → TeacherSalaryInvoice
  ├── SalaryWithdrawalRequest
  ├── TeacherSchedule (availability)
  └── TeacherZoomLink
```

### 7.2 Entity catalogue

| Entity | Purpose | Key attributes observed | Lifecycle / states | Evidence |
|---|---|---|---|---|
| **Student** | Customer & learner | uid `STD-#####`, photo, name, DOB, gender, account_type (individual/family), age_group, registration date, tags, email, alias email, phone, postal code, country, nationality, timezone, device type, IP, preferred language, status, password, 7 notification prefs, balance, XP | active · pending · trial · in-progress · paused · inactive | CONFIRMED |
| **FamilyAccount** | Groups sibling students under one payer | name, linked accounts (family-type students), **payer account**, notes, active | active / inactive | CONFIRMED |
| **Group** | Cohort of students | name, linked students, notes, active | active / inactive | CONFIRMED |
| **Parent** | Guardian | name, email, phone, on-WhatsApp, children, registration date, language, timezone, password (min 8), active | active / inactive | CONFIRMED |
| **Teacher** | Instructor & payee | uid `TCH-#####`, photo, name, gender, DOB, address, identifier (auto), language, tags, email, phone ×2, timezone, payout method + details, balance, note, bio, CV, skills, media, offers-consultations, enabled, show-on-homepage, rating 1–5, dashboard style, custom notification group, password | enabled / disabled; rating scale | CONFIRMED |
| **Agreement** | Employment contract | teacher, details (AI-draftable), contract file | — | CONFIRMED |
| **User** | Admin/staff account | name, email, password, roles | — | CONFIRMED |
| **Role** | Permission bundle | title, guard, permissions | — | CONFIRMED |
| **Course** | Subject offering | banner/icon/media, name, slug, category, teachers, short description, active, visible, requirements, lesson count, certificate flag, Qur'an-linked flag, language, overview, SEO title/description/keywords, schema codes | active/inactive; visible/hidden | CONFIRMED |
| **CourseCategory** | Course taxonomy | icon, name, slug, description | — | CONFIRMED |
| **Package** | Sellable plan | image, name, description, features, weekly lessons, type (individual/group), session duration, duration + unit, max days, **freeze days allowed**, hourly price, discount %, price, currency, active, visible, popular, **per-country prices** | active/inactive; visible/hidden | CONFIRMED |
| **Subscription** | Commercial agreement | type, payment method/status/number, individual type, start date, duration days, payment type, subscription system, auto-renew, auto-invoice, details (student → courses → {course, teacher, package, duration}), mode, sessions attended, extra sessions, total sessions, total hours, paid amount, original amount, hourly price, suspension days allowed, weekly sessions, preferred timings, notes | ساري · موقوف مؤقتًا · منتهي (+ soft-deleted, archived) | CONFIRMED |
| **WeeklySchedule** | Recurring timetable | student, subscription details, slots {days, course, start, end, teacher}, status, notification-group settings | active · stopped · deleted | CONFIRMED |
| **Session** | One delivered lesson | see §4.7 SCHED-004 field list (~50 attributes) | scheduled · completed · cancelled (+ archived); attendance not_set/present/absent; report not_sent/sent | CONFIRMED |
| **ExtraSession** | Out-of-package lesson | student, teacher, datetime, duration, link, attendance ×2, status, paid-to-teacher, notes | — | CONFIRMED |
| **TrialSession** | Pre-sale lesson | student, source, course, student count, teacher gender preference, duration, datetime, teacher, request date, status, request status, link, attendance ×2, paid-to-teacher, attribution, rated flag, notes | scheduled · completed · cancelled | CONFIRMED |
| **SessionReport** | Teacher's lesson write-up | session, behaviour rating, participation rating, notes, status | sent / not sent | CONFIRMED |
| **Homework** | Assignment | student, title, type (file/text), file, student response, student attachment, teacher comment, status | incomplete / complete | CONFIRMED |
| **Level / SubLevel / Topic** | Curriculum ladder | course, level name, sub-levels with topics | — | CONFIRMED |
| **LevelUpgradeRequest** | Promotion decision | student, subscription, course, current level, approved, rejection reason | approved / rejected | CONFIRMED |
| **QuranChapter** | Qur'an reference data | simple/Arabic/complex name, revelation place & order, verse count, start & end page | synced from API | CONFIRMED |
| **EducationalContent** | Per-course learning files | course + files | — | CONFIRMED (existence) |
| **Certificate / CertificateTemplate** | Achievement artefacts | type, student, course, completed sessions, photo, admin message / template title, description, image | — | CONFIRMED |
| **Invoice** | Student monthly bill | number, student, type, status, issue date, amount due, currency, 5% fee, payment method, transaction number, notes | per invoice status | CONFIRMED |
| **PaymentRecord** | Money received | customer type, transaction number, method, amount, currency, status, notes, date | pending / completed / … | CONFIRMED |
| **PaymentLink** | Hosted payment request | user type, gateway, currency, amount, 5% fee, description | active/used (INFERRED) | CONFIRMED |
| **PaymentMethod** | Manual method per country | country, enabled, methods[{name, active, logo, rich-text instructions}] | — | CONFIRMED |
| **DonationRecord** | Charitable payment | amount, method, transaction number, status | مكتمل / … | CONFIRMED |
| **Expense** | Outgoing cost | title, type, amount, currency, notes | — | CONFIRMED |
| **TeacherCourseRate** | Pay rate | teacher, per-course rates | — | CONFIRMED |
| **TeacherDeduction** | Payroll debit | teacher, amount, currency, date, reason | — | CONFIRMED |
| **TeacherIncentive** | Payroll credit | teacher, type (fixed/%), value, currency, date, notes | — | CONFIRMED |
| **TeacherSalary** | Monthly computation | teacher, period, session counters, hours, salary, currency | — | CONFIRMED |
| **TeacherSalaryInvoice** | Payslip | teacher, receipt number, period start/end, hours, final salary, currency, status, teacher confirmation, notes | pending · paid · cancelled | CONFIRMED |
| **SalaryWithdrawalRequest** | Payout request | teacher, amount USD, status, notes | per status | CONFIRMED |
| **SystemCode** | Voucher | type (activation/renewal/discount), package, course, session count, created, validity days, status, code `SYS-XXXXX` | unused · used · expired | CONFIRMED |
| **Conversation / ConversationGroup** | Internal chat | sender type, receiver type, attachments, read count, created / group name, image, participants | — | CONFIRMED |
| **Notification** | Outbound message record | target type, target, message, channels, status, read | pending · sent · failed | CONFIRMED |
| **ContactRequest** | Inbound enquiry | person type, name, email, phone, country, WhatsApp, message | — | CONFIRMED |
| **Article / ArticleCategory** | Blog | see §4.12 | published / draft | CONFIRMED |
| **Video** | Media library item | title, description, file, cover, SEO, keywords, published, views, reactions | published / unpublished | CONFIRMED |
| **Faq** | Q&A | ar/en question & answer, active, order | active / inactive | CONFIRMED |
| **StudentReview** | Testimonial | student name, stars, type (text/audio/video) | — | CONFIRMED |
| **SitePage** | CMS page | name, key, title, meta title/description, keywords (+ GrapesJS body) | — | CONFIRMED |
| **Advertisement** | Promo banner | banner, type (general/discount), title, body, expiry | active until expiry | CONFIRMED |
| **Redirect** | URL redirect | — | — | CONFIRMED (existence) |
| **PlayList / PlaylistVideo** | Recorded course | see §4.13 | published / draft / hidden | CONFIRMED |
| **RcSubscription / RcComment / RcReview** | Recorded-course commerce & feedback | playlist, student, amount, method, transaction, certificate flag, watched videos, notes | — | CONFIRMED |
| **Consultation / ConsultationRequest / ConsultationReview / ConsultationSchedule** | Advisory product line | see §4.14 | see §8 | CONFIRMED |
| **StudentReport** | Monthly AI report | student, subscription details, session details, report body, generation date | — | CONFIRMED |
| **HonorBoard** | Recognition | — | — | CONFIRMED (existence) |
| **FileUpload** | Media/document library | — | — | CONFIRMED (existence) |
| **LanguageLine** | UI translation string | — | — | CONFIRMED (permission only) |
| **SiteSetting / SystemSetting** | Singleton config | see §4.17 / §4.12 | — | CONFIRMED |
| **RequestCenter** | Unknown request queue | — | — | CONFIRMED (permission + a notification referencing "مركز الطلبات") / UNKNOWN |

---

## 8. State Machines / State Transitions

### 8.1 Subscription — `CONFIRMED (states)` / `INFERRED (triggers)`

```
            create
              ↓
          ساري (active) ──── تجديد (renew, manual/bulk/auto) ──→ ساري (new cycle)
            │   │
   suspend  │   │  expiry reached / sessions exhausted
            ↓   ↓
   موقوف مؤقتًا  منتهي (expired)
   (limited by "عدد أيام التعليق المسموح بها",
    itself derived from the package's freeze-day allowance)
            │           │
            └───────────┴──→ "المسح مع حفظ السجلات" → soft-deleted
                                (visible via the "السجلات المحذوفة" filter,
                                 restorable via restore permission)
                          └──→ "المسح النهائي" → force-deleted
                          └──→ archived to /admin/expired-subscriptions
```
Invalid/unavailable: no observed path from منتهي back to ساري other than renewal.

### 8.2 Session — `CONFIRMED`

```
                       generated from a weekly schedule
                                     ↓
                            status = مجدولة (scheduled)
             ┌───────────────────────┼───────────────────────┐
     تحويل إلى حضور            تحويل إلى غياب            إلغاء الحصة
             ↓                       ↓                       ↓
      attendance = present     attendance = absent      status = cancelled
             ↓                       ↓
      status → completed       may spawn a compensation session
      (bulk "تحديد كمكتملة" exists on the archive)   (is_compensation = true,
             ↓                                       compensation date set)
   archived to /admin/expired-sessions

Attendance sub-state (independent for student and teacher):
      not_set ──→ present (with timestamp)
              └─→ absent
      (+ "عذر الطالب" student excuse field → feeds "الحصص المعتذر عنها" in payroll)

Report sub-state:
      not_sent ──(teacher submits)──→ sent
              └──(reminder fires)──→ report_reminder_sent_at stamped
                                     → counts as "تقارير غير مرسلة" → deduction

Teacher approval sub-state: لم يتم التعيين → موافق | غير موافق
   (set automatically on creation — observed value `approved`)
```

### 8.3 Trial session — `CONFIRMED`
```
مجدولة → مكتملة | ملغية        (plus an independent "request status")
```

### 8.4 Consultation request — `CONFIRMED`
```
قيد المراجعة → تم التأكيد وتأكيد الموعد → مكتمل
      │                    │
      └────→ ملغي          └────→ تم طلب اعاده الجدولة  (only when the
                                   consultation product is reschedulable)
Session sub-state: مجدولة → مكتملة | غياب
```

### 8.5 Other state sets — `CONFIRMED`

| Entity | States |
|---|---|
| Student | نشط · قيد الانتظار · تجريبي · قيد التقدم · متوقف مؤقتا · غير نشط |
| Weekly schedule | نشط · متوقف · محذوف (× cross-tabs for active/expired subscription) |
| Notification | قيد الانتظار → مرسل \| فشل |
| System code | لم يستخدم بعد → مستخدم \| منتهي الصلاحية |
| Teacher salary invoice | قيد الانتظار → مدفوع \| ملغي (+ teacher receipt confirmation) |
| Homework | غير مكتمل → مكتمل |
| Playlist video | مسودة → منشور \| مخفي |
| Consultation product | متاحة \| مؤرشفة |
| Level upgrade request | approved \| rejected (+ reason) |
| Payment record / donation | includes مكتمل (completed); other values UNKNOWN |
| Package / Course / FAQ / Group / Family account | active ↔ inactive (+ visible ↔ hidden for package/course) |

### 8.6 Restricted transitions observed

* A weekly schedule **cannot be created for a student without an active subscription** (form hint). `CONFIRMED`.
* A session **cannot be created for a student who is not active and lacks both a subscription and a weekly schedule** (form hint). `CONFIRMED`.
* Session teacher/course choices are **constrained to the selected weekly schedule** (form hints). `CONFIRMED`.
* A student **already linked to a family account cannot be added to another**; likewise for groups (form hints). `CONFIRMED`.
* Only students whose `account_type = individual` appear in the individual-subscription selector; only `family`-type students appear in the family-account selector. `CONFIRMED`.
* A withdrawal request expects a teacher **with sufficient balance** (form hint). `CONFIRMED` as guidance, `UNKNOWN` as a hard validation.

---

## 9. APIs

**No public/documented REST API was found.** `/api`, `/api/v1`, `/api/documentation`, `/api/user` all return 404. `CONFIRMED`.

The application is a **server-rendered Livewire app**; effectively all admin interaction is:

| Endpoint | Method | Purpose | Auth | Notes |
|---|---|---|---|---|
| `/livewire/update` | POST | Every Filament interaction — table loads, filters, pagination, form updates, actions, modals | Session cookie + CSRF | `CONFIRMED`. Payloads are Livewire component snapshots + calls, not a domain API |
| `/admin/{resource}` | GET | Server-rendered list page (many defer their table body to a follow-up `livewire/update`) | Session | `CONFIRMED` |
| `/admin/{resource}/create`, `/admin/{resource}/{id}/edit` | GET | Server-rendered forms | Session | `CONFIRMED` |
| `/admin/sessions/{id}/activities` | GET | Activity log page | Session | `CONFIRMED` |
| `/select-language/{locale}` | GET | Locale switch | Any | `CONFIRMED` |
| `/class/{session_uid}` | GET | Jitsi classroom page | UNKNOWN | `CONFIRMED` (renders) / `UNKNOWN` (auth requirement) |
| `/student/STD-#####`, `/teacher/TCH-#####` | GET | Quick-login / impersonation entry points | UNKNOWN | `CONFIRMED` (links) / `UNKNOWN` (guard) |
| `/student/auth/google` | GET | OAuth redirect | Public | `CONFIRMED` |
| `/student/login`, `/student/register`, `/student/proregister`, `/student/password/forgot` | GET/POST | Student auth (classic form POST with `_token`) | Public | `CONFIRMED` |
| `/system-only-error` | GET | Public-site lockout page on the demo | Public | `CONFIRMED` |

**Inbound integration endpoints that must exist but were not located** (`UNKNOWN`): Stripe webhook (a **webhook secret field** exists in settings, so a receiving route exists), PayPal IPN/webhook, and the "API" trial-request source implies an inbound booking endpoint. Guessed paths (`/webhooks/stripe`, `/stripe/webhook`, `/paypal/webhook`) all 404 — `HIGH priority unknown`.

**Outbound API calls the system makes** (`CONFIRMED` from settings/actions): Qur'an chapters API ("مزامنة السور من API"), IP geolocation API, Exchange Rate API, Google Gemini, Google OAuth, reCAPTCHA verification, Zoom API, kMeet API, WhatsApp, Stripe, PayPal, SMTP, Jitsi external API (browser-side).

---

## 10. External Integrations

| ID | Integration | Configuration fields observed | Used for | Evidence |
|---|---|---|---|---|
| INT-001 | **Stripe** | publishable key, secret key, **webhook secret**, notes | Subscriptions, payment links, donations, RC subscriptions, consultations. Live `pi_…` PaymentIntent IDs stored | CONFIRMED |
| INT-002 | **PayPal** | status, client ID, client secret, **currency\***, **language\***, notes | Payments, payment links, consultations | CONFIRMED |
| INT-003 | **Manual / local payment methods** | per-country enable + list of {name, active, logo, rich-text instructions} | Bank transfer, Zelle, InstaPay, Telda, PayMob and similar | CONFIRMED |
| INT-004 | **Jitsi Meet** | none in settings (uses `meet.jit.si`) | The live classroom at `/class/{uid}` | CONFIRMED |
| INT-005 | **Zoom** | ZOOM ACCOUNT ID, ZOOM API KEY, ZOOM API SECRET, notes; feature flag "نظام زووم API"; `teacher_zoom_link` resource | Alternative classroom provider | CONFIRMED |
| INT-006 | **kMeet** | KMEET_API_KEY | Alternative meeting provider | CONFIRMED |
| INT-007 | **WhatsApp** | admin WhatsApp number, **repeater of {group name, group ID}**, notes | Notification delivery; per-teacher and per-schedule group overrides | CONFIRMED |
| INT-008 | **Google OAuth** | GOOGLE CLIENT ID, GOOGLE CLIENT SECRET | Student social login | CONFIRMED |
| INT-009 | **Google reCAPTCHA** | RECAPTCHA SITEKEY | Public forms (INFERRED) | CONFIRMED (config) |
| INT-010 | **Google Gemini** | GEMINI API KEY | AI: article body/short description, SEO title/description, keyword suggestions, course description & overview, category descriptions, **employment contract drafting**, **monthly student reports**. Feature flag "المساعد الذكي" | CONFIRMED |
| INT-011 | **TinyMCE** | TINY_LICENSE_KEY | Rich-text editing | CONFIRMED |
| INT-012 | **IP API** | API_TOKEN | Geolocating registrations/logins (student IP field) | CONFIRMED |
| INT-013 | **Exchange Rate API** | EXCHANGE_RATE_API_KEY | Multi-currency conversion | CONFIRMED (config) / INFERRED (usage) |
| INT-014 | **Email / SMTP** | MAIL_MAILER\*, MAIL_FROM_ADDRESS\*, MAIL_FROM_NAME\*, notes | Notifications, quick-login links, invoices | CONFIRMED |
| INT-015 | **Qur'an chapters API** | none exposed | "مزامنة السور من API" action | CONFIRMED |
| INT-016 | **Olovix (vendor)** | OLOVIX UID, OLOVIX DEVICE UID; feature flag "نظام أولوفيكس الداخلي"; license ID `OLO-VXXX` | **Licensing / phone-home / vendor support** | CONFIRMED (config) / INFERRED (purpose) |
| INT-017 | **GrapesJS** | — | Site page builder (client-side) | CONFIRMED (assets) |

---

## 11. UI / UX Behaviour

*Functional behaviour only; visual styling is out of scope.*

| Aspect | Observed behaviour | Evidence |
|---|---|---|
| **Navigation** | Collapsible sidebar with 11 collapsible groups; **live count badges** per item; breadcrumbs; topbar with Quick Create, language switcher, user menu, theme toggle | CONFIRMED |
| **Hidden navigation** | ~20 modules have **no sidebar entry** and are reached only through "return to X" / context buttons on related screens (e.g. Students → Monthly reports; Sessions → Homework; Teachers → contracts, rates, deductions, incentives, salary invoices, availability, Zoom links; Site settings → advertisements, redirects, site pages; Playlists → RC subscriptions/comments/reviews) | CONFIRMED |
| **Tables** | Deferred loading (most list bodies arrive in a second Livewire round-trip), search, multi-filter panel with an **active-filter count badge** and "reset filters", **column toggle ("تبديل الأعمدة")**, per-page selector **5 / 10 / 25 / 50 / All**, "showing X to Y of Z results", select-all + per-row checkboxes for bulk actions | CONFIRMED |
| **Status tabs** | Several resources put status filters in tabs with counts rather than the filter panel (students, subscriptions, weekly schedules, sessions) | CONFIRMED |
| **Forms** | Tabbed multi-section forms (up to 7 tabs); repeaters for nested collections; **almost every field carries an Arabic helper hint**, many phrased as operational advice ("نصيحة للإدارة: …"); required fields marked with `*`; save options include **"إضافة وبدء إضافة المزيد"** (save and create another) | CONFIRMED |
| **Conditional UI** | Fields reveal others (e.g. student "ولي أمر جديد" toggle swaps between a new-parent form and an existing-parent picker; teacher "إضافة وسائط" reveals a media field; "هل تود تخصيص جروب الإشعار؟" reveals group pickers; level-upgrade rejection reason appears when approval is off) | CONFIRMED |
| **Dependent selects** | Session form filters teacher/course by the chosen weekly schedule; consultation request loads available slots only after a teacher is chosen; certificate session-count auto-fills from student+course; student-report panels populate after a student is chosen | CONFIRMED |
| **Modals** | Confirmation modals with heading, description, confirm/cancel (subscription renewal); form modals (bulk scheduling with a date range); several `/create` routes 404 → those resources create via modal rather than a page | CONFIRMED |
| **Row actions** | Rendered inline; include destructive actions (delete, cancel session, permanent delete) | CONFIRMED |
| **Empty states** | Plain text, e.g. **"لا توجد الشهادات"**; dependent panels show "الرجاء اختيار طالب أولاً" | CONFIRMED |
| **Loading states** | Livewire deferred table loading; the bulk-scheduling modal warns the operation may take time; the student login button has a "Logging…" state | CONFIRMED |
| **Progress indicators** | Subscription progress rendered as an **animated striped percentage bar** (a `filament-progressbar` plugin); note that the bar's inline `<style>` block leaks into the table cell's text content | CONFIRMED |
| **Emoji as UI vocabulary** | Status glyphs (🟢 نشط, 🟢 مدفوع, ❌), 🌿 in page titles, ⭐ rating scales, 😊🙂😐😕😞 report ratings, 🚀 "rocket icon" to stamp the actual session time | CONFIRMED |
| **RTL** | Whole admin is right-to-left; English/Spanish locales available | CONFIRMED |
| **Responsive** | Sidebar collapses; layout adapted at a 771 px viewport during the audit | CONFIRMED (basic) |
| **Error pages** | Custom 404 ("Oh No! Error 404 … May the force be with you!" + "Back to Home"); custom 403 ("403 - Unauthorized"); custom lockout page (`/system-only-error`, "Restricted Area") | CONFIRMED |
| **Console warning** | Panels emit *"Livewire: The published Livewire assets are out of date"* | CONFIRMED |

---

## 12. Business Rules

Rules are recorded with their **trigger**, **scope**, **affected feature** and **evidence**. Most come from on-screen helper text (which in this product is unusually explicit) or from observed constraints.

| # | Rule | Trigger / scope | Feature | Evidence | Confidence |
|---|---|---|---|---|---|
| BR-01 | A weekly schedule cannot be created for a student without an active subscription | Weekly schedule create | SCHED-001 | Form hint: *"لا يمكن انشاء جدول لطالب ليس لديه اشتراك نشط"* | CONFIRMED (stated) / INFERRED (enforced) |
| BR-02 | A session requires an active student **with** a subscription **and** a weekly schedule | Session create | SCHED-003 | Hint: *"يجب ان يكون الطالب حسابه نشط ولديه اشتراك وجدول اسبوعي"* | CONFIRMED (stated) |
| BR-03 | A session's teacher and course must come from the selected weekly schedule | Session create | SCHED-003 | Hints: *"سيتم عرض المعلمين من الجدول الأسبوعي المختار"*, *"اختر الكورس الذي يدرسه المعلم المختار… من الجدول الأسبوعي"* | CONFIRMED |
| BR-04 | Session default duration is derived from the subscription for the chosen course, and is manually overridable | Session create | SCHED-003 | Hint: *"يتم تحديد مدة الحصة تلقائياً من الاشتراك حسب الكورس المختار، ويمكنك تع…"* | CONFIRMED |
| BR-05 | Teacher approval is set automatically when a session is created | Session create | SCHED-003 | Hint: *"يتم تعيين موافقة المعلم تلقائياً عند إنشاء الحصة"*; activity log shows `approved` at creation | CONFIRMED |
| BR-06 | The session's "creation date" is the field used for salary calculation | Payroll | PAY-001 | Hint: *"…(يتم استخدامه لحساب الروا…)"* | CONFIRMED |
| BR-07 | Subscription "sessions attended" is computed from completed sessions | Subscription | SUB-001 | Hint: *"يتم حساب عدد الحصص التي تم حضورها بناءً على عدد الجلسات التي أنجزها ال…"* | CONFIRMED |
| BR-08 | Sessions attended **beyond** the package during the grace period are counted as "extra sessions" | Subscription | SUB-001 | Hint: *"عندما يحضر الطالب حصصًا إضافية خلال فترة السماح الخاصة به يتم إضافتها…"* | CONFIRMED |
| BR-09 | Total sessions is derived from the selected packages | Subscription | SUB-001 | Hint: *"إجمالي عدد الحصص التي اشترك فيها الطالب طبقًا للباقات المختارة"* | CONFIRMED |
| BR-10 | Original amount is auto-computed as the sum of the selected packages' prices | Subscription | SUB-001 | Hint: *"يتم حسابه تلقائياً من مجموع أسعار الب…"* | CONFIRMED |
| BR-11 | Renewal is priced from the subscription's **paid amount**, which is manually editable | Renewal | SUB-002 | Hint: *"هذا المبلغ الذي سيتم تجديد الاشتراك بناء عليه , يمكنك تعديله يدويا"* | CONFIRMED |
| BR-12 | A subscription may be suspended only for a limited number of days, configured per subscription and derived from the package's freeze-day allowance | Subscription | SUB-001 / CATALOG-003 | Fields "عدد أيام التعليق المسموح بها" (subscription) and "الأيام المسموح بها لتعليق الباقة" (package) | CONFIRMED (fields) / INFERRED (linkage) |
| BR-13 | There is a global cap on postponements | System-wide | SYS-001 | Setting "الحد الاقصي لامكانية التأجيل" | CONFIRMED (setting) / UNKNOWN (semantics) |
| BR-14 | Only students with `account_type = individual` can be placed on an individual subscription | Subscription | SUB-001 | Hint: *"يظهر هنا الطلاب نوع حسابهم فردي"* | CONFIRMED |
| BR-15 | Only students with `account_type = family` can join a family account; a student already linked cannot be linked again | Family accounts | PEOPLE-002 | Hint on "الحسابات المرتبطة" | CONFIRMED |
| BR-16 | A family account must nominate one linked account as **payer** | Family accounts | PEOPLE-002 | Required field "الحساب المسؤول عن الدفع" | CONFIRMED |
| BR-17 | A student already in a group cannot be added to another group | Groups | PEOPLE-003 | Hint on "الطلاب المرتبطة" | CONFIRMED |
| BR-18 | Parent passwords must be at least 8 characters | Parent create | PEOPLE-004 | Hint: *"يجب أن تحتوي كلمة المرور على 8 أحرف على الأقل"* | CONFIRMED |
| BR-19 | Student phone numbers must include a country code and a `+` | Student create | PEOPLE-001 | Hint: *"أدخل رقم هاتف صحيح يبدأ برمز الدولة وتاكد من وجود علامة+"* | CONFIRMED (stated) |
| BR-20 | A student's age group is derived from date of birth | Student create | PEOPLE-001 | Hint: *"تأكد من إدخال تاريخ الميلاد الصحيح لتصنيف الطالب ضمن الفئة العمرية المناسبة"*; `student_age_group` is a hidden derived field on the registration form | CONFIRMED |
| BR-21 | On the Enhanced registration, **minor ⇒ family account**, **adult ⇒ individual account** | Registration | AUTH-009 | The age-group selector's own labels | CONFIRMED |
| BR-22 | Student wallet balance can pay invoices/subscriptions and is used to compensate students for sessions | Billing | BILL-007 | Field hint | CONFIRMED |
| BR-23 | A withdrawal request should target a teacher with sufficient balance | Payroll | PAY-007 | Hint: *"اختر معلم لديه رصيد كافي لسحب الراتب"* | CONFIRMED (stated) / UNKNOWN (hard-enforced?) |
| BR-24 | Withdrawal amounts are denominated in USD regardless of the teacher's salary currency | Payroll | PAY-007 | Label "المبلغ المطلوب (بالدولار)" | CONFIRMED |
| BR-25 | Service fee on payment links and invoices is **5%** | Billing | BILL-003 / BILL-004 | Toggle labels; invoice hint says *"رسوم الخدمة مفعلة دائماً (5%)"* | CONFIRMED |
| BR-26 | Consultations may carry a 5% gateway fee and a **booking validity window in days** after payment | Consultations | CONS-001 | Fields "رسوم ٥٪" and "مدة صلاحية الحجز (بالأيام)" with hint | CONFIRMED |
| BR-27 | A consultation can be rescheduled only if the product allows it | Consultations | CONS-001/002 | Toggle "امكانيه اعادة الجدول" + request status "تم طلب اعاده الجدولة" | CONFIRMED (fields) / INFERRED (gating) |
| BR-28 | Consultation slots are only offered after a teacher is selected | Consultations | CONS-002 | Hint: *"يرجى اختيار المعلم أولاً لعرض المواعيد المتاحة"* | CONFIRMED |
| BR-29 | Invoice numbers are auto-generated when left blank | Billing | BILL-003 | Hint: *"سيتم إنشاؤه تلقائياً إذا تركته فارغاً"* | CONFIRMED |
| BR-30 | Teacher identifiers are auto-generated | Teachers | PEOPLE-005 | Hint: *"يتم انشاءه تلقائياً"* | CONFIRMED |
| BR-31 | Certificate completed-session count auto-fills from the chosen student + course | Certificates | CERT-002 | Hint: *"يتم تعبئته تلقائياً بناءً على الطالب والكورس المختار"* | CONFIRMED |
| BR-32 | Session reports are sent by the teacher to the administration and are **not** forwarded to (…) | Sessions | SCHED-003 | Hint truncated in the DOM: *"هذا التقرير يتم ارساله بواسطة المعلم كملاحظات للادارة ولا يتم ارسالة ل…"* | CONFIRMED (partial) — see Unknowns |
| BR-33 | Failure to submit session reports produces a payroll deduction | Payroll | PAY-008 | Settings tab "خصم التقارير"; feature flag "نظام خصومات التقارير"; payroll inputs "التقارير المرسلة / الغير مرسلة" | CONFIRMED (mechanism exists) / INFERRED (exact rule) |
| BR-34 | Teacher salary is paid in the teacher's own currency | Payroll | PAY-001 | EGP and USD rows in the same table | CONFIRMED |
| BR-35 | Package prices may be overridden per country | Pricing | CATALOG-003 | "أسعار الباقة في الدول" repeater + feature flag "نظام الاسعار المخصص حسب الدولة" | CONFIRMED |
| BR-36 | Payment methods are offered per country and can be disabled for a country wholesale | Billing | BILL-002 | Country field + "تفعيل وسائل الدفع للدولة" | CONFIRMED |
| BR-37 | Trial-session duration must be between 1 and 180 minutes | Trial sessions | SCHED-007 | Hint: *"حدد مدة الحصة التجريبية بالدقائق (من 1 إلى 180)"* | CONFIRMED |
| BR-38 | Videos: max 5 GB, MP4/MOV; covers JPG/PNG/WEBP at 16:9; SEO title ≤ 60 chars; SEO description ≤ 160 chars | Video library | CNT-003 | Field hints | CONFIRMED (stated) |
| BR-39 | Certificate template images ≤ 5 MB; certificate student photos ≤ 2 MB; course banner/icon ≤ 5 MB; playlist intro video ≤ 100 MB; playlist thumbnails 400×225; payment-method logos 200×200 | Uploads | CERT-001/002, CATALOG-001, RC-001, BILL-002 | Field hints | CONFIRMED (stated) |
| BR-40 | A teacher can be hidden from the public homepage independently of being enabled | Teachers | PEOPLE-005 | Separate toggles "مفعل" and "الظهور في الرئيسية" | CONFIRMED |
| BR-41 | A course/package can be active but not visible (and vice-versa) | Catalogue | CATALOG-001/003 | Separate "نشطة"/"مرئية" toggles | CONFIRMED |
| BR-42 | Notification status and read flag are system-managed and not editable by an operator | Notifications | COMM-003 | Hint on both fields: *"لا يمكن تعديل هذا الحقل"* | CONFIRMED |
| BR-43 | Chat participation is controllable per student via two separate toggles (can create conversations; chat system enabled) | Messaging | PEOPLE-001 / COMM-001 | Student form toggles | CONFIRMED |
| BR-44 | Deleting a weekly schedule can either delete outright or **move its sessions** | Scheduling | SCHED-001 | Bulk action "حذف مع نقل الحصص" | CONFIRMED (action) / UNKNOWN (target) |
| BR-45 | Subscription deletion has two tiers: keep records (soft) vs permanent | Subscriptions | SUB-004 | Row/bulk actions + "deleted records" filter + restore/force-delete permissions | CONFIRMED |
| BR-46 | Total-sessions-ever counts both the live sessions table and the archive | Dashboard | DASH-004 | Widget label *"من جدول سجلات الحصص و سجلات الارشيف"* | CONFIRMED |
| BR-47 | Revenue this month counts **completed** payment records only | Dashboard | DASH-003 | Widget label *"الإيرادات من سجلات الدفع المكتملة في الشهر الحالي"* | CONFIRMED |
| BR-48 | Net profit = revenue − expenses, monthly | Dashboard | DASH-003 | Widget label *"(الإيرادات - المصروفات)"* | CONFIRMED |
| BR-49 | Operators are instructed to verify payroll manually in the current version | Payroll | PAY-001 | On-screen notice | CONFIRMED |
| BR-50 | Entire subsystems are switched by feature flags; disabling one removes its UI | System-wide | SYS-002 | 34 flags; `request::center` has no reachable UI and no granted permissions | CONFIRMED (flags) / INFERRED (causal link) |

---

## 13. Validation Rules

Because submitting forms would have mutated the demo, validation was audited **statically** (required markers, input types, hints) rather than by provoking errors. Server-side messages are therefore `UNKNOWN`.

### 13.1 Confirmed required-field sets (selection)

| Entity | Required (`*`) fields |
|---|---|
| Student | name, date of birth, gender, account type, registration date, email, phone, country, nationality, preferred language, status, password |
| Teacher | name, gender, address, preferred language, email, phone, payout method, payout details, bio, enabled, show-on-homepage, rating, dashboard style, password |
| Parent | name, email, phone, registration date, password |
| Admin user | name, email, password |
| Course | name, slug, category, teachers, short description, visible, lesson count, language, overview |
| Package | name, description, features, weekly lessons, type, session duration, duration, duration unit, max days, freeze days, price, currency, visible |
| Subscription | type, payment method, payment status, payment number, individual type, start date, duration, payment type, subscription system, details, student, courses, (per detail) course/teacher/package/session duration, mode, sessions attended, extra sessions, total sessions, paid amount, original amount, hourly price, suspension days, weekly sessions |
| Weekly schedule | subscription type, student, subscription; per slot: days, course, start time, teacher |
| Session | student, subscription, weekly schedule, day, teacher, course, default duration, session status, report status |
| Trial session | student, source, course, student count, teacher gender, duration, datetime, request date, status, request status, link, both attendances, attribution |
| Invoice | student, type, status, issue date, amount due, currency |
| Payment record | customer type, method, amount, currency, status, payment date |
| Teacher deduction | teacher, amount, currency, date, reason |
| Teacher incentive | teacher, type, value, currency, date |
| Salary invoice | teacher, receipt number, period start, period end, status, final salary, currency |
| Withdrawal request | teacher, amount, status |
| Consultation | name, description, price, duration, validity days, participants, delivery mode, status, responsible teachers |
| Consultation request | student name, email, WhatsApp, consultation, teacher, session status, session datetime, both attendances, request status |
| Certificate | type, student, course |
| System code | type, package, course, validity days |
| Notification | target, message, channels |
| Homework | student, title, type, file, status |
| Level upgrade request | student, subscription, course; rejection reason when not approved |

### 13.2 Confirmed type-level validation

* `email` inputs on student/teacher/parent/user/contact/consultation forms.
* `tel` inputs with a country-code component (`tapp/filament-country-code-field`); the student registration form splits phone into `phone_country_code`, `phone_number`, `phone_full`.
* `url` inputs: session link, extra-session link, playlist video URL, Zoom meeting URL.
* `date` / `datetime-local` / `time` inputs throughout; time fields annotate the active timezone.
* `number` inputs for all monetary, count and duration fields.
* Numeric bounds stated in hints: trial duration 1–180; teacher rating 1–5; service fee fixed at 5%.
* Character limits stated in hints: video SEO title ≤ 60, SEO description ≤ 160.
* File-type and size constraints listed in BR-38 / BR-39.
* Uniqueness is implied for slugs (`الرابط المختصر`), page keys, playlist codes and receipt numbers — `INFERRED`, not observed.

### 13.3 Not determined

Server-side error message text and format, cross-field validations (e.g. end time after start time, period end after period start), duplicate-email handling, password complexity beyond the parent-form minimum, and whether the "sufficient balance" and "active subscription" hints are enforced or advisory. All `UNKNOWN`.

---

## 14. Error Handling

| Condition | Observed behaviour | Evidence |
|---|---|---|
| Unknown route | Custom **404** page: *"Oh No! Error 404 — This page you requested counld not found. May the force be with you!"* + "Back to Home" (typo present in the product) | CONFIRMED |
| Unauthorized page | Custom **403** page titled *"403 - Unauthorized"* (observed at `/admin/quick-translate` **as `super_admin`**) | CONFIRMED |
| Public site disabled | Redirect to `/system-only-error` — *"Restricted Access - System Only"*, heading "Restricted Area" | CONFIRMED |
| Unauthenticated admin access | Redirect to the panel login page | CONFIRMED (observed at session start) |
| Route-prefix confusion | An authenticated `fetch` of `/admin/password-reset/request` resolved to `/parent/login` — suggesting panel password-reset routes overlap or resolve unexpectedly | CONFIRMED (observation) / UNKNOWN (cause) — worth flagging as a possible defect |
| Empty dataset | Plain empty-state text (e.g. *"لا توجد الشهادات"*); dependent panels show *"الرجاء اختيار طالب أولاً"* | CONFIRMED |
| Long-running action | Modal warns *"قد تستغرق العملية بعض الوقت"* before bulk scheduling | CONFIRMED |
| Client-side console | Persistent warning that published Livewire assets are out of date | CONFIRMED |
| Debug mode | The demo runs with `APP_DEBUG` on and `APP_ENV=local`, so raw stack traces would be exposed on error | CONFIRMED (status page) — **not exercised** |
| Form validation failure | `UNKNOWN — not exercised (would mutate demo data)` |
| Payment gateway failure | `UNKNOWN` |
| External API failure (Gemini, IP API, exchange rate, Qur'an sync) | `UNKNOWN` |
| Email/WhatsApp delivery failure | Notification status has a **فشل (failed)** value, so failures are recorded; retry behaviour `UNKNOWN` | CONFIRMED (state) |

---

## 15. Edge Cases

| Case | What is known | Confidence |
|---|---|---|
| **Slot exists but no session generated** | Directly observed: the today-sessions board showed two Wednesday slots with scheduling status "لم يتم جدولتها" and link status "لم يتم الجدولة" (❌). Sessions are **not** generated automatically on the demo — generation is an explicit (or scheduled) action | CONFIRMED |
| **Session outside the package** | Supported first-class: `extra sessions` on the subscription, plus a separate ExtraSession entity with its own "paid to teacher?" flag | CONFIRMED |
| **Student absent** | Recorded as an attendance state, carries a separate "عذر الطالب" excuse field, is counted separately in payroll ("حصص غياب الطالب", "الحصص المعتذر عنها"), and can spawn a compensation session | CONFIRMED |
| **Teacher absent** | Dedicated notification templates (warning, absence notice) and payroll treatment; a **substitute teacher** field exists on the session | CONFIRMED |
| **Session opened by a supervisor** | `is_session_opened_by_supervisor` and `supervisor_attendance` fields exist | CONFIRMED (fields) / UNKNOWN (flow) |
| **Multiple accounts on one phone** | Explicitly handled in student password recovery with an account-selection step | CONFIRMED |
| **Same student in two groups / two family accounts** | Blocked by form hints | CONFIRMED (stated) |
| **Deleting a schedule with future sessions** | Two behaviours offered: plain delete vs **"حذف مع نقل الحصص"** (delete and move the sessions) | CONFIRMED (action) / UNKNOWN (destination) |
| **Deleting a subscription with history** | Two tiers: soft ("keep records") and permanent | CONFIRMED |
| **Timezone mismatch** | Per-user timezones plus a system timezone; lists are explicitly labelled "توقيت النظام"; consultation requests store the **student's** timezone separately | CONFIRMED |
| **Multi-currency payroll** | Confirmed: EGP and USD in the same payroll table; withdrawals always in USD | CONFIRMED |
| **Expired subscription still having schedules** | The weekly-schedule list has dedicated tabs for "ذات الاشتراك النشط" vs "ذات الاشتراك المنتهي" — so the state is expected and visible | CONFIRMED |
| **Zero-data state** | Demo shows growth rate **−100.0%** when the previous month had data and the current has none — no divide-by-zero guard issue observed, but the figure is presented without qualification | CONFIRMED |
| **Large datasets** | Pagination supports an **"All"** option, which on a real dataset would be a performance risk | CONFIRMED (option exists) / INFERRED (risk) |
| **Concurrent edits** | `UNKNOWN — no optimistic-locking or conflict UI observed` | UNKNOWN |
| **Duplicate submissions / double-click on generate** | `UNKNOWN` | UNKNOWN |
| **Partial failure of bulk generation** | `UNKNOWN` | UNKNOWN |
| **Reverting an activity-log entry on a session that changed since** | `UNKNOWN` | UNKNOWN |

---

## 16. Feature Dependencies

### 16.1 Backbone chain

```
Authentication
      ↓
Authorization (roles → 71 resources × 12 verbs; page & widget gates)
      ↓
People (Students · Teachers · Parents · Family accounts · Groups)
      ↓
Catalogue (Courses → Categories; Packages → per-country prices; Levels)
      ↓
Subscriptions  ──(auto-invoice)──→ Invoices → Payments
      ↓
Weekly Schedules
      ↓
Sessions ──→ Attendance ──→ ┬─→ Subscription progress → Renewal / Archive
                            ├─→ Teacher payroll → Salary invoices → Withdrawals
                            ├─→ Session reports → report deductions
                            ├─→ Homework · Level upgrades · Certificates
                            └─→ Notifications
      ↓
Reports & Exports · Dashboard
```

### 16.2 Cross-feature dependencies (observed)

```
Creating a Subscription
    ├── requires Student (account_type must match the subscription type)
    ├── requires Course(s) + Teacher(s) + Package(s)
    ├── derives  total sessions, original amount, weekly session count
    ├── creates/links WeeklySchedule(s)
    ├── may create Invoice (auto-invoice) and PaymentRecord
    ├── consumes a SystemCode when the activation-code route is used
    └── appears in dashboard subscription stats + Excel export

Generating a Session
    ├── requires an active Subscription and an active WeeklySchedule
    ├── requires Teacher availability (TeacherSchedule) — INFERRED
    ├── creates a Jitsi room (uid, meeting_id, meeting_password)
    ├── schedules 10 notification timestamps
    ├── writes an ActivityLog entry
    └── becomes an input to SubscriptionProgress and TeacherSalary

Computing a Teacher Salary
    ├── requires Sessions in the window (completed / absent / compensation / excused)
    ├── requires ExtraSessions and TrialSessions flagged "paid to teacher"
    ├── requires TeacherCourseRate (per course)
    ├── applies TeacherIncentive and TeacherDeduction
    ├── applies report deductions from SessionReport status
    ├── produces TeacherSalaryInvoice
    └── is drawn down by SalaryWithdrawalRequest against Teacher balance

Issuing a Certificate
    ├── requires Course.certificate = on (or Playlist.accredited certificate)
    ├── requires completed Sessions for the student+course (auto-counted)
    └── requires a CertificateTemplate for custom types

Publishing an Article
    ├── requires ArticleCategory
    ├── optionally invokes Gemini (body, SEO title/description, keywords)
    └── surfaces on the public site (SitePage/site settings must be live)

Sending a Notification
    ├── requires a target (user, group, or broadcast)
    ├── requires channels + the recipient's preference toggles
    ├── requires a bilingual template from SystemSetting
    └── may require a WhatsApp group ID (global, per-teacher, or per-schedule)
```

### 16.3 Feature-flag dependencies

Each of the 34 flags gates a whole vertical. Observed or strongly implied gating relationships: `نظام حسابات العائلات` → family accounts + family-type subscriptions; `نظام اولياء الامور` → the Parent panel; `نظام الواجبات` → homework; `نظام تقارير الحصص` → session reports → `نظام خصومات التقارير` → report deductions in payroll; `نظام المحادثات الداخلية` → conversations + chat groups + per-student chat toggles; `نظام الكورسات المسجله` → playlists, playlist videos, RC subscriptions/comments/reviews; `نظام الاستشارات` → consultations + teacher "offers consultations"; `نظام الشهادات الموثق` → certificates; `نظام المستويات` → levels + level upgrade requests; `نظام الحوافز والخصومات` → incentives/deductions; `نظام الارصده` → wallet balances; `نظام التبرع` → donations; `نظام الاسعار المخصص حسب الدولة` → per-country package prices; `نظام تصدير اكسيل` → every Excel export action; `نظام ارشيف الاشتراكات` / `نظام ارشيف الحصص` → the two archives; `نظام الفواتير والايصالات` → invoices + salary receipts; `نظام العقود` → agreements; `نظام زووم API` → Zoom links; `المساعد الذكي` → all AI generate buttons; `نظام الاشراف العام` → supervisor fields on sessions; `نظام المجموعات` → groups; `روابط الدفع` → payment links; `نظام رفع الملفات` → the file library; `نظام اعاده توجيه الروابط` → redirects; `نظام انتظار تسجيل الطالب` → the pending-student status. `INFERRED` (names map cleanly onto observed modules, but the gating was not toggled and verified).

---

## 17. External Actors

| Actor | Direction | What crosses the boundary | Evidence |
|---|---|---|---|
| **Student** | in/out | Registration data, scheduling preferences, attendance, homework responses, payments, reviews; receives reminders, reports, certificates, invoices | CONFIRMED |
| **Parent** | in/out | Child linkage, WhatsApp consent; receives notifications about children | CONFIRMED |
| **Teacher** | in/out | Profile, CV, contract, availability, attendance, session reports, homework feedback, withdrawal requests; receives reminders, schedules, salary receipts | CONFIRMED |
| **Supervisor** | in/out | Session oversight (`supervisor_id`, `supervisor_attendance`, session opening); participates in chat | CONFIRMED (references) / UNKNOWN (interface) |
| **Admin / staff** | in/out | All operational data | CONFIRMED |
| **Stripe** | out/in | Charge creation; PaymentIntent IDs back; webhook events in (webhook secret configured) | CONFIRMED |
| **PayPal** | out/in | Payment creation and confirmation | CONFIRMED |
| **Local payment providers** (Zelle, InstaPay, Telda, PayMob, bank transfer) | out-of-band | Manual reconciliation; instructions rendered to the payer | CONFIRMED |
| **Jitsi (meet.jit.si)** | out | Room name, display name, email of the joining user | CONFIRMED |
| **Zoom / kMeet** | out | Meeting creation via API keys | CONFIRMED (config) |
| **WhatsApp** | out | Notification text to numbers and group IDs | CONFIRMED (config) |
| **SMTP provider** | out | Emails (notifications, quick-login links, invoices) | CONFIRMED |
| **Google (OAuth)** | out/in | Student identity | CONFIRMED |
| **Google (reCAPTCHA)** | out/in | Bot-check tokens | CONFIRMED (config) |
| **Google Gemini** | out/in | Prompts containing course/article/student/session data; generated text back — **note this means student data may leave the system for report generation** | CONFIRMED (config + AI actions) / INFERRED (payload content) |
| **IP geolocation API** | out/in | Visitor IP → location | CONFIRMED (config) |
| **Exchange rate API** | out/in | Currency rates | CONFIRMED (config) |
| **Qur'an chapters API** | out/in | Surah reference data | CONFIRMED (action) |
| **Olovix (vendor)** | out/in | `OLOVIX UID`, `OLOVIX DEVICE UID`, license ID — licensing/telemetry | CONFIRMED (config) / INFERRED (purpose) |
| **Search engines / public visitors** | in | Public site, articles, courses, packages, SEO metadata, schema, sitemap | CONFIRMED (SEO surface) / disabled on the demo |

---

## 18. Hidden / Secondary Features

The single most important structural finding of this audit: **the sidebar shows 34 of ~54 admin modules**.

### 18.1 Modules with no sidebar entry (all CONFIRMED to exist and return HTTP 200)

| Path | Title | Reached from |
|---|---|---|
| `/admin/family-accounts` | حسابات العائلات | Students screen, Quick Create |
| `/admin/groups` | المجموعات | Students screen |
| `/admin/invoices` | فواتير الطلاب الشهرية | Students screen |
| `/admin/student-reports` | تقارير الطلاب | Students → التقارير الشهرية |
| `/admin/honor-boards` | لوحة الشرف | Students screen |
| `/admin/agreements` | عقود العمل | Teachers screen |
| `/admin/teacher-course-rates` | أجور الساعة للمعلمين | Teachers screen |
| `/admin/teacher-deductions` | خصومات المعلمين | Teachers screen |
| `/admin/teacher-incentives` | حوافز المعلمين | Teachers screen |
| `/admin/teacher-salary-invoices` | إيصالات رواتب المعلمين الشهرية | Teachers screen |
| `/admin/teacher-schedules` | مواعيد المعلمين | Teachers screen |
| `/admin/teacher-zoom-links` | روابط زووم المعلمين | Teachers screen |
| `/admin/homework` | واجبات | Sessions screen |
| `/admin/session-reports` | تقارير الحصص | Sessions screen |
| `/admin/session-reviews` | تقييمات الحصص | Sessions screen |
| `/admin/extra-sessions` | الحصص الإضافية | — |
| `/admin/expired-sessions` | أرشيف الحصص | Sessions header |
| `/admin/expired-subscriptions` | أرشيف الاشتراكات | Subscriptions header |
| `/admin/payment-methods` | وسائل الدفع التقليدية | Payment records header |
| `/admin/level-upgrade-requests` | طلبات رفع المستوى | Levels screen |
| `/admin/course-categories` | تصنيفات الدورات | Courses header |
| `/admin/article-categories` | فئات المقالات | Articles header |
| `/admin/site-pages` | صفحات الموقع | Site settings |
| `/admin/advertisements` | الإعلانات | Site settings |
| `/admin/redirects` | إعادة توجيه الروابط | Site settings |
| `/admin/rc-subscriptions` | اشتراكات الكورسات المسجلة | Playlists screen |
| `/admin/rc-comments` | التعليقات | Playlists screen |
| `/admin/rc-reviews` | التقييمات | Playlists screen |
| `/onlyadmin/sessions-lite` | النسخة المبسطة للحصص | Sessions header — **different route prefix** |

### 18.2 Features hidden behind menus, dialogs and settings

* The **user menu** hides seven administrative surfaces (site settings, system settings, roles, themes, file uploads, system status, 2FA) that have no sidebar presence.
* **Quick Create** offers a Family-account shortcut for a module absent from the sidebar.
* **Dashboard stat cards are links** to pre-filtered lists (`?tableFilters[...]`).
* **Bulk actions** hide meaningful business operations, not just deletion: renew subscriptions, convert students to/from active, create a family account from selection, send quick-login links, duplicate a course/package, mark sessions present/absent/cancelled, mark archived sessions complete, deactivate/activate schedules, *delete a schedule and move its sessions*, bulk-create salary receipts, send unpaid-invoice notices.
* **System status** hides three operational jobs: clear cache, **manually reconcile subscriptions**, **notify teachers of the monthly review**.
* **Per-row "monitor" (مراقبة)** silently opens the live Jitsi room for any session.
* **The activity log** is reachable only via a per-row icon on sessions.
* **`/admin/quick-translate`** exists but 403s; **`language::line` (ترجمات)** is a permission group with no route.
* **`request::center`** — permission group, zero grants, 404 route, yet a notification referencing "مركز الطلبات" exists in the demo data.

### 18.3 Conditional / flagged functionality

The 34 feature flags in *إعدادات المطور* are the master switch list (§4.17 SYS-002). Some flags reference capabilities with **no corresponding UI found**: `نظام الحصص المجانيه للمشتركين` (free sessions for subscribers), `نظام روابط عامة` (public links), `نظام انتظار تسجيل الطالب` (registration waiting list), `نظام راتب المعلم الثابت` (fixed teacher salary), `نظام أولوفيكس الداخلي` (Olovix internal), `نظام سجلات ايصالات الدفع` (payment receipt records).

---

## 19. Unknowns & Open Questions

| Pri | Question | Why it matters | Feature ID | Missing evidence | How to investigate |
|---|---|---|---|---|---|
| **CRITICAL** | What do the Teacher, Parent and Student panels actually contain? | Three of four user-facing surfaces are unmapped; any faithful model of the system depends on them | PANEL-002/003/004 | No credentials | Obtain demo teacher/parent/student logins, or use admin quick-login (mutates state — needs owner consent) |
| **CRITICAL** | What is the subscription **renewal** page and what does it do to the old cycle? | Renewal is a core commercial workflow and the archive's trigger | SUB-002 | Confirm dialog only | Click "متابعة" on a disposable subscription |
| **CRITICAL** | Exact payroll arithmetic (how each session class is weighted; how report deductions are computed; what "fixed salary" mode does) | Payroll is the highest-risk calculation in the system | PAY-001/002/008/009 | Only input names | Seed data and compare computed salary against known inputs; open "توقعات الرواتب" |
| **HIGH** | Is session generation ever automatic (cron), or always operator-triggered? | Determines whether a scheduler exists | SCHED-002 | Board showed ungenerated slots; a manual "schedule all" exists | Observe an instance across a day boundary; ask the vendor |
| **HIGH** | Are `/class/{uid}` and `/student/STD-#####` protected? | Potential unauthenticated exposure of session data and account access | AUTH-011, SCHED-014 | Fetched with an admin session present | Request both from a clean, unauthenticated browser profile |
| **HIGH** | What is the `day` encoding `friday_4`? | Directly shapes how recurrence is represented | SCHED-003 | One observed value | Inspect several sessions across different schedule slots and weeks |
| **HIGH** | Where are the Stripe/PayPal webhooks, and what do they update? | Payment state transitions depend on them | INT-001/002 | Webhook secret field exists; no route found | Inspect the gateway dashboard's configured endpoint, or vendor docs |
| **HIGH** | What exactly does "حذف مع نقل الحصص" move the sessions **to**? | Data-integrity behaviour on schedule deletion | BR-44 | Action label only | Execute on disposable data |
| **HIGH** | Why does `/admin/quick-translate` 403 for a `super_admin`? | Reveals a second authorization mechanism beyond roles | SYS-007, RBAC-009 | 403 only | Toggle related feature flags; inspect vendor documentation |
| **MEDIUM** | What is "مركز الطلبات" (request centre)? | An entire subsystem is referenced but unreachable | LEAD-003 | Permission group + one notification | Enable related flags; ask the vendor |
| **MEDIUM** | Full text of the truncated session-report rule (BR-32) | Determines whether reports reach students/parents | BR-32 | Hint truncated in the DOM | Read the field hint in the live UI at full width |
| **MEDIUM** | Server-side validation messages and cross-field rules | Needed for faithful behaviour | §13.3 | Not exercised | Submit deliberately invalid forms on disposable data |
| **MEDIUM** | Export file formats and column sets (7 Excel exports + student export + schedule download) | Reporting parity | EXP-002/003/004 | Action labels only | Trigger each export and inspect the file |
| **MEDIUM** | Notification **channels** available (the checkbox list was not enumerated) | Determines the delivery matrix | COMM-003 | Field exists, options not read | Open the notification create form in the live UI |
| **MEDIUM** | Does the archive move rows to separate tables, or is it a scoped view? | Data-model consequence | SCHED-005, SUB-003 | Dashboard label implies two tables ("جدول سجلات الحصص و سجلات الارشيف") | Compare IDs before/after archiving |
| **MEDIUM** | How does a Supervisor sign in and what can they see? | A whole actor type is unresolved | §5.1 | No panel; role exists in admin | Create a user with the Supervisor role and log in |
| **MEDIUM** | Fields for the modal-only resources (honor boards, redirects, teacher schedules, session reviews, educational content) | Five entities have unknown shape | PEOPLE-007, CNT-008, SCHED-012, SCHED-010, CATALOG-007 | `/create` returns 404 | Open the create modal in the live UI |
| **MEDIUM** | Is there realtime chat (websockets) and what broadcasts? | `echo.js` is loaded but no connection was inspected | COMM-001 | Asset presence only | Inspect websocket frames while two users chat |
| **LOW** | Does activity logging cover entities other than sessions? | Audit-trail scope | SYS-008 | Only the session route found | Probe `/{resource}/{id}/activities` on other resources |
| **LOW** | What does "الحد الاقصي لامكانية التأجيل" cap, precisely? | Postponement policy | BR-13 | Setting label only | Vendor docs / experimentation |
| **LOW** | What is `page_SystemStatus`-gated "support" link behaviour? | Minor | SYS-004 | Label only | Click it |
| **LOW** | Sitemap generation (route 404s on the demo) | SEO parity | PANEL-006 | robots.txt references it | Check a production instance |

---

## 20. Investigation Gaps

1. **Three of four panels unmapped** (Teacher, Parent, Student). This is the dominant gap; roughly half of the product's *user-facing* behaviour is inferred from admin-side fields rather than observed.
2. **No mutating actions were performed.** Creates, updates, deletes, renewals, generations, exports and payments were deliberately not executed on the owner's demo instance. Consequently: validation behaviour, side effects, transactional integrity, and job/queue behaviour are all inferential.
3. **Demo dataset is tiny** (4 students, 5 teachers, 2 subscriptions, 4 sessions, 1 payment). Aggregate/report behaviour, pagination at scale, and performance characteristics could not be observed.
4. **Deferred table loading** meant column sets for ~30 list screens could not be captured from server-rendered HTML; columns were obtained live only for the highest-value screens.
5. **No database, code, logs or configuration access** — everything is black-box. Field names in §4.7 come from an activity log, which is the closest the audit got to the schema.
6. **The public marketing site is disabled** on the demo, so the entire public funnel (course pages, package pages, checkout, article rendering, SEO output, site pages built in GrapesJS) is unobserved.
7. **Feature flags were not toggled**, so flag→UI causality is inferred from naming.
8. **Localisation coverage**: only the Arabic locale was exercised; the English and Spanish surfaces were not compared for completeness.
9. **Mobile/responsive behaviour** was only lightly exercised (one narrow viewport).
10. **Time-dependent behaviour** (reminder dispatch, auto-renewal, month rollover, archive triggers) was not observable in a single session.

---

## 21. Coverage Report

### Features discovered

**~150 discrete features** across **21 functional areas**, carrying stable IDs:

| Area | ID prefix | Count |
|---|---|---|
| Authentication & access | AUTH | 15 |
| Authorization | RBAC | 10 |
| Dashboard | DASH | 7 |
| People | PEOPLE | 8 |
| Catalogue | CATALOG | 7 |
| Commerce / subscriptions | SUB | 5 |
| Scheduling & delivery | SCHED | 14 |
| Student billing | BILL | 7 |
| Teacher payroll | PAY | 10 |
| Certificates | CERT | 3 |
| Communications | COMM | 8 |
| Marketing & content | CNT | 9 |
| Recorded courses | RC | 5 |
| Consultations | CONS | 4 |
| Inbound / leads | LEAD | 3 |
| Reporting & export | EXP | 6 |
| Platform / system | SYS | 8 |
| Panels | PANEL | 7 |
| Integrations | INT | 17 |
| **Total identified** | | **153** |

Plus **34 feature flags** and **~54 admin CRUD modules**.

### User roles discovered

* **Actor types:** 5 — Admin, Supervisor, Teacher, Student, Parent.
* **Configured roles on the demo:** 2 — `super_admin` (847 permissions), `Supervisor` (24).
* **Permission surface:** 856 permission values = 71 resources × 12 verbs (less exceptions) + 5 page + 5 widget + 3 custom.

### Domain entities discovered

**71 permission-gated entities**, of which **~54 have a reachable admin UI**, **~17 are backend-only or modal-only**. Fully catalogued in §7.2.

### Major workflows discovered

**13 documented end-to-end flows** (FLOW-001 … FLOW-013): acquisition, trial lifecycle, subscription creation, session materialisation, session delivery & attendance, teacher payroll, student billing, renewal, consultation booking, level progression, certificate issuance, password recovery, notification dispatch.

### Integrations discovered

**17** (INT-001 … INT-017): Stripe, PayPal, manual/local payment methods, Jitsi, Zoom, kMeet, WhatsApp, Google OAuth, reCAPTCHA, Gemini, TinyMCE, IP API, Exchange Rate API, SMTP, Qur'an API, Olovix vendor, GrapesJS.

### APIs discovered

**No public REST API.** One effective transport endpoint (`POST /livewire/update`) plus server-rendered routes. Webhook receivers are implied by configuration but were not located. See §9.

### Business rules discovered

**50 rules** (BR-01 … BR-50) — 40 `CONFIRMED`, 10 `INFERRED`/partially confirmed. Plus required-field sets for 25 entities and the type/size/bound validations in §13.

### Unknowns

**22 open questions** — 3 CRITICAL, 7 HIGH, 8 MEDIUM, 4 LOW (§19), and **10 structural investigation gaps** (§20).

### Areas requiring deeper investigation

1. Teacher / Parent / Student panels (CRITICAL).
2. Payroll arithmetic and the salary-projection screen (CRITICAL).
3. Subscription renewal mechanics and archive semantics (CRITICAL/HIGH).
4. Session generation triggering — manual vs scheduled (HIGH).
5. Authentication guards on impersonation and classroom URLs (HIGH, also a security question).
6. Recurrence encoding (`friday_4`) (HIGH).
7. Payment webhook handling and payment state transitions (HIGH).
8. Server-side validation and error behaviour (MEDIUM).
9. Export formats (MEDIUM).
10. Realtime/chat transport (MEDIUM).

### Potentially hidden functionality (not yet reached)

`مركز الطلبات` (request centre) · `ترجمات` / QuickTranslate · `نظام الحصص المجانيه للمشتركين` (free sessions for subscribers) · `نظام روابط عامة` (public links) · `نظام انتظار تسجيل الطالب` (registration waiting list) · `نظام راتب المعلم الثابت` (fixed teacher salary) · `نظام أولوفيكس الداخلي` (vendor-internal system) · `نظام سجلات ايصالات الدفع` (payment receipt records) · consultation reviews & schedules · honor board · RC comments & reviews · redirects · teacher availability · session reviews · educational content.

---

## 22. Evidence / Confidence Notes

### 22.1 How evidence was obtained

| Method | Used for | Reliability |
|---|---|---|
| Rendered-page reading (accessibility tree, visible text, screenshots) | Navigation, list columns, modals, empty states, dashboards | Highest — directly observed |
| Authenticated same-origin `fetch()` + DOM parsing of server-rendered HTML | Form schemas (fields, types, required markers, hints, select options), filters, header/bulk actions, headings | High — the markup is the application's own output. Caveat: Filament defers some table bodies, so absent columns ≠ no columns |
| Livewire component-state extraction (`wire:snapshot`) on the roles screen | The complete permission model, role compositions, page/widget/custom permission keys | High — this is the server's own serialised state |
| Activity-log reading | Session attribute names and enum values | High for *field names*; the mapping to database columns is `INFERRED` |
| Route probing (HTTP status + title) | Discovery of the ~20 hidden modules, absence of APIs/webhooks, panel structure | High for presence; **absence of a route is not proof of absence of a feature** |
| Network-request inspection | Framework versions, plugin inventory, Livewire transport, Echo presence | High |
| On-screen helper text | Business rules | High that the rule is *stated*; `INFERRED` that it is *enforced* |

### 22.2 Deliberate limits

* **No data was created, modified or deleted.** Two modals were opened and cancelled (bulk scheduling, subscription renewal); nothing was submitted. No exports were triggered. No impersonation was used.
* **No credentials were entered by the auditor** for any panel; the admin session was established by the system owner.
* **No attempt was made to bypass authorization.** The single 403 encountered is reported as observed, not probed further.

### 22.3 Confidence summary

| Area | Confidence | Note |
|---|---|---|
| Admin navigation & module inventory | **CONFIRMED** | Exhaustively enumerated, including hidden routes |
| Form/field inventory (admin) | **CONFIRMED** | ~45 forms extracted field-by-field with types, required markers and hints |
| Permission model | **CONFIRMED** | Read from server state, not guessed |
| Entity list | **CONFIRMED** (names) / **INFERRED** (attributes for backend-only entities) | 71 names are authoritative; ~17 have no observed fields |
| State machines | **CONFIRMED** (state values) / **INFERRED** (transition triggers) | Values read from selects and tabs; triggers mostly from action labels |
| Business rules | **CONFIRMED as stated** / **INFERRED as enforced** | None were tested by provoking failure |
| Workflows | **PROBABLE** | Assembled from field-level evidence, hints and status vocabularies rather than executed end-to-end |
| Integrations | **CONFIRMED** (configured) / **INFERRED** (runtime usage) | Configuration fields are direct evidence; actual call behaviour is not |
| Teacher/Parent/Student panels | **UNKNOWN** | Login screens only |
| Validation & error behaviour | **UNKNOWN** | Not exercised by design |
| Performance, concurrency, jobs | **UNKNOWN** | Not observable black-box in one session |

### 22.4 Statements explicitly **not** made in this document

* No claim about database tables, columns, types, indexes or relationships beyond the domain level.
* No claim that any stated rule is enforced server-side.
* No claim about which features belong to which commercial licence tier.
* No claim that the hidden modules are intentionally hidden rather than pending navigation entries.
* No design, technology or implementation recommendation of any kind — those belong to Phases 2–5.

---

*End of Phase 1 — System Audit. Feature IDs (AUTH-, RBAC-, DASH-, PEOPLE-, CATALOG-, SUB-, SCHED-, BILL-, PAY-, CERT-, COMM-, CNT-, RC-, CONS-, LEAD-, EXP-, SYS-, PANEL-, INT-, FLOW-, BR-) are stable and are to be referenced by later phases.*



