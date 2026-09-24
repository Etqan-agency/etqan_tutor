# TutorHamster Feature Audit (2026-09-24)

**Why this exists:** the product owner asked for "a clone of https://www.tutorhamster.com/ — audit all system features in detail before starting any work". This document lists what TutorHamster does and compares it, feature by feature, with what etqan_tutor has built or planned. It is meant to help decide what to build next.

**Sources, all read-only:**

| Source | What it gave | Date |
|---|---|---|
| `docs/PHASE_1_SYSTEM_AUDIT.md` | The earlier audit of the admin panel, including hidden modules, permissions, flows and business rules. Its feature IDs are reused here. | 2026-09-15 / 2026-09-23 |
| Crawl of the demo admin panel (`/admin`, Arabic UI, Filament 3 / Livewire), captured with page navigation only: no clicks on actions and no form submissions | All 50 navigation entries (headings, list columns, filters, header and bulk actions, tabs), 38 create forms, 12 edit views of existing records, the settings pages, and 50 screenshots | 2026-09-24 |
| Saved HTML of `/teacher/login`, `/parent/login`, `/student/login` | Proof that the other panels exist, and what their login pages contain | 2026-09-24 |
| Vendor homepage text (`tutorhamster.com`) | The features the vendor advertises, its pricing plans and the apps it claims | 2026-09-24 |
| `docs/superpowers/specs/2026-09-23-etqan-tutor-v1-design.md`, `…-academy-sites-design.md`, the backend and dashboard source | What etqan_tutor has decided on and built | 2026-09-24 |

**Evidence labels** (the same as Phase 1):

- `CONFIRMED`: seen directly.
- `PROBABLE`: strongly implied by what was seen.
- `INFERRED`: a reasonable reading of the evidence.
- `UNKNOWN`: not observed.

Where a field label in the demo ends in `*`, the field is **required**. Every file-upload field was reported as "required" by the crawl whatever its label said; the package-image hint even says "optional". So a file field is shown as required below only when its label has `*`.

---

## 1. Summary

### 1.1 What TutorHamster is

TutorHamster (version **18.5** on today's system-status page; Phase 1 recorded 18) is a licensed, **single-academy** operations product for online 1:1 and small-group tutoring. It is aimed mainly at Arabic and Qur'an teaching. It is sold in tiers:

- $40 a month, $100 a quarter, $370 a year, or $800 for a lifetime self-hosted licence.
- A "limited free version for small academies".
- The vendor says the full version includes a Windows/Mac desktop program and a mobile app.

The core of the product is **academy operations**:

- packages are sold as subscriptions
- a subscription gets a weekly timetable
- the timetable becomes individual session records
- attendance is recorded on each session by both sides
- both student billing and teacher payroll are worked out from those session records

Around this core it adds families and groups, levels and a Qur'an curriculum, certificates, internal chat, WhatsApp and email notifications, online payment links, recorded-course sales, paid consultations, a marketing CMS, AI content generation and 37 feature flags.

### 1.2 Size

| Measure | Count | Source |
|---|---|---|
| User-facing surfaces (panels) | 4 logins (Admin, Teacher, Parent, Student), a live-classroom page and a public site (disabled on the demo) | Phase 1 PANEL-001…007; login pages re-checked today |
| Admin navigation entries | **50**: 35 sidebar modules, the dashboard, 8 user-menu pages and 6 "Quick create" shortcuts | today (`nav.json`) |
| Admin modules including hidden ones | ~54 CRUD modules plus about 29 screens that are not in the sidebar | Phase 1 §18.1 |
| Permission-gated resources | 71 resources × 12 verbs (the role form's "Resources" tab shows **846**), plus 5 page and 5 widget permissions | today + Phase 1 RBAC-002 |
| Feature flags ("Developer settings" tab) | **37**, of which 6 are marked "(مدفوع)" = paid add-on | today |
| System-settings fields | 132, spread over 8 top-level tabs and nested per-template / per-integration sub-tabs | today |
| Fields inventoried today | **1,191 raw field records → ≈560 unique fields**, taken from 28 forms and settings pages (this includes 132 system-settings fields and 72 permission groups) | today |
| Automated notification templates | 11 templates, each with an Arabic and English text and its own on/off switch | today |

### 1.3 What changed compared with the 2026-09-15/23 audit

**No new modules or menu entries.** Today's 35 sidebar modules match the Phase 1 sidebar one for one. The 8 user-menu pages and the 6 quick-create shortcuts are also unchanged. The new findings are at the level of fields, options and settings:

| # | Finding | New ID or Phase-1 ID |
|---|---|---|
| 1 | **3 feature flags that are not in the Phase-1 list of 34:**<br>• "custom teacher hourly rate per student" (تخصيص سعر الساعه للمعلم). Its hint: *"lets you set the teacher's hourly rate per student; the normal hourly-rate calculation stops"*.<br>• "teacher can record student attendance" (إمكانية أن يأخذ المعلم حضور الطالب), *"directly from the teacher panel"*.<br>• "AI reports" (تقارير الذكاء الاصطناعي).<br>Either these arrived with version 18.5 or Phase 1 missed them. | PAY-011, SCHED-016, EXP-001 |
| 2 | Six flags are marked **paid add-ons**: levels, file uploads/CDN, payment links, internal chat, Excel export, and "Olovix internal". | SYS-009 |
| 3 | The channels for manually composed notifications are **Email and WhatsApp**. Phase 1 had left this as an open MEDIUM question. | COMM-009 |
| 4 | Session option lists:<br>• **Session status**: scheduled (مجدولة) · completed (مكتملة) · absent without excuse (غائب بدون عذر) · **at the administration's disposal (تحت تصرف الإدارة)**.<br>• **Attendance**, for each side: present (حاضر) · absent without excuse (غائب بدون عذر) · **excused absence (غياب بعذر)** · not recorded (لم يتم التسجيل). | SCHED-003 |
| 5 | The full session-report hint: *"sent by the teacher as notes to the administration and **not sent to the student**"*. This answers Phase 1 BR-32, which had been cut off. | SCHED-003/009 |
| 6 | Subscription option lists:<br>• **payment method**: via administration, PayPal, activation code, Stripe, payment link, cash, Venmo, CashApp, Zelle, Western Union<br>• **payment status**: pending, completed, failed, refunded, cancelled<br>• **payment type**: prepaid (مقدم) / postpaid (مؤخر)<br>• **subscription system**: normal (عادي) / monthly (شهري)<br>• **individual-subscription type**: normal / group | SUB-006 |
| 7 | Every subscription form carries a **"Calculate and update subscription details"** button, with the note that the totals (sessions, amount, hours) are only worked out when it is pressed. | SUB-007 |
| 8 | A **subscription roster** tab lists each student with their UID and the number of *completed* sessions at which they were present. | SUB-008 |
| 9 | Extra sessions outside the package: *"added here and **deducted later in the following month**"*. | SUB-001 |
| 10 | Weekly-schedule times are stored in the system timezone but the form shows each one in the **student's timezone** (e.g. "11:45 AM (America/Los_Angeles)"). | SCHED-017 |
| 11 | **Postponement window:** "Max postponement limit (minutes)" — *"the student and the teacher can postpone a session before this time"*. This partly answers Phase 1's LOW question on BR-13. | SCHED-015 |
| 12 | 11 teacher **payout methods**: Vodafone Cash, InstaPay, bank account, Mashreq Neo, Western Union, Wise, PayPal, Telda, Abu Dhabi bank, cash, STC Pay. Each comes with a required "payment method details" field. | PEOPLE-005 |
| 13 | **Per-country package prices** are a repeater of country + price + currency. Seen: Egypt → EGP, Saudi Arabia → SAR. | CATALOG-003 |
| 14 | **Site status** modes: live (يعمل) · under maintenance · beta · **system only (النظام فقط)**. The last one explains why the demo's public site shows "Restricted Area". | CNT-010 |
| 15 | The student **nationality** field has only two values: Arab (عربي) / Foreign (أجنبي). There are 21 preset student tags and 22 preset teacher tags, each with an emoji (e.g. "⭐ star of the month"). | PEOPLE-001/005 |
| 16 | Student-registration waiting list, from the flag hint: *"students can't register on the platform except after administration approval or with a code"*. | LEAD-004 |
| 17 | An expense row titled "teacher salary – {teacher} – receipt INV-…", of type "salaries" → teacher salary receipts appear to be **posted to expenses**. | PAY-013 (PROBABLE) |
| 18 | The sessions page states *"compensation and postponement sessions have been moved into session records"*. It has context buttons to **Session reports · Session reviews · Homework**. The students page has buttons to **Families · Groups · Receipts (الايصالات)**. | SCHED-003, PEOPLE-001 |
| 19 | The Today board at 05:47 on Thursday listed that day's 21:40 slot as "not scheduled" (لم يتم جدولتها ❌). Two sessions dated 2026-08-14 are still "scheduled" although both sides are marked present. So **nothing had auto-generated today's sessions by early morning, and attendance does not auto-complete a session.** Neither observation proves there is no automation. | SCHED-002/003 |
| 20 | The PayPal settings have a sandbox/production switch and 6 currencies (USD, EUR, SAR, AED, GBP, CAD). The mail transport can be SMTP, Mailgun, SES, Postmark, Sendmail or Log. | INT (Phase 1) |
| 21 | A vendor support widget ("TutorHamster support is ready to help you") appears on the system-status page. | SYS-004 |

### 1.4 What still could not be observed (details in §4)

- The contents of the Teacher, Parent and Student panels (no credentials).
- Every flow that changes data: renewal, bulk generation, payroll receipts, payments and webhooks, deletes.
- Everything that runs on a timer.
- About 29 hidden admin screens, which were not re-crawled today (their fields are in Phase 1).
- Some lazily loaded tabs.
- The disabled public site.
- The AI assistant.
- The advertised desktop and mobile apps.

---

## 2. Module-by-module inventory

Each module below gives: purpose · fields (label [Arabic] · type · required · options / hint) · list columns · filters · actions · rules. "(P1)" means the detail comes from Phase 1 and was not re-observed today.

### 2.1 People

#### PEOPLE-001 — Students (الطلاب) `/admin/students`

The customer record. Public ID `STD-#####`.

**List**
- **Columns:** Photo · Student name (+ email) · Country · Account type · Student status.
- **Status tabs:** active (نشط) · pending (قيد الانتظار) · trial (تجريبي) · in progress (قيد التقدم) · paused (متوقف مؤقتا) · inactive (غير نشط) · all.
- **Filters:** country, nationality, timezone, account type, status, a custom "condition" (الشرط) filter.
- **Optional columns:** ID, phone, postal code, device type, IP, account status, balance, XP, registration date.

**Actions**
- **Header:** Add student · **Monthly reports** (→ `/admin/student-reports`) · **Export data**.
- **Context buttons:** Families · Groups · **Receipts** (الايصالات).
- **Row:** Edit · **Quick login** (دخول سريع).
- **Bulk:** delete · convert to active · convert to inactive · send quick-login link · **convert to family account** · **create family account**.

**Stat cards:** total students · new this month · growth rate against last month.

**Form:** 6 tabs on create, 7 on edit (the Parent tab appears only on edit).

| Tab | Field | Type | Req | Options / hint |
|---|---|---|---|---|
| Basic info | Profile photo (الصورة الشخصية) | image, with crop tool | – | "square, high quality preferred" |
| | Student name | text | ✓ | "avoid using different names for students" |
| | Date of birth | date | ✓ | "…to classify the student into the right **age group**" |
| | Gender | select | ✓ | male / female |
| | **Account type** (نوع الحساب) | select | ✓ | **individual (فرد) / family (عائلة)** |
| | Age group (الفئة العمرية) | select | – | "minor" (قاصر) seen; other values UNKNOWN |
| | Registration date | datetime | ✓ | |
| | Tags (الوسوم) | multi-select | – | 21 presets, e.g. 🎓 new, 🌟 outstanding, ⭐ star of the month, 💯 proficient memoriser (حافظ متقن), 📖 skilled reader, 🎤 fluent speaker, 📅 member for 1 year … "to encourage the student" |
| | Active | toggle | – | |
| Contact | Email | email | ✓ | |
| | **Alias email** (البريد الالكتروني المستعار) | email | – | "backup for emergencies or to promote your brand" |
| | Phone | text | ✓ | "must start with the country code and +" |
| | Postal code | text | – | |
| | Country | select (≈250) | ✓ | |
| | **Nationality** | select | ✓ | **Arab / Foreign** |
| | Timezone | select (IANA list) | – | "helps schedule sessions correctly" |
| Technical | Device type · IP address | text | – | filled in by student login (P1 AUTH-006) |
| Account & security | Preferred language | select | ✓ | not set / Arabic / English / Spanish |
| | Status | select | ✓ | 🟢 active · 🔄 trial · ⏳ in progress · ⏸️ paused · 🔴 inactive. "Pending" appears as a list tab but is **not offered in the form**. |
| | Password | password + generate | ✓ create / – edit | |
| Preferences | 7 toggles: session notifications · chat notifications · payment reminders · schedule-update notifications · reports & homework notifications · **can create conversations** · **chat enabled** | toggle | – | |
| Parent (edit only) | Parents (أولياء الأمور) | repeater | – | each row: "new parent" toggle → a new-parent sub-form, *or* "existing parent*" select; header note: "add existing parents or create new accounts" |
| Balances & points | **Balance** (الرصيد) | number | – | "used to pay invoices and subscriptions; students can be compensated for sessions as balance" |
| | **XP points** | number | – | "track progress and motivate the student" |

#### PEOPLE-002 — Family accounts (حسابات العائلات) `/admin/family-accounts`

Hidden from the sidebar. Reached from Quick create and the Students page.

| Field | Type | Req | Hint |
|---|---|---|---|
| Family name | text | ✓ | |
| Linked accounts | multi-select | ✓ | "students whose account type is **family**; a student linked to another family cannot be added" |
| **Account responsible for payment** (الحساب المسؤول عن الدفع) | select | ✓ | chosen from the linked accounts |
| Notes | textarea | – | |
| Active | toggle | – | |

The subscription create page has an **"Add new family"** header action.

#### PEOPLE-003 — Groups (المجموعات) — not re-crawled

From P1: group name\*, linked students\* (a student can be in only one group), notes, active. Today's evidence that groups are live: the weekly-schedule create form offers subscription type **individual / family / group**; the weekly-schedule list has a "group" filter; the Students page has a "Groups" button.

#### PEOPLE-004 — Parents (أولياء الأمور) `/admin/parents`

**List**
- **Columns:** name · phone · email · children · account status.
- **Filters:** account status, WhatsApp.
- **Actions:** add; edit; bulk delete.

| Tab | Field | Type | Req | Hint |
|---|---|---|---|---|
| Basic | Parent name · Email · Phone | text/email/tel | ✓ | |
| | **Registered on WhatsApp** | toggle | – | |
| Children & account | Children (الأبناء) | multi-select | – | |
| | Account active | toggle | – | |
| | Registration date | datetime | ✓ | |
| Extra | Preferred language (default Arabic) · Timezone | select | – | |
| Password | Password | password | ✓ create | "at least 8 characters" |

#### PEOPLE-005 — Teachers (المعلمين) `/admin/teachers`

Public ID `TCH-#####`.

**List**
- **Columns:** Photo · Teacher name · Gender + age (e.g. "male, 36") · **Rating** (★ with a label such as "weak") · Status.
- **Filter:** status.
- **Optional columns:** ID, phone, email.

**Actions**
- **Header:** Add · **Export data**.
- **Row:** edit · delete · **quick login** · **send quick-login link**.
- **Bulk:** send quick-login link · delete.

| Tab | Field | Type | Req | Options / hint |
|---|---|---|---|---|
| Basic | Teacher photo | image | – | |
| | Teacher name | text | ✓ | |
| | Gender | select | ✓ | male / female |
| | Date of birth | date | – | |
| | Address (العنوان) | text | ✓ | "teacher's home address" |
| | Identifier (المعرف) | text | – | "generated automatically" |
| | Preferred language | select | ✓ | not set / Arabic / English |
| | Tags | multi-select | – | 22 presets, e.g. 👑 excellent at teaching, 🎯 expert, 🤝 patient, ✨ inspiring |
| Contact | Email · Phone | email/tel | ✓ | phone "with country code" |
| | Second phone · Timezone | tel/select | – | |
| Financial | **Salary payout method** (طريقة استلام الراتب) | select | ✓ | Vodafone Cash · InstaPay · bank account · Mashreq Neo · Western Union · Wise · PayPal · Telda · Abu Dhabi bank · cash · STC Pay |
| | **Payment method details** | text | ✓ (seen on edit) | "information required by the chosen method" |
| | **Current balance** (الرصيد الحالي) | number | – | |
| | Note | – | – | |
| Bio & skills | Bio | textarea | ✓ | |
| | CV | file (PDF/Word/image) | – | |
| | Skills & subjects taught | text | – | |
| Media | "Add media" toggle → media file | toggle/file | – | |
| Contracts | Contracts list repeater: identifier, details, contract file | repeater | row fields required | |
| Settings | **Offers consultations** | toggle | – | |
| | Enabled | toggle | ✓ | |
| | **Show on home page** | toggle | ✓ | "appears on the site's home page" |
| | **Teacher rating** (تقييم المعلم) | select | ✓ | ★ very weak · ★★ weak · ★★★ average · ★★★★ good · ★★★★★ excellent |
| | **Dashboard style** (نمط اللوحة التحكم) | select | ✓ | default / simple (بسيط) |
| | **Custom notification group** | toggle | – | "use this teacher's own group for notifications" |
| | Password | password | ✓ create | |

#### PEOPLE-006 Employment contracts · PEOPLE-007 Honor board — not re-crawled

From P1: contracts have teacher\*, details (with an AI "generate contract wording" action) and a file. The Honor board's fields are UNKNOWN.

#### PEOPLE-008 — Admin users (المستخدمين) `/admin/users`

- **Columns:** name · email · roles.
- **Filter:** role.
- **Row:** edit/delete. The super admin's own row has no actions.
- **Form:** name\*, email\*, password\*, roles (multi, "more than one role allowed").
- **Seen roles:** Super Admin (847 permissions) and "Supervisor".

### 2.2 Catalogue

#### CATALOG-001 — Courses (الدورات) `/admin/courses`

**List**
- **Columns:** course name · number of teachers · status · created.
- **Filter:** status.
- **Actions:** add; **view course categories**; bulk **duplicate course** / delete.

| Tab | Field | Type | Req | Options / hint |
|---|---|---|---|---|
| Course info | Course banner · Image or video · Course icon | file | – | images ≤ 5 MB |
| | Course name | text | ✓ | |
| | Slug (رابط مختصر) | text | ✓ | |
| | Course category | select | ✓ | seen: Qur'an courses, Arabic-language courses; has a "Go to categories" link |
| | Teachers | multi-select + "select all" | ✓ | |
| | Short description | textarea | ✓ | **AI generate** |
| Course details | Active | toggle | – | "disable if you don't want students to see it" |
| | Visible | toggle | ✓ | "visible to students on the home page" |
| | Requirements | text | – | |
| | Lesson count | number | ✓ | |
| | **Certificate** | toggle | – | "students can get a certificate after completing" |
| | **Linked to the Qur'an curriculum** | toggle | – | |
| | Course language | select | ✓ | Arabic / English / Arabic & English |
| | Overview | rich text | ✓ | **AI generate** |
| SEO | SEO title · SEO description (**AI**) · keywords | text | – | |
| Schema | Schema codes (أكواد المخطط) | repeater | – | |

#### CATALOG-002 — Course categories — not re-crawled

From P1: icon, name\*, slug\*, description (AI).

#### CATALOG-003 — Packages (الباقات) `/admin/packages`

**List**
- **Columns:** name · price (e.g. "US$40.00") · duration (e.g. "1 month") · session length · status.
- **Filters:** status, visibility.
- **Optional columns:** ID, lessons per week, max days.
- **Bulk:** **duplicate package** · activate · deactivate.

| Tab | Field | Type | Req | Options / hint |
|---|---|---|---|---|
| Basic | Package image | image | – | "(optional)" |
| | Name · Description · **Features** | text/textarea | ✓ | |
| Sessions & prices | **Weekly lesson count** | number | ✓ | |
| | **Package type** | select | ✓ | individual (باقة فردية) / group (باقة جماعية) |
| | **Session length** | select | ✓ | 30 / 45 / 60 min / other |
| | **Duration + unit** | number + select | ✓ | day / month |
| | **Max package days** (الحد الأقصى لأيام الباقة) | number | ✓ | |
| | **Allowed freeze days** (الأيام المسموح بها لتعليق الباقة) | number | ✓ | |
| | Hourly price | number | – | |
| | **Discount %** | number | – | |
| | Package price | number | ✓ | "calculate the package price" |
| | Currency | select | ✓ | only USD offered |
| Visibility | Active ("available for subscription") | toggle | – | |
| | Visible on site | toggle | ✓ | |
| | **Popular** | toggle | – | |
| Per-country pricing (إعدادات تسعير الباقة في البلدان) | Repeater: **country\* · price\* · currency\*** | repeater | ✓ per row | seen: Egypt / EGP, Saudi Arabia / SAR |

#### CATALOG-004 — Levels (المستويات) `/admin/levels`

- **Columns:** course · level name · sub-levels · **topic count** · created.
- **Filter:** by course.
- **Form:** course\* · level name\* · **sub-levels & topics repeater**.

#### CATALOG-005 Level upgrade requests · CATALOG-007 Educational content

- **CATALOG-005** — not re-crawled. From P1: student, subscription, course, current level, approve toggle, rejection reason.
- **CATALOG-007 Educational content (المحتوى التعليمي)**: list with a course filter and "Add educational content". The create form's fields are UNKNOWN (P1: `/create` 404, so a modal is PROBABLE).

#### CATALOG-006 — Qur'an chapters (القرآن الكريم) `/admin/quran-chapters`

- **Columns:** revelation order · Arabic name · simple name · revelation place (makkah/…) · verse count · pages.
- **Actions:** **Sync chapters from API** · add · bulk delete.
- **Form sections:** chapter info (simple, Arabic and complex name) · revelation (place, order) · statistics (verse count, start page, end page).

### 2.3 Subscriptions

#### SUB-001 — Subscriptions (الاشتراكات) `/admin/subscriptions`

**List**
- **Stat cards:** all · active · expired.
- **Tabs:** active · expired · paused · all.
- **Columns:** account name · teacher(s) · **subscription progress (% bar)** · payment status (e.g. 🟢 paid) · subscription date.
- **Filters:** deleted records, account type, teacher, subscription status.
- **Optional columns:** account ID, paid amount, payment method.

**Actions**
- **Header:** add subscription · **Export to Excel** · **Subscription archive**.
- **Row:** edit · **renew** · **delete keeping records** · **permanent delete**.
- **Bulk:** permanent delete · **renew subscriptions** · delete keeping records.

**Form: 5 tabs**

| Tab | Field | Type | Req | Options / hint |
|---|---|---|---|---|
| Subscription info | Subscription type | select | ✓ | individual (فردي) / family (عائلي) |
| | Payment method | select | ✓ | via administration · PayPal · activation code · Stripe · payment link · cash · Venmo · CashApp · Zelle · Western Union |
| | Payment status | select | ✓ | pending · completed · failed · refunded · cancelled |
| | Payment number | text | ✓ | |
| | Individual-subscription type | select | ✓ | normal / group |
| | Start date | date | ✓ | |
| | Duration (days) | number | ✓ | |
| | **Payment type** | select | ✓ | **prepaid (مقدم) / postpaid (مؤخر)** |
| | **Subscription system** | select | ✓ | **normal (عادي) / monthly (شهري)** |
| | **Auto-renew** | toggle | – | |
| | **Auto invoices** | toggle | – | |
| | Details repeater → Student | select | ✓ | "only students whose account type is individual appear here" |
| | → Courses | multi-select | ✓ | |
| | → per-course rows: course\* · teacher\* · package\* · session length (min)\* | nested repeater | ✓ | **one subscription can mix several courses, each with its own teacher and package** |
| Weekly schedule | Linked weekly schedules repeater → existing schedule, student\*, schedule status toggle, timings repeater (days\* multi, course\*, teacher\*, start\*, end) | repeater | | header shows the subscription type, student and weekly session count; times hint shows the student's timezone |
| Summary | Note: *"press 'Calculate and update subscription details' so sessions, amount, hours are computed"* | button | | SUB-007 |
| | Current mode | select | ✓ | active (ساري) / paused (موقوف مؤقتًا) / expired (منتهي) — "changes according to the student's wish" |
| | **Sessions attended** | number | ✓ | "computed from completed sessions; **don't change manually**" |
| | **Extra sessions outside the package** | number | ✓ | "attended during the grace period; **deducted later in the following month**" |
| | Total sessions | number | ✓ | from the chosen packages |
| | Total subscription hours | number | – | |
| | **Paid amount** | number | ✓ | "**renewal is based on this amount**; editable" |
| | Original amount | number | ✓ | "before fees; sum of package prices" |
| | Hourly price | number | ✓ | |
| | **Allowed suspension days** | number | ✓ | "max days the subscriber can pause" |
| | Weekly session count | number | ✓ | |
| | Preferred times · Subscription notes | textarea | – | |
| Student levels | Level + completed topics repeater ("Add level for student") | repeater | – | |
| Roster & attendance | Table: student · UID · sessions present (completed only) | read-only | | SUB-008 |

#### SUB-002 Renewal · SUB-003 Archive · SUB-004 two-tier delete

Re-seen today as actions: renew (row and bulk), archive (header), "delete keeping records" vs "permanent delete", and a "deleted records" filter. The renewal page itself is still UNKNOWN (P1 CRITICAL).

#### SUB-005 — System codes (أكواد النظام) `/admin/system-codes`

- **Columns:** code type · code · expiry · created.
- **Filters:** code type, status, **discount type**, used.

| Field | Type | Req | Options / hint |
|---|---|---|---|
| Code type | select | ✓ | **activation / renewal / discount** |
| Package | select | ✓ | |
| Course | select | ✓ | |
| Session count | number | – | "from the package details" |
| Created date | datetime | – | |
| **Validity (days)** | number | ✓ | |
| Status | select | – | not used yet / used / expired |

The discount-type filter exists but the create form showed no discount-type or discount-value field. How discount codes are valued is UNKNOWN.

### 2.4 Scheduling & sessions

#### SCHED-001 — Weekly schedules (الجدول الأسبوعي) `/admin/weekly-schedules`

**List**
- **Tabs:** active · stopped · deleted · **with active subscription** · **with expired subscription** · all.
- **Columns:** student · **timings (system timezone)** as "day | from–to | course" lines · subscription progress.
- **Filters:** student, teacher, subscription type, group.

**Actions**
- **Header:** add · **Expand calendar** · **Download all schedules**.
- **Row:** edit · deactivate.
- **Bulk:** restore · permanent delete · **bulk change** (تغيير جماعي) · deactivate · activate · **delete and move sessions** (حذف مع نقل الحصص).

**Create form:** a first step only — subscription type\* (individual / family / **group**, radio) → student\* → subscription\*. Hint: *"a schedule cannot be created for a student without an active subscription"*.

**Edit form**

| Section | Field | Type | Req | Hint |
|---|---|---|---|---|
| Subscription info | Student · subscription details | read-only | | |
| Timings | Repeater: **days** (multi) · course · teacher (⭐-marked) · start time · end time | repeater | days, course, teacher, start ✓ | "choose several days with the same details and times"; each time shows "in the student's timezone: 09:40 PM (Africa/Cairo)" |
| Schedule status | Current status (read-only) · Schedule status toggle | toggle | | "**when stopped, no new sessions are created from this schedule**" |
| Notification group | Notify via group? | toggle | – | "send notifications through a WhatsApp group" |
| | Group per course: course\* → WhatsApp group | repeater | ✓ | seen group name "BK website" |

#### SCHED-002 — Today's core sessions board (حصص اليوم الاساسية) `/admin/today-sessions`

- **Title:** "Today's core sessions 🌿 {weekday} – {date} 🌿 {time}". Banner: "all times shown in Africa/Cairo".
- **Stat cards:** sessions this month · sessions today · total sessions ever ("from the session table **and the archive**").
- **Buttons:** **Schedule all sessions** (جدولة جميع الحصص) · **Bulk scheduling** (الجدولة المجمعة). P1: bulk scheduling is a modal with start/end date and "may take some time".
- **Columns:** student · account type · teacher · timings · subscription progress · **time remaining** · **scheduling status** · session-link status.
- **Filters:** teacher, student.
- **Observed:** today's Thursday slot showed "not scheduled" + ❌ at 05:47.

#### SCHED-003 — Session records (سجلات الحصص) `/admin/sessions`

**List**
- **Description:** *"add and browse all sessions; compensation and postponement sessions were moved into session records"*.
- **Stat cards:** as on the Today board.
- **Tabs:** all · core (أساسية) · compensation (تعويض) · scheduled.
- **Context buttons:** **Session reports · Session reviews · Homework**.
- **Columns:** student · teacher · session type · teacher attendance (state + time) · student attendance (state + time) · session status (+ datetime).
- **Filters:** student, teacher, session length, from/to time.
- **Optional columns:** session no., end time, report status, session link, date.

**Actions**
- **Header:** **Simplified version** (`/onlyadmin/sessions-lite`) · create · **Export to Excel** · **Session archive**.
- **Row:** edit · **activity log** · **monitor** (opens the room) · delete · **mark present** · **mark absent** · **cancel session**.
- **Bulk:** delete · mark present · mark absent · cancel.

**Form: 5 tabs**

| Tab | Field | Type | Req | Options / hint |
|---|---|---|---|---|
| Basic | Student | select | ✓ | "must be active, with a subscription and a weekly schedule" |
| | Subscription → Weekly schedule → **Day** (slot) → Teacher → Course | cascading selects | ✓ | day = "day per the available schedule", e.g. "Friday – 09:45 PM – 10:15 PM \| course \| teacher"; teachers "from the chosen schedule" |
| | **Default duration (min)** | number | ✓ | "auto from the subscription for the chosen course; editable" |
| | **Actual duration (min)** | number | – | "time the teacher actually spent" |
| Details | **Session creation date** | datetime | – | "**used to calculate salaries**" |
| | Session type | select | – | normal (حصة عادية) / group (حصة جماعية) — "very important to ensure students' attendance" |
| | **Teacher in / out · Student in / out** | time | – | "set in timezone Africa/Cairo" |
| | **Teacher approval** | select | – | approved / not approved / not set — "set automatically on creation" |
| | **Created by** | select | – | teacher / student / administration |
| | Session link | url | – | |
| | **Actual session timestamp** | datetime | – | "a fingerprint of each session; the 🚀 icon sets it" |
| Attendance & report | Student attendance · Teacher attendance | select | – | present · absent without excuse · **excused absence** · not recorded — "leave as is until the session completes" |
| | **Session status** | select | ✓ | scheduled · completed · absent without excuse · **at the administration's disposal** |
| | Report status | select | ✓ | sent / not sent |
| | Report | textarea | – | "sent by the teacher as notes to the administration, **not sent to the student**" |
| Notifications | 9 datetime fields: early reminder (student) · reminder (student) · attendance reminder (student) · absence notice (student) · reminder (teacher) · early reminder (teacher) · absence warning (teacher) · attendance reminder (teacher) · absence notice (teacher) | datetime | – | each reminder is individually scheduled and stamped |
| Compensation | "Is it a compensation session?" | toggle | – | |

#### SCHED-004 — Session activity log (سجل عمليات حصة) `/admin/sessions/{id}/activities`

The page exists today for sessions 19 and 20, but the crawl captured no rows. The content (actor, field-level before/after diff, **revert**) comes from P1.

#### SCHED-005 Session archive · SCHED-006 Simplified sessions

Reached from the sessions header. Not re-crawled; P1 lists the archive columns.

#### SCHED-007 — Trial sessions (الحصص التجريبية) `/admin/trial-sessions`

- **Header:** add · **Export to Excel**.
- **Filters:** student, course, teacher, teacher gender, status.
- **Optional columns:** duration, request date, paid to teacher, how did you hear.

| Field | Type | Req | Options / hint |
|---|---|---|---|
| Student | select | ✓ | any student |
| Student data | textarea (auto) | – | fills when a student is chosen |
| **Request source** | select | ✓ | website / app / **API** |
| Course | select | ✓ | |
| Number of students | number | ✓ | |
| Preferred teacher gender | select | ✓ | male / female / no preference |
| Duration (min) | number | ✓ | 1–180 |
| Session datetime | datetime | ✓ | |
| Teacher | select | – | "any available teacher, **or use the suggest button for the best match**" |
| Request date | date | ✓ | |
| Status | select | ✓ | scheduled / completed / cancelled |
| Request status | select | ✓ | default "under review"; other values UNKNOWN |
| Session link | text | ✓ | |
| Student attendance · Teacher attendance | select | ✓ | present / absent / session not started |
| **Paid to teacher?** | toggle | – | |
| **How did you hear about us?** | select | ✓ | Facebook · Google · YouTube · web search · referral · other |
| Did the student rate the trial? | toggle | – | |
| Notes | textarea | – | |

#### SCHED-008…014

These were not re-crawled today; P1 has their details:

- SCHED-008 Extra sessions
- SCHED-009 Session reports (5-point emoji scales)
- SCHED-010 Session reviews
- SCHED-011 Homework
- SCHED-012 Teacher availability
- SCHED-013 Teacher Zoom links
- SCHED-014 Jitsi classroom `/class/{uid}`

Today's evidence: the reports, reviews and homework buttons are on the sessions page.

#### SCHED-015 (new) — Postponement window

System setting **"Max postponement limit" (minutes, required)**: *"the student and the teacher can postpone a session before this time"*. Where students and teachers actually postpone (their panels) is UNKNOWN.

#### SCHED-016 (new) — Teacher-recorded student attendance

A flag: *"teacher can record the student's attendance directly from the teacher panel"*.

#### SCHED-017 (new) — Student-timezone display of slots

Slot times are entered and listed in the system timezone and shown back in the student's timezone.

### 2.5 Billing & finance

#### BILL-001 — Payment records (سجلات الدفع) `/admin/payment-records`

- **Columns:** customer name · **transaction number** · customer type · payment method · amount · currency · status · date. One row seen: *unregistered student*, Stripe, GBP 10.50, completed.
- **Filters:** method, customer type, status, currency.
- **Header:** add · **Traditional payment methods** (→ BILL-002).
- **Edit form:** customer type\* · transaction no. ("from the provider") · method\* · amount\* · currency\* · status\* · notes · payment date\*.

#### BILL-002 — Traditional payment methods (per country) — not re-crawled

From P1: country, enabled toggle, and a repeater of name / logo / rich-text instructions.

#### BILL-003 — Monthly student invoices / receipts — not re-crawled

From P1: auto number, 5% service fee, and a bulk "send unpaid-invoice notice". Today it is reachable as "Receipts" (الايصالات) from Students.

#### BILL-004 — Payment links (روابط الدفع) `/admin/payment-links`

- **Description:** "create a payment link dedicated to your student to collect fees manually".
- **Columns:** # · student (e.g. "unregistered student") · gateway · amount · **service fee** · status (paid) · **link (copy)**.
- **Filters:** gateway, status, from/to date.

| Tab | Field | Type | Req | Options / hint |
|---|---|---|---|---|
| User | User type | select | ✓ | registered student / **unregistered student** |
| Link subscription | (fields not rendered; UNKNOWN) | | | |
| Payment | Gateway | select | ✓ | PayPal / Stripe |
| | Currency | select (full ISO list) | ✓ | |
| | Amount | number | ✓ | |
| | **Enable 5% service fee** | toggle | – | "adds 5% to the amount" |
| Description | Description | textarea | – | |

#### BILL-005 — Donation records (سجلات التبرعات) `/admin/donation-records`

- **Columns:** record no. · amount · method · transaction no. · status · created.
- **Filter:** payment status.
- **Form:** amount\* · method\* · transaction no. · status\*.
- **Seen:** a Stripe PaymentIntent reference, completed.

#### BILL-006 — Expenses (المصروفات) `/admin/expenses`

- **Columns:** title · type · amount · created.
- **Filters:** type, currency.
- **Form:** title\* · type\* (options not rendered) · amount\* · currency\* (USD) · notes.
- **Seen row:** "teacher salary – {teacher} – receipt INV-20260310-…", type "salaries", USD 120 → salary receipts appear to post here (**PAY-013, PROBABLE**).
- Feeds the dashboard's "expenses this month" and "net profit this month".

#### BILL-007 — Student wallet

The student's **balance** field (see PEOPLE-001). Gated by the "balances" flag.

#### Gateways and payment switches (SYS-003)

System settings → Payment gateways: PayPal · Stripe · **local payment** · **activation code** · **required fees ("5% charged to students paying through the system")**.

- **PayPal:** mode (sandbox / production), client ID, secret, currency (USD, EUR, SAR, AED, GBP, CAD), locale.
- **Stripe:** public key, secret, **webhook secret**.

### 2.6 Payroll

#### PAY-001 — Monthly teacher salaries (رواتب المعلمين النشطين) `/admin/teacher-salaries`

- **Caveat on screen:** *"salaries for the current month; in the current version please review salaries manually to verify the number of paid sessions"*.
- **Default filter:** from the 1st of the month to today.
- **Columns:** teacher · completed sessions · student-absence sessions · compensation sessions · total hours · **salary in the teacher's currency** (EGP and USD side by side).
- **Optional columns:** excused sessions · paid extra sessions · paid trial sessions · absence sessions · reports sent · reports not sent · total deductions · total incentives.
- **Row:** view · **create receipt**.
- **Bulk:** create receipts.
- **Header:** **salary projections** · Excel export.

#### PAY-003…006, 008–010 — not re-crawled

From P1:

- PAY-003 per-course hourly rates (single and bulk)
- PAY-004 deductions
- PAY-005 incentives (fixed or %)
- PAY-006 salary receipts (pending / paid / cancelled, plus teacher acknowledgement)
- PAY-008 report-submission deductions
- PAY-009 fixed salary
- PAY-010 teacher balance

Today: the "Report deductions" (خصم التقارير) settings tab is present, but no fields were captured (UNKNOWN).

#### PAY-007 — Salary withdrawal requests (طلبات سحب الرواتب)

- **Filters:** status, teacher.
- **Form:** teacher\* ("choose a teacher with enough balance") · **amount (USD)\*** · status\* (default "under review") · notes.

#### PAY-011 (new) — Per-student teacher hourly rate

A flag. When it is on, the teacher's rate is set per student and the normal hourly-rate calculation stops.

#### PAY-013 (new, PROBABLE) — Salary receipts become expenses

See BILL-006.

### 2.7 Communication

#### COMM-001 — Messages (الرسائل) `/admin/conversations`

- **Description** (P1): "view, edit and delete all messages sent through the system".
- **Columns:** sender type · sender · receiver type · receiver · message.
- **Optional columns:** attachments, read count, created.
- **Filters:** sender type, receiver type, created from/to.
- **Seen row:** a student → "all" message.
- **Bulk:** delete.

#### COMM-002 — Chat groups (مجموعات المحادثة)

- **Form:** group name\* · group image · participants (repeater).
- **Filters:** created from/to.

#### COMM-003 — Notifications ("automatic") (الإشعارات التلقائية) `/admin/notifications`

- **Columns:** target type · target name · message · sent date.
- **Row:** view, delete.
- **Filter:** target type.
- **Seen:** an admin notification "new request in the request centre…".

| Field | Type | Req | Options |
|---|---|---|---|
| Target (الشخص المستهدف) | select | ✓ | system admin · multiple teachers · multiple students · specific student · specific teacher · specific parent · all students · all teachers · all parents · group |
| Message | textarea | ✓ | |
| **Channels** | checkbox | ✓ | **Email · WhatsApp** (COMM-009) |
| Status | select (read-only) | – | pending / sent / failed |
| Read | toggle (read-only) | – | |

#### COMM-004 — Automated notification templates

System settings → Alerts. Each template has an Arabic\* and English\* text and an "initial status" on/off switch (COMM-010).

| Template | Timing (from its hint) |
|---|---|
| Session reminder (student) | UNKNOWN |
| Early reminder (student) | 2 hours before |
| Lateness reminder (student) | 5 min after start |
| Absence notice (student) | after the session ends |
| Teacher-absent apology (to the student) | when the teacher is absent |
| Subscription renewal | when the subscription ends |
| Subscription nearing expiry | UNKNOWN threshold |
| Teacher session reminder | 30 min before |
| Teacher early reminder | 2 hours before |
| Teacher "session started 5 min ago" | +5 min |
| Teacher "session ended 5 min ago" | end +5 min |

**Notification preferences tab** (on/off switches): subscription offers · student schedule update · teacher schedule update · trial sessions · **teacher reminder to send the session report**.

#### COMM-005 — WhatsApp routing

- Settings → WhatsApp: linked number + repeater of **group name\* + group ID\*** ("your linked number must be a member of the group"). At least 6 rows are configured on the demo.
- Per-teacher custom group (PEOPLE-005).
- Per-schedule, per-course group (SCHED-001).

#### COMM-006…008

- Per-user preferences (the 7 student toggles).
- Per-session reminder timestamps (9 per session).
- In-app notification stream.

### 2.8 Learning

| ID | Module | Today's evidence |
|---|---|---|
| CATALOG-004 | Levels & sub-levels / topics | See §2.2. Subscriptions have a "student levels" tab ("add level for student", with completed topics). |
| CATALOG-006 | Qur'an chapters | See §2.2 (API sync). |
| CATALOG-007 | Educational content | List plus course filter; the form is UNKNOWN. |
| CERT-001 | Certificate templates (قوالب الشهادات) | Form: template title\*, short description, template image. List has no rows. |
| CERT-002 | Certificates (الشهادات) | **Type\*:** completion (اتمام) / appreciation (تقدير) / pride (اعتزاز) / custom templates. Student photo (≤ 2 MB), student\*, course\*, **completed session count (auto from student + course)**, message from administration. |
| RC-001 | Playlists (قوائم التشغيل) — recorded courses | **Filters:** publish status, content language, has discount. **Optional columns:** description, total hours, lesson count, discount. **Tabs:** basic · course details · content · terms & conditions · publishing. **Seen fields:** thumbnail\*, intro video, title\*, slug\*, description\*. The rest is from P1: code, hours, lessons, language, price, discount, AI content, T&C, certificate, app-only. |
| RC-002 | Playlist videos (فيديوهات قوائم التشغيل) | **Filters:** playlist, status, downloadable. **Form:** thumbnail\*, playlist\*, code\*, title\*, slug\*, **video type\***, video URL\*, **duration\***, **order\***, description; publishing tab. |
| RC-003…005 | RC subscriptions, comments, reviews | Not re-crawled (P1). |
| CONS-001 | Consultations (الاستشارات) | **Filters:** delivery mode, featured, status. **Fields:** cover image, service name\*, description\* (rich text), **price USD\***, **session length (min)\***, **booking validity (days)\*** ("e.g. must be used within 7 days of payment"), **participants\***, **delivery mode\*** (video call / live chat / email), status\* (available / archived), enabled, **featured**, **reschedulable**, **5% fee**, **responsible teachers\*** (multi). |
| CONS-002 | Consultation requests (طلبات الاستشارات) | **Header:** add · **Export report** · **Export teacher profit margins**. **Filters:** consultation, teacher, session status, student and teacher attendance, gateway, from/to. **Fields:** student name\*, email\*, WhatsApp\*, request ID, consultation\*, teacher\*, session link, session status\* (scheduled / completed / absent), student timezone, session datetime ("pick a teacher first to see available slots"), student attendance\* and teacher attendance\* (present / absent / not started), **request status\*** (under review / confirmed & time confirmed / completed / cancelled / **reschedule requested**), payment ID, amount paid, **gateway** (PayPal / Stripe / Manual / Zelle / InstaPay / Telda / PayMob). |

### 2.9 Marketing site

The public site is **disabled on the demo** (site status "system only"), so everything here is admin-side only.

#### CNT-009 — Site settings (إعدادات الموقع) `/admin/site-settings`

**Header links:** site settings · **URL redirects** · **site pages** · **advertisements**.

| Tab | Fields |
|---|---|
| Basic | Site name English\* · Site name Arabic\* · **primary colour\*** · logo (JPG/PNG) · favicon (ICO/PNG 16/32 px) · hero image · share image · **intro video (MP4)** · **site status\*** (live / under maintenance / beta / system only — CNT-010) · **custom Header code** · **custom ads code** · **site schema** |
| Content | About · privacy policy · terms & conditions · vision · mission · packages-page blurb (rich text) · footer blurb |
| Social | Facebook · X · WhatsApp · phone · Gmail · public-service email · info email · Instagram · Telegram · SoundCloud · YouTube · LinkedIn · TikTok · Snapchat — **each with its own enable toggle** |
| SEO | Address · site description ("appears in search results") · keywords |

#### Other content modules

| ID | Module | Evidence today |
|---|---|---|
| CNT-001 | Articles (المقالات) | **Filter:** status. **Header:** add · **view article categories**. **Tabs:** basic · content · attachments · SEO · schema. **Seen fields:** cover image, title\*, category\*, slug\*, short description\*, publish date\*, published, **views count**, **reactions count**. AI generation is from P1. |
| CNT-002 | Article categories | P1 only |
| CNT-003 | Video library (مكتبة الفيديوهات) | **Tabs:** video info · SEO · publishing. **Seen fields:** title\*, description, video\*, cover\*. |
| CNT-004 | FAQs (الأسئلة الشائعة) | **Tabs:** Arabic · English · settings. **Seen fields:** question (ar)\*, answer (ar)\*. **Filter:** active only. |
| CNT-005 | Student reviews / testimonials (آراء طلابنا / شهادات الطلاب) | **Form:** student name\*, star count\*, review type\* (P1: text / audio / video). |
| CNT-006…008 | Site pages, advertisements, redirects | Header links only; P1 only |

### 2.10 Platform

| ID | Module | Evidence today |
|---|---|---|
| PEOPLE-008 | Users | See §2.1. |
| RBAC-001…010 | Roles & permissions (الادوار والصلاحيات) | **List:** title · guard · permission count · updated. **Form:** title\*, guard name, "select all", then **tabs Resources (846) · Pages (5) · Widgets (5)**. Each of the 71 resources has 12 verbs (view, view all, create, update, restore, restore all, replicate, reorder, delete, delete all, force delete, force delete any); `role` has 6. **Pages:** quick translate, themes, 2FA, login 2FA, system status. **Widgets:** 4 stats widgets + student stats. |
| SYS-001 | System settings (إعدادات النظام) | **General:** max postponement limit\* (min), system language\* (ar/en, "used for messages to the supervisor"), supervisor email\*, supervisor WhatsApp\*, system timezone\*. Then report deductions (fields UNKNOWN), payment gateways, alerts, subscriptions & offers (fields UNKNOWN), notification preferences, developer settings, external services. |
| SYS-002 | Feature flags (developer settings) — 37 | levels (paid) · file uploads/CDN (paid) · URL redirects · **AI assistant** · payment links (paid) · verified certificates · incentives & deductions · general supervision · family accounts · parents · free sessions for subscribers · homework · session reports · internal chat (paid) · recorded courses ("sell recorded courses") · articles · per-country pricing · Excel export (paid) · consultations · Olovix internal (paid) · study groups · balances ("add balance to the student's account") · **per-student teacher rate** · donations · automatic notifications · **teacher records attendance** · **AI reports** · contracts · subscription archive · session archive · invoices & receipts · report deductions · fixed teacher salary ("paid a fixed monthly salary") · student registration waiting list · payment receipt records ("payment receipts will be saved") · Zoom API · public links; plus developer notes |
| INT-* | External services tab | Zoom (account ID, API key, secret) · Olovix (UID, device UID) · WhatsApp (number, groups) · Google OAuth (client ID, secret) · reCAPTCHA site key · **Gemini API key** · PayPal · Stripe · mail (mailer, from address\*, from name\*) · TinyMCE licence · kMeet API key · IP-API token · Exchange-rate API key. All are entered in the UI. |
| SYS-004 | System status (حالة النظام) | Version 18.5, licence status "licensed", PHP 8.5.8, Laravel 10.50.2, env `local`, debug **on**. **Actions:** clear cache · **manually reconcile subscriptions** · **notify teachers of the monthly evaluation**. Vendor support widget. |
| SYS-005 | Themes (القوالب) | Primary colour + templates Default (light / dark) · Dracula (no light mode) · Nord · Sunset. |
| SYS-006 | File uploads (رفع الملفات) | **List** + bulk delete. **Form:** file name\*, file\*. |
| AUTH-003 | Two-factor authentication | Page "Secure your account". Mechanism UNKNOWN. |
| AUTH-015 | Profile (الملف الشخصي) | name\*, email\*, new password. |
| DASH-001…007 | Dashboard | Greeting + logout; **cards:** total students, new this month, growth %; all / active / expired subscriptions; revenue this month ("from completed payment records"), expenses this month, **net profit**; sessions this month, today, total ever (table + archive); "student statistics" charts with an age-group selector. Sidebar badges show live counts. |

### 2.11 Panels outside the admin

| Panel | Evidence today | Contents |
|---|---|---|
| Teacher `/teacher/login` | Filament login: email\*, password\*, remember me. No reset link. | UNKNOWN |
| Parent `/parent/login` | Same as the teacher login. | UNKNOWN |
| Student `/student/login` | Custom page: "Email or phone number"\*, password\*, remember me, **Forgot password** (`/student/password/forgot`), **Google** sign-in (`/student/auth/google`), **Sign up** (`/student/proregister`). Hidden fields timezone, device type, IP, favourite language. | UNKNOWN beyond the login page (P1 documented the registration and OTP-reset forms) |

No demo credentials are published for these three panels.

---

## 3. Key business behaviours visible from forms and hints

1. **Account type decides everything downstream.**
   - Every student is **individual (فرد)** or **family (عائلة)**.
   - Family accounts group *family-type* students and name one **payer** (PEOPLE-002).
   - Individual subscriptions list only individual-type students.
   - Weekly schedules branch into individual / family / **group**.
   - Students have a separate **age group** (minor…) derived from date of birth.

2. **A subscription is a bundle**, not one course:
   - several courses, each with its own teacher, package and session length
   - payment metadata on the record itself: method, status, number, prepaid or postpaid, normal or monthly system
   - auto-renew and auto-invoice toggles
   - a recalculation button that derives totals from the packages

   The paid amount can be edited and **drives renewal pricing**.

3. **Consumption accounting.**
   - "Sessions attended" is system-computed ("don't change manually").
   - Extra sessions taken during a grace period are counted and **deducted from the next month**.
   - Progress % shows on the subscription, schedule and Today lists.
   - Allowed suspension days are snapshotted from the package's "allowed freeze days". Packages also have "max package days".

4. **Package pricing.**
   - base price in USD, plus an optional hourly price and discount %
   - **per-country price overrides in local currency** (EGP, SAR seen)
   - popular / visible / active flags
   - individual or group type

5. **Weekly schedule → sessions.**
   - Slots are day(s) + course + teacher + start/end, stored in the system timezone and shown in the student's timezone.
   - Stopping a schedule stops future generation.
   - Generation is operator-triggered from the Today board (all of today, or a date range). Whether it also runs automatically is still UNKNOWN.
   - Bulk operations: bulk change, activate/deactivate, restore, **delete and move sessions**.

6. **Two-sided attendance.**
   - Student and teacher attendance are separate, each present / absent without excuse / **excused** / not recorded, with in/out times.
   - Session status is separate from attendance and includes **"at the administration's disposal"**.
   - Admins bulk-mark present / absent / cancel.
   - A flag lets teachers record student attendance.
   - Attendance does not appear to auto-complete a session (§1.3 #19).

7. **Compensation, postponement, extra and trial sessions** all live in the session records (tabs core / compensation). A global limit sets how long before a session students and teachers may postpone it.

8. **Teacher pay.**
   - monthly salary per teacher in the teacher's own currency, from completed / absent / compensation / excused / extra / trial sessions and reports sent or not sent, plus incentives and minus deductions
   - receipts created one at a time or in bulk, which appear to be posted to expenses
   - a teacher **balance**, drawn on by **withdrawal requests in USD**
   - 11 payout methods tuned to Egypt and the Gulf
   - alternatives: fixed monthly salary, or per-student rates (flags)
   - the on-screen warning to verify salaries manually

9. **Money flows.**
   - manual payment records, including for unregistered payers
   - payment links (PayPal / Stripe, optional 5% fee)
   - donations
   - expenses
   - student wallet balance
   - activation / renewal / discount codes
   - The dashboard computes revenue from *completed* payment records only, and net profit = revenue − expenses.

10. **Notifications.**
    - 11 timed templates (−2 h, −30 min, +5 min, after the end), each in Arabic and English with its own on/off state
    - 9 reminder timestamps stored on each session
    - manual messages to 10 audience types by Email and/or WhatsApp
    - WhatsApp group routing per teacher and per schedule course

11. **Archives and deletion.**
    - Subscriptions and sessions have archive screens, and the dashboard counts "table + archive".
    - Subscriptions have "delete keeping records" (soft) and permanent delete.
    - Schedules have a "deleted" tab with restore.

12. **Student engagement.** XP points, 21 emoji tags ("star of the month", "proficient memoriser"), certificates with auto session count, and an honor board (P1).

13. **Everything is a switch.** 37 flags, 6 of them sold as paid add-ons. Integrations are configured in the UI, and the demo runs with debug on.

---

## 4. Still unobserved, and what would close each gap

| # | Gap | Why it matters | What would close it |
|---|---|---|---|
| U1 | **Teacher panel** contents | Teachers mark attendance, write reports, may postpone, see salary and balance, request withdrawals: half of daily operations | A teacher login on the demo (none published), or admin "Quick login" on a teacher (mutates demo state; needs the demo owner's consent), or our own licensed instance (§6: the vendor sells monthly access) |
| U2 | **Student panel** contents (custom Blade app) | Registration funnel, booking/trial intake, payments, wallet, homework, recorded courses, consultations are all student-facing | A student account: register one on our own instance via `/student/proregister`, or quick-login |
| U3 | **Parent panel** contents | What parents see (reports? invoices? attendance?) | A parent login on our own instance |
| U4 | Renewal page (SUB-002) and what happens to the old cycle | Core commercial flow | Press "renew" on a disposable subscription on our own instance |
| U5 | Session generation: result of "schedule all" / bulk range; whether a daily job exists | Shapes the engine | Run both on our own instance; watch the Today board across midnight for 2–3 days |
| U6 | Payroll arithmetic (weighting of each session class, report deductions, fixed-salary mode, projections screen) | Highest-risk calculation | Seed known sessions on our own instance, create receipts, compare the numbers; open "salary projections" |
| U7 | Payments: payment-link checkout, Stripe/PayPal webhooks, 5% fee application, wallet debits, code redemption | Money correctness | Sandbox keys on our own instance; pay a link; redeem each code type |
| U8 | Time-based jobs: 11 reminders, auto-renew, near-expiry, archive moves, monthly teacher evaluation, "manually reconcile subscriptions" | Automation claims in vendor marketing | Observe our own instance over at least a week with WhatsApp/email configured |
| U9 | "Delete and move sessions" (schedules), "bulk change", "at the administration's disposal" status semantics | Data integrity | Run each on disposable data |
| U10 | ~29 hidden screens not re-crawled today (homework, groups, invoices, extra sessions, session reports/reviews, teacher rates/deductions/incentives/salary receipts, contracts, honor board, payment methods, level upgrades, categories, site pages, ads, redirects, RC-*, archives, student reports, sessions-lite) | Confirm P1 fields are still current in 18.5 | Re-run the same read-only crawl against the Phase-1 URL list |
| U11 | Lazily loaded / conditional parts: settings tabs "Report deductions" and "Subscriptions & offers"; payment-link "Link subscription" tab; expense types; activity-log rows; dashboard charts; educational-content form | Missing fields | Click each tab in a live browser (read-only), then re-extract |
| U12 | Public marketing site (disabled on the demo) and `/student/proregister` output | Funnel parity | Set site status to "live" on our own instance |
| U13 | **AI assistant**, AI reports, AI content generation behaviour | Advertised feature | Enter a Gemini key on our own instance and exercise the flag |
| U14 | **Desktop (Windows/Mac) and mobile apps** ("runs locally on students' devices") | Advertised in the full version | Ask the vendor or download the apps; nothing in the admin panel refers to them apart from the trial "request source = app" and the playlist "show in app only" flag |
| U15 | English and Spanish UI completeness | Localisation parity | Switch locale on the demo (read-only) |
| U16 | Security questions carried over from P1: whether `/class/{uid}` and quick-login URLs need authentication | Security | Request both from a clean, unauthenticated browser |

---

## 5. Gap table: TutorHamster vs etqan_tutor

**What has been built so far:**

- **Plan 1:** a fork of Kaleem with django-tenants schema-per-academy, the Etqan staff console, subdomains, and `identity`. Identity covers:
  - a User with one role from admin / teacher / student / parent
  - minimal Student, Teacher and Parent profiles and a parent–child link
  - parent invite codes, child accounts
  - email login, email verification, password reset, change password, multiple emails
  - a Kaleem `register` endpoint that is still present
- **Plan 2:** academy sites:
  - Branding (bilingual name, logo, favicon, share image, primary and accent colour, contact details, 6 socials)
  - Landing content with section toggles
  - Testimonials, rich-text SitePages, Inquiries (contact / trial)
  - an Astro public site with sitemap, robots, canonical and JSON-LD
  - custom domains with on-demand TLS
  - branded emails
  - the dashboard served under `/app/` with runtime branding and a Website area

**Status legend:**

| Status | Meaning |
|---|---|
| **BUILT** | Exists in Plan 1 or Plan 2 |
| **V1-M3 … V1-M8** | In the v1 spec. Milestones per v1 §9: M3 People & catalogue (now Plan 3) · M4 Subscriptions & scheduling · M5 Sessions · M6 Billing · M7 Payroll · M8 Notifications |
| **NON-GOAL** | Listed as excluded in v1 §1.2, v1 §6.4 or academy-sites §1.2 |
| **NOT ADDRESSED** | Neither planned nor excluded |
| **PARTIAL** | A narrower version is built or planned; the difference is given in the note |

### 5.1 Access, identity, platform

| ID | TutorHamster feature | etqan_tutor status | Note |
|---|---|---|---|
| AUTH-001/004/005 | Admin, teacher and parent logins (separate panels) | **BUILT** | One login and one dashboard for all roles (Plan 1). Role-specific screens come in M3–M7. |
| AUTH-002 | Password reset | **BUILT** | Email reset for every role. TH has none for teachers or parents. |
| AUTH-006 | Login by email **or phone** | **PARTIAL** — email built; phone in v1 §4.2/§6.4 (M3) | `User` has no phone field yet |
| AUTH-007 | Google sign-in (students) | NOT ADDRESSED | |
| AUTH-008/009 | Student self-registration + enhanced onboarding funnel (age group, preferred days, hours/week, intro-call slot) | **NON-GOAL** (v1 §6.4 "no self-registration") | The Kaleem `register` endpoint still exists in the backend. The public site has an inquiry form (Plan 2). |
| LEAD-004 | Registration waiting list / approval or code | NON-GOAL (follows from AUTH-008) | |
| AUTH-010 | OTP password reset by phone or student UID | NOT ADDRESSED | |
| AUTH-011/012 | Impersonation ("quick login") and quick-login links | **NON-GOAL** (v1 §6.4 "view as" out) | v1 has admin **invite** (set-password link), M3 |
| AUTH-003 | Two-factor authentication | NOT ADDRESSED | |
| AUTH-014 | Languages ar / en / **es** | **PARTIAL** — ar/en built (dashboard, site, emails) | Spanish not addressed |
| AUTH-015 | Own profile | **BUILT** | `me`, change password, emails |
| RBAC-001…010 | Role editor, 71×12 permissions, page/widget permissions | **NON-GOAL** ("fine-grained permission editor") | 4 fixed roles, built |
| §5.1 P1 | Supervisor (مشرف) actor | NOT ADDRESSED | |
| SYS-002 / SYS-009 | 37 feature flags, paid add-on tiers | **NON-GOAL** ("feature-flag system") | |
| — | Multi-academy SaaS, per-academy subdomain and custom domain | **BUILT** (etqan only) | TH is one academy per install |
| SYS-001 | System settings (timezone, language, admin contact, postponement limit, templates, integrations) | **PARTIAL** — V1-M3 `AcademySettings` (timezone, currency, locale, horizon, consumption rules, reminder minutes, thresholds, notification switches) | No postponement limit, no editable templates, no UI integration keys |
| INT | Integration keys entered in the UI (Zoom, kMeet, Gemini, TinyMCE, IP-API, exchange rates, mail transport) | NOT ADDRESSED | Platform-level environment config. Per-academy sender *address* is a NON-GOAL (sites §1.2). |
| SYS-004 | System status + manual jobs (clear cache, reconcile subscriptions, notify monthly evaluation) | NOT ADDRESSED | The Etqan staff console is Django admin |
| SYS-005 | Themes (Default / Dracula / Nord / Sunset, dark mode) | **PARTIAL** — per-academy primary/accent colours built (Plan 2) | Named themes not addressed |
| SYS-006 | File library / CDN | NOT ADDRESSED | Uploads exist only for branding and site fields |
| SYS-007 | Quick translate / translation lines | NOT ADDRESSED | |
| SYS-008 / SCHED-004 | Activity log with field diff + **revert** | NOT ADDRESSED | |
| SYS-010 | AI assistant | **NON-GOAL** ("AI features") | |
| DASH-001…004 | Stat cards (students, subscriptions, revenue, sessions) | **V1** (§6.3 Admin Home: active students, active subscriptions, sessions today, missing reports, overdue invoices, revenue per currency) across M4–M6 | No growth %, no expenses / net profit |
| DASH-005 | Charts by age group / gender / country / account type / month | NOT ADDRESSED | |
| EXP-002/003 | Excel exports (subscriptions, sessions, trials, salaries, students…) | **PARTIAL** — v1 §6.3 "CSV export for admin" on all lists | |
| PANEL-008/009 | Desktop and mobile apps (vendor claim) | **NON-GOAL** ("mobile app") | Desktop not mentioned |

### 5.2 People

| ID | TutorHamster feature | etqan_tutor status | Note |
|---|---|---|---|
| PEOPLE-001 | Student record (photo, DOB, gender, country, timezone, language, status, password) | **V1-M3** (a minimal `StudentProfile` already exists from Kaleem) | v1 statuses: active / paused / inactive. TH adds **pending, trial, in progress**. |
| PEOPLE-001 | Account type individual/family, age group, nationality (Arab/Foreign), alias email, postal code, device/IP | NOT ADDRESSED (family itself is a NON-GOAL) | |
| PEOPLE-001 | Student tags, **XP points** | NOT ADDRESSED | |
| PEOPLE-001 / BILL-007 | Student **wallet balance** | **NON-GOAL** ("wallets") | |
| PEOPLE-001 / COMM-006 | Per-student notification preferences (7 toggles) | NOT ADDRESSED | v1 has per-academy switches only |
| PEOPLE-001 | Bulk convert active/inactive; export | PARTIAL — CSV export in v1 | Bulk status change not specified |
| PEOPLE-002 | **Family accounts** with payer | **NON-GOAL** ("family accounts") | v1 approximates the payer: invoice payer = first guardian (§5.4) |
| PEOPLE-003 | Study groups | **NON-GOAL** ("group sessions") | |
| PEOPLE-004 | Parents + children linkage | **PARTIAL** — `ParentProfile` + parent–child link + invites **BUILT** (Plan 1); admin CRUD V1-M3 | No "registered on WhatsApp" flag |
| PEOPLE-005 | Teacher core (name, gender, contact, timezone, bio, active) | **V1-M3** (`TeacherProfile`: gender, bio, default meeting URL, pay currency) | |
| PEOPLE-005 | Payout method + details, current balance | NOT ADDRESSED | |
| PEOPLE-005 | CV, media, tags, rating, dashboard style, show-on-home | NOT ADDRESSED — except "teachers" section on the public site, planned in sites spec §3.2 for Plan 3 | |
| PEOPLE-006 | Employment contracts (AI-drafted) | NOT ADDRESSED (AI drafting = NON-GOAL) | |
| PEOPLE-007 | Honor board | NOT ADDRESSED | |
| PEOPLE-008 | Admin users with multiple roles | **PARTIAL** — first admin created with the academy (Plan 1); admin CRUD V1-M3 | Single role per account |

### 5.3 Catalogue

| ID | TutorHamster feature | etqan_tutor status | Note |
|---|---|---|---|
| CATALOG-001 | Courses (name, description, active) | **V1-M3** | bilingual name and description |
| CATALOG-001 | Course slug/SEO/schema, media, teachers list, lesson count, language, certificate & Qur'an toggles, AI texts | NOT ADDRESSED (AI = NON-GOAL) | The public courses section is planned for Plan 3 (sites §3.2) |
| CATALOG-002 | Course categories | NOT ADDRESSED | |
| CATALOG-003 | Packages: sessions/week, session minutes, term, price, currency, freeze days, active | **V1-M3** | v1 term unit is week/month; TH's is day/month |
| CATALOG-003 | **Per-country pricing** in local currency | NOT ADDRESSED | |
| CATALOG-003 | Discount %, hourly price, features, popular/visible, max package days, image | NOT ADDRESSED | |
| CATALOG-003 | Group package type | NON-GOAL (group sessions) | |
| CATALOG-004/005 | Levels, sub-levels/topics, upgrade requests; subscription "student levels" tab | **NON-GOAL** ("levels/curriculum progress") | |
| CATALOG-006 | Qur'an chapters (API sync) | NOT ADDRESSED | Nearest exclusion: curriculum |
| CATALOG-007 | Educational content files per course | NOT ADDRESSED | |

### 5.4 Subscriptions

| ID | TutorHamster feature | etqan_tutor status | Note |
|---|---|---|---|
| SUB-001 | Subscription (student + package + dates + price snapshot + status active/paused/expired) | **V1-M4** | |
| SUB-001 | **Multi-course / multi-teacher bundle** in one subscription | **NON-GOAL** by decision D8 (one course + one teacher) | |
| SUB-001 | Family subscription type | NON-GOAL | |
| SUB-001 | Progress %, sessions attended (computed) | **V1-M4/M5** | `sessions_used` is derived and never typed. TH also stores a manual field. |
| SUB-001 | Extra sessions beyond the package, deducted next month | **PARTIAL** — v1 shows negative remaining (§5.1) | No carry-over deduction |
| SUB-001 | Allowed suspension (freeze) days | **V1-M4** (`SubscriptionPause`, capped by the package's freeze days) | |
| SUB-001 | Payment method / status / number on the subscription | **PARTIAL** — V1-M6 invoices + payments | Payment is not stored on the subscription |
| SUB-006 | Prepaid/postpaid payment type; normal/monthly subscription system | NOT ADDRESSED | |
| SUB-001 | Auto-renew toggle | NOT ADDRESSED | v1 renew is an admin action |
| SUB-001 | Auto invoices toggle | **V1-M6** | Per academy (`auto_invoice_on_subscription`), not per subscription |
| SUB-007 | "Calculate and update" totals button | n/a — v1 derives totals | |
| SUB-008 | Roster tab (multi-student subscription) | NON-GOAL (family/group) | |
| SUB-002 | Renewal (row + bulk) | **V1-M4** (single) | Bulk renew not specified |
| SUB-003 | Subscription archive screen | **PARTIAL** — v1 `expired` status | No separate archive |
| SUB-004 | Soft delete "keeping records" vs permanent; restore | NOT ADDRESSED | v1 has `cancelled` status |
| SUB-005 | Activation / renewal / discount codes | NOT ADDRESSED | |

### 5.5 Scheduling & sessions

| ID | TutorHamster feature | etqan_tutor status | Note |
|---|---|---|---|
| SCHED-001 | Weekly slots (day, time, teacher, course) per subscription | **V1-M4** (`ScheduleSlot`) | Teacher and course come from the subscription |
| SCHED-001 | Separate schedule entity with status tabs, stop/restore, bulk change, **delete and move sessions**, multi-day rows | **PARTIAL** — v1 slot active flag; slot edits regenerate future sessions (§5.1) | No bulk ops or move |
| SCHED-001 | Expand calendar, download all schedules | **PARTIAL** — v1 week calendar on Sessions (§6.3) | No download |
| SCHED-001 / COMM-005 | WhatsApp group per schedule course | NON-GOAL (WhatsApp delivery) | |
| SCHED-017 | Show slot times in the student's timezone | NOT ADDRESSED | v1 stores academy-timezone wall clock; per-user timezone exists on `User` |
| SCHED-002 | Today board with per-slot state + generate | **V1-M4** | |
| SCHED-002 | Bulk generation for a date range | **V1-M4** ("Generate for range") | v1 also generates automatically daily; TH automation is UNKNOWN |
| SCHED-003 | Sessions list, filters, two-sided attendance, cancel, bulk present/absent/cancel | **V1-M5** | |
| SCHED-003 | **Excused absence** attendance value | **V1-M5** (`excused` + `excused_consumes_session`) | |
| SCHED-003 | Status "absent without excuse" / "at the administration's disposal" | NOT ADDRESSED | v1 statuses: scheduled / completed / cancelled |
| SCHED-003 | Teacher/student in-out times, actual duration, actual timestamp, teacher approval, created-by | NOT ADDRESSED | |
| SCHED-003 | Session creation date used for payroll | n/a — v1 payroll uses `occurs_on` | |
| SCHED-003 | Group session type, substitute teacher, supervisor attendance | NON-GOAL (group) / NOT ADDRESSED (substitute, supervisor) | |
| SCHED-003 / COMM-007 | 9 per-session reminder timestamps | **PARTIAL** — V1-M8 one reminder (`reminder_minutes_before`) with dedupe | |
| SCHED-003 | "Monitor" live room | NON-GOAL (built-in video) | |
| SCHED-003 | Compensation sessions (tab, flag, link) | NOT ADDRESSED | An admin can add a one-off session in v1 (M5), but it is not linked |
| SCHED-015 | Postponement by student/teacher within a time limit | NOT ADDRESSED | |
| SCHED-016 | Teacher records attendance (flag in TH) | **V1-M5** (teachers set attendance on own sessions, always on) | |
| SCHED-004 | Session activity log + revert | NOT ADDRESSED | |
| SCHED-005 | Session archive | NOT ADDRESSED | |
| SCHED-006 | Simplified sessions view | NOT ADDRESSED | |
| SCHED-007 | **Trial-session pipeline** (source, attribution, teacher-gender preference, suggest-teacher, outcome, paid-to-teacher, rated) | **NON-GOAL** ("a trial is just a one-off session") | Plan 2 **BUILT** the intake side: public "trial" inquiry (kind=trial) |
| SCHED-008 | Extra (out-of-package) sessions + "paid to teacher?" | **PARTIAL** — one-off sessions V1-M5 | No paid-to-teacher flag |
| SCHED-009 | Session reports (behaviour + participation 1–5, notes) | **V1-M5** (+ `visible_to_parent`) | TH hides reports from students |
| SCHED-010 | Session reviews | NOT ADDRESSED | |
| SCHED-011 | Homework | **NON-GOAL** | |
| SCHED-012 | Teacher availability | NOT ADDRESSED | |
| SCHED-013 | Teacher Zoom links / Zoom API | **PARTIAL** — V1-M3/M4 teacher default meeting URL + per-slot URL | No Zoom API |
| SCHED-014 | Jitsi classroom `/class/{uid}` | **NON-GOAL** (built-in video; D5 external link) | |

### 5.6 Billing & finance

| ID | TutorHamster feature | etqan_tutor status | Note |
|---|---|---|---|
| BILL-001 | Manual payment records | **V1-M6** (`Payment`: cash, bank transfer, InstaPay, Vodafone Cash, manual card, other) | Payments are tied to invoices; TH also records unregistered payers |
| BILL-002 | Per-country manual payment methods with instructions and logos | NOT ADDRESSED | |
| BILL-003 | Student invoices, auto number, statuses | **V1-M6** | |
| BILL-003 | 5% service fee | NOT ADDRESSED | |
| BILL-003 | Unpaid-invoice notice | **V1-M8** (`invoice.overdue`) | |
| BILL-004 | Payment links (PayPal/Stripe, 5% fee) | **NON-GOAL** ("online student payments") | |
| SYS-003 | Stripe / PayPal gateways, webhooks, activation-code payment | **NON-GOAL** | |
| BILL-005 | Donations | NOT ADDRESSED | |
| BILL-006 | Expenses | NOT ADDRESSED | |
| DASH-003 | Net profit | NOT ADDRESSED | v1 revenue per currency only |
| BILL-007 | Student wallet | **NON-GOAL** | |
| — | Multi-currency amounts | **V1** (integer minor units + currency; never summed across currencies) | TH also has an exchange-rate API: NOT ADDRESSED |

### 5.7 Payroll

| ID | TutorHamster feature | etqan_tutor status | Note |
|---|---|---|---|
| PAY-001 | Monthly salary board per teacher, teacher currency | **V1-M7** (payslips per month; pay currency per teacher) | |
| PAY-002 | Inputs: completed, student-absent, compensation, excused, paid extra, paid trial, reports sent/not | **PARTIAL** — V1-M7 completed sessions + `pay_teacher_for_student_absence` | Other classes not modelled |
| PAY-003 | Per-course hourly rates | **V1-M7** (`TeacherRate` with a course override) | Bulk assignment to many teachers not addressed |
| PAY-011 | Per-student rate | NOT ADDRESSED | |
| PAY-004/005 | Deductions and incentives | **V1-M7** (`PayAdjustment` bonus/deduction, fixed amount) | Percentage incentives not addressed |
| PAY-006 | Salary receipts (pending/paid/cancelled) | **V1-M7** (draft → issued → paid, frozen lines) | Teacher acknowledgement not addressed |
| PAY-007/010 | Teacher balance + withdrawal requests (USD) | NOT ADDRESSED | |
| PAY-008 | Report-submission deductions | NOT ADDRESSED | v1 only notifies (`report.missing`, M8) |
| PAY-009 | Fixed monthly salary mode | NOT ADDRESSED | |
| EXP-005 | Salary projections | NOT ADDRESSED | |
| PAY-013 | Receipts posted to expenses | NOT ADDRESSED | |
| PEOPLE-005 | Payout methods (11) + details | NOT ADDRESSED | |

### 5.8 Communication

| ID | TutorHamster feature | etqan_tutor status | Note |
|---|---|---|---|
| COMM-004 | Automated notifications (reminders, absences, renewal, near-expiry, report reminder) | **V1-M8** — 8 types: session reminder, student absent, subscription low, expired, invoice issued, invoice overdue, report missing, invite | TH has 11 timed templates. v1 lacks the early (−2 h), lateness (+5 min), teacher-absent apology, teacher start/end nudges and schedule-update notices. |
| COMM-004 | Templates editable in the UI (ar + en) | NOT ADDRESSED | v1 keeps templates in code |
| COMM-008 | In-app notifications | **V1-M8** | |
| — | Email delivery | **BUILT** (branded emails, Plan 2) / V1-M8 for notification types | |
| COMM-009 / COMM-005 | WhatsApp delivery, group routing | **NON-GOAL** (D9: designed for, deferred) | |
| COMM-003 | Manual broadcast composer to 10 audience types | NOT ADDRESSED | |
| COMM-006 | Per-user notification preferences | NOT ADDRESSED | |
| COMM-001/002 | Internal messaging + chat groups | **NON-GOAL** ("chat") | |

### 5.9 Learning & add-on commerce

| ID | TutorHamster feature | etqan_tutor status |
|---|---|---|
| CERT-001/002/003 | Certificate templates, issued certificates (4 types, auto session count) | **NON-GOAL** |
| EXP-001 | AI monthly student reports | **NON-GOAL** (AI) |
| RC-001…005 | Recorded courses: playlists, videos, subscriptions, comments, reviews | **NON-GOAL** |
| CONS-001…004 | Consultations: products, requests, slot picking, payments, profit-margin export | **NON-GOAL** |
| LEAD-003 | Request centre | NOT ADDRESSED (UNKNOWN in TH as well) |

### 5.10 Marketing site

| ID | TutorHamster feature | etqan_tutor status | Note |
|---|---|---|---|
| CNT-009 | Site name ar/en, primary colour, logo, favicon, hero image, share image, social links, address, description | **BUILT** (Branding + LandingContent, Plan 2) | 6 social networks vs TH's 14; accent colour extra |
| CNT-009 | About / privacy / terms / vision / mission texts | **BUILT** as rich-text SitePages + landing "about" | |
| CNT-009 | Intro video, packages-page blurb, footer blurb, keywords | NOT ADDRESSED | |
| CNT-009 | Custom header code / ads code injection | NOT ADDRESSED | |
| CNT-009 | Site schema / SEO | **BUILT** (JSON-LD, sitemap, robots, canonical, hreflang) | |
| CNT-010 | Site status (maintenance / beta / system-only) | NOT ADDRESSED | Etqan can only suspend a tenant |
| CNT-005 | Testimonials (stars, text) | **BUILT** | TH audio/video types not addressed |
| CNT-006 | Site pages | **BUILT** (rich text, SEO description) | GrapesJS page builder = **NON-GOAL** |
| CNT-001/002 | Articles + categories | **NON-GOAL** (sites §1.2 "blog/articles") | |
| CNT-003 | Video library | NOT ADDRESSED | |
| CNT-004 | FAQs (ar/en) | NOT ADDRESSED | Could be a SitePage |
| CNT-007 | Advertisements (general/discount, expiry) | NOT ADDRESSED | |
| CNT-008 | URL redirects | NOT ADDRESSED | |
| LEAD-001 | Contact requests | **BUILT** (Inquiry: name, email, phone, has WhatsApp, message, contact/trial, new/handled, throttled) | TH adds person type and country |
| — | Public courses / packages / teachers sections | **PLANNED** (sites §3.2 toggles; Plan 3 data) | |

### 5.11 Panels (non-admin)

| Panel | TutorHamster | etqan_tutor |
|---|---|---|
| Teacher | Separate Filament panel; contents UNKNOWN | **V1-M5/M7**: today/week with join link, attendance, report; session history; own payslips |
| Parent | Separate Filament panel; contents UNKNOWN | **V1-M5/M6**: children's upcoming sessions, attendance, progress, shared reports, invoices |
| Student | Custom app with registration, Google, OTP reset; contents UNKNOWN | **V1-M5/M6**: own sessions with join link, attendance, progress, invoices. Self-registration is a NON-GOAL. |

---

## 6. What the vendor sells

The vendor homepage promises "more than 50 advanced features". It lists 34 cards, and each one is mapped below to what the admin crawl found. "Seen" means seen in the admin panel, today or in P1.

| # | Advertised (Arabic → English) | Found in the admin panel | etqan status |
|---|---|---|---|
| V01 | Unlimited students and teachers | No limits seen; plan limits UNKNOWN | BUILT (no limits) |
| V02 | Flexible, customisable pricing | CATALOG-003 (hourly price, discount %, per-country prices), SUB-005 codes | PARTIAL (V1-M3 package price; no per-country pricing or codes) |
| V03 | Student subscription management — follow, renew and pause "automatically" | SUB-001/002, pause days, auto-renew toggle; the automation itself is UNKNOWN (U8) | V1-M4 (manual renew; automatic expiry) |
| V04 | Weekly schedules | SCHED-001 | V1-M4 |
| V05 | Automatic notifications (WhatsApp – email – app) | COMM-003/004 (Email + WhatsApp channels, in-app stream); push to a mobile app UNKNOWN | V1-M8 email + in-app; WhatsApp NON-GOAL |
| V06 | Session records with full archive | SCHED-003/005 | V1-M5 records; archive NOT ADDRESSED |
| V07 | Automatic trial-session management "without manual intervention" | SCHED-007 (request source website/app/API); automatic intake UNKNOWN | NON-GOAL (inquiry intake BUILT) |
| V08 | Smart WhatsApp session reminders | COMM-004/005/007 | NON-GOAL (WhatsApp) |
| V09 | Students, supervisors, parents, teachers with full permissions per category | PEOPLE-*, RBAC; supervisor panel UNKNOWN | PARTIAL (4 fixed roles) |
| V10 | Independent dashboard per user | 3 extra panel logins exist; contents UNKNOWN; teacher "dashboard style" field | V1 (role-driven screens) |
| V11 | Discount codes | SUB-005 (discount type) | NOT ADDRESSED |
| V12 | Detailed payment records | BILL-001 | V1-M6 |
| V13 | Financial operations (revenue and expenses) | BILL-006, DASH-003 | PARTIAL (revenue only) |
| V14 | Automatic teacher salary calculation "from sessions and subscriptions" | PAY-001 (with the "verify manually" caveat) | V1-M7 |
| V15 | Automatic attendance recording | In/out timestamps, teacher-attendance flag; automatic capture UNKNOWN (PROBABLE from room joins) | PARTIAL (manual attendance V1-M5) |
| V16 | Automatic student/teacher subscription status updates | "Manually reconcile subscriptions" action; job UNKNOWN | V1-M4 daily expiry job |
| V17 | Electronic payment links (Stripe, PayPal) | BILL-004 | NON-GOAL |
| V18 | Expenses | BILL-006 | NOT ADDRESSED |
| V19 | Study levels | CATALOG-004 | NON-GOAL |
| V20 | Curricula linked to levels and sessions | Levels → sub-levels → topics; student-level tab on subscriptions; link to sessions UNKNOWN | NON-GOAL |
| V21 | Completion and appreciation certificates | CERT-001/002 | NON-GOAL |
| V22 | Consultation requests | CONS-001/002 | NON-GOAL |
| V23 | Recorded courses | RC-001…005 | NON-GOAL |
| V24 | **AI assistant** "instant support and smart data analysis" | Flag "AI assistant" only; **no UI seen — UNKNOWN** | NON-GOAL |
| V25 | **Homework** — create, submit, grade | SCHED-011 seen in P1 at a hidden URL; today only as the "Homework" button on the sessions page and a flag; not re-crawled | NON-GOAL |
| V26 | Session reports | SCHED-009 | V1-M5 |
| V27 | Monthly teacher performance evaluation | System-status action "notify teachers of the monthly evaluation"; teacher rating field; an evaluation screen was **not seen — UNKNOWN** | NOT ADDRESSED |
| V28 | **AI monthly student reports** | EXP-001 (P1: generate action on student reports) + flag "AI reports"; not re-crawled today | NON-GOAL |
| V29 | Family management ("link several students to one parent") | PEOPLE-002 + PEOPLE-004 | PARTIAL (parent ↔ many children BUILT; family accounts NON-GOAL) |
| V30 | **Groups** | PEOPLE-003 seen in P1; today only indirect evidence (schedule type "group", filter, button); not re-crawled | NON-GOAL |
| V31 | Invoices | BILL-003 ("Receipts" button today) | V1-M6 |
| V32 | **Incentives** "reward teachers and students" | PAY-005 teacher incentives (P1); student rewards = XP / tags? — student reward mechanism **UNKNOWN** | PARTIAL (teacher bonus V1-M7) |
| V33 | Discounts | Package discount %, discount codes, teacher deductions — which one is meant is ambiguous | NOT ADDRESSED |
| V34 | Integrated education system | — | — |
| Plans | $40 / month, $100 / quarter, $370 / year, $800 lifetime self-hosted; limited free version; "free WhatsApp subscription", "10 professional mailboxes", data export, VIP support | SaaS billing is NOT observable in the admin panel | NON-GOAL (v1 D4: Etqan bills academies manually) |
| Apps | "Full version includes desktop (Windows & Mac) and mobile app, runs locally on students' devices" | **Not seen — UNKNOWN**; indirect hints only: trial source "app", playlist "show in app only" | NON-GOAL (mobile app) |

---

## 7. Scope options for the owner

Both options below assume Plan 1 and Plan 2 stay as built. Sizes are relative:

| Size | Rough meaning |
|---|---|
| **S** | about one v1 milestone's worth of work or less |
| **M** | about 1–2 milestones |
| **L** | about 3 milestones |
| **XL** | more than 3 milestones |

No technology choices are implied.

### Option A — keep the v1 spine and add the most valuable missing pieces

The v1 spine (M3–M9: people & catalogue → subscriptions & slots → sessions → invoices → payslips → notifications) already covers the three engines TutorHamster is built around. The table lists additions that the audit suggests matter most to daily use, with the evidence for each.

| # | Addition | Why, per the audit | Size | Removes a v1 non-goal? |
|---|---|---|---|---|
| A1 | **Trial-session pipeline**: record → assign teacher (gender preference) → outcome → convert to subscription; source and "how did you hear" attribution | TH gives trials their own sidebar module, flow, flag and notification. The vendor sells "automatic trial management". Plan 2 already collects `trial` inquiries, so the intake exists. | S–M | yes ("trial-session pipeline") |
| A2 | **Family accounts with a payer** (student account type individual/family) | "Account type" is a *required* field on every TH student and shapes subscriptions, schedules and billing. Enhanced registration sends minors to family accounts. Vendor card V29. | M | yes ("family accounts") |
| A3 | **Compensation (make-up) sessions + postponement window** | TH has a compensation tab and flag, a "compensation" sessions tab and payroll column, and a global postponement limit. The sessions page says compensation and postponement are core session records. | S–M | no |
| A4 | **WhatsApp as a notification channel** | TH's only manual channels are Email and WhatsApp; 11 templates; group routing; vendor cards V05/V08. v1 already designs a channel interface (D9). | M | yes ("WhatsApp delivery") |
| A5 | **More notification types** (−2 h early reminder, +5 min lateness, teacher-absent apology, schedule-changed) + templates editable per academy | TH has 11 timed, editable, bilingual templates against v1's 8 fixed ones | S | no |
| A6 | **Expenses + net-profit card** | Small CRUD; drives TH's dashboard net profit; vendor cards V13/V18 | S | no |
| A7 | **Per-country package pricing** | A flag and a repeater in TH; vendor card V02; relevant where one academy sells in several countries | S | no |
| A8 | **Session audit log** (who changed attendance or status, when; view only, no revert) | TH logs every session change with revert. This backs up payroll disputes, which v1 already treats as a risk (§8). | S | no |
| A9 | **Extra student statuses** (pending, trial) and **teacher payout details** (method + details) | Cheap fields that TH uses on its main lists (status tabs) and for payroll payouts | S | no |
| A10 | **Excused / paid-trial / paid-extra session classes in payroll** + **percentage incentives** | TH's payroll board columns; v1 pays completed sessions only | S | no |

The following were left out of Option A because the audit shows them as large, separate product lines or as add-ons in TutorHamster itself. Most are marked "(paid)" or sit behind their own flag.

- recorded courses
- consultations
- certificates
- levels / curriculum
- homework
- internal chat
- online gateways and payment links
- wallet
- AI
- the page builder
- the role editor
- feature flags
- desktop and mobile apps

### Option B — full-parity roadmap

The phases are ordered by dependency. Each builds on the one before unless noted.

| Phase | Contents (TutorHamster IDs) | Depends on | Size |
|---|---|---|---|
| **B0** | The v1 spine as specified (M3–M9) | Plan 1/2 | L (already planned) |
| **B1** | **Account model & access**: family accounts + payer, study groups, student statuses / tags / XP / nationality / age group, supervisor actor, role editor with resource×verb permissions, per-academy feature toggles (PEOPLE-001…004, 007, RBAC-*, SYS-002) | B0 people | L |
| **B2** | **Scheduling depth**: multi-course / multi-teacher subscriptions, group and family subscriptions + roster, weekly-schedule entity with bulk change / move / restore, compensation, postponement, extra and trial pipeline, teacher availability, session statuses and in/out times, activity log + revert, archives, simplified view, student-timezone display (SUB-001/003/004/006–008, SCHED-001/003–008/012/015/017) | B1 (families, groups) | XL |
| **B3** | **Money depth**: per-country pricing, discount / activation / renewal codes, per-country manual payment methods, wallet, donations, expenses + net profit, service fee, exchange rates, online gateways (Stripe / PayPal) + payment links + webhooks (CATALOG-003, SUB-005, BILL-002…007, SYS-003) | B0 billing; B1 (payer) | XL |
| **B4** | **Payroll depth**: per-student rates, % incentives, report deductions, fixed salary, teacher balance + withdrawals, receipt acknowledgement, projections, bulk rate assignment, receipts → expenses (PAY-002…013) | B2 session classes; B3 expenses | M |
| **B5** | **Communication**: WhatsApp (numbers, groups, per-teacher / per-course routing), 11+ editable bilingual templates with per-session reminder timestamps, manual broadcast composer, per-user preferences, internal chat + chat groups (COMM-001…010) | B0 notifications; B2 sessions | L |
| **B6** | **Learning**: levels / sub-levels / topics + upgrade requests + student levels on subscriptions, Qur'an chapters sync, educational content, homework, session reviews, certificates + templates, honor board (CATALOG-004…007, SCHED-010/011, CERT-*, PEOPLE-007) | B2 | L |
| **B7** | **Add-on commerce**: recorded courses (playlists, videos, enrolment, watch tracking, comments, reviews), consultations (products, slot booking, payments, reschedule, profit margins) (RC-*, CONS-*) | B3 gateways | XL |
| **B8** | **Marketing parity**: articles + categories, video library, FAQs, ads, redirects, testimonial media types, site status modes, custom code injection, extra socials, page builder (CNT-001…010) | Plan 2 | M (L with a page builder) |
| **B9** | **Platform extras**: 2FA, Google sign-in, phone + OTP login and reset, self-registration + enhanced funnel + waiting list, impersonation / quick-login links, named themes and dark mode, file library, system-status jobs, employment contracts, Spanish (AUTH-*, LEAD-004, SYS-004…007, PEOPLE-006) | B0 | M–L |
| **B10** | **AI**: content generation (courses, articles, SEO, contracts), AI monthly student reports, AI assistant (EXP-001, SYS-010) | B6 (reports need learning data) | M (scope UNKNOWN — U13) |
| **B11** | **Apps**: mobile and desktop apps (PANEL-008/009) | B2–B5 APIs | XL (scope UNKNOWN — U14) |

Before B2–B4 can be specified faithfully, gaps U1–U9 in §4 need closing: the panels, renewal, generation, payroll arithmetic, payments and timers. The cheapest single step that closes most of them is running our own licensed TutorHamster instance for a month, which the vendor sells.
