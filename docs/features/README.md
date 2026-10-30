---
title: "Feature reference"
---

How each feature works **today**: what it is for, its models, rules, API, screens, jobs and
settings, and where the code is. Each page was checked against the code, and where the code
and the original spec disagree, the page follows the code. Each page ends with *Design
history*, which links the specs and plans that shaped the feature.

New here? Start with the [developer guide](../guide/README.md).

Most features can be switched on or off per academy. See [Feature toggles](feature-toggles.md).

## Platform

| Page | Covers |
|---|---|
| [Tenancy](tenancy.md) | Academies, schemas, domains and custom domains, suspension, `for_each_academy` |
| [Feature toggles](feature-toggles.md) | The per-academy feature registry and how routes and screens honour it |
| [Academy settings](academy-settings.md) | Settings row, themes and appearance, languages and translations, system status |
| [Integrations](integrations.md) | `resolve(service)`, Etqan default vs academy-owned accounts, email/WhatsApp/Zoom/Stripe/AI providers |
| [Etqan billing](etqan-billing.md) | Metering Etqan's defaults, prices and allowances, Etqan's invoices to academies |
| [Private files](private-files.md) | Protected storage and authenticated file streaming |

## People and access

| Page | Covers |
|---|---|
| [People](people.md) | Users and roles, student/teacher/parent profiles, families, tags, invites |
| [Sign-in](sign-in.md) | Sessions and CSRF, login, two-factor, password reset, Google, quick login |
| [Roles & permissions](roles-permissions.md) | Staff roles, the permission-code registry, how views enforce it |
| [Registration](registration.md) | Self-registration, confirmation, waiting list, registration codes |
| [Employment contracts](employment.md) | Teacher and staff contracts with private files |

## Teaching operations

| Page | Covers |
|---|---|
| [Catalogue](catalogue.md) | Courses, packages, per-country prices |
| [Subscriptions](subscriptions.md) | Subscriptions, pauses, slots, renewals, the hourly scheduling job |
| [Sessions](sessions.md) | Session lifecycle, attendance, postponement, supervision, archives, activity log |
| [Scheduling tools](scheduling-tools.md) | Trials, teacher availability, study groups, bundles, weekly schedules |
| [Meetings](meetings.md) | Session video links: Zoom (own or Etqan pool), Jitsi, the host link |

## Money

| Page | Covers |
|---|---|
| [Billing](billing.md) | Invoices, payments, refunds, local payment methods. How money is represented |
| [Online payments](online-payments.md) | Gateways: own Stripe/PayPal keys, Stripe Connect, checkouts, webhooks, payment links |
| [Finance](finance.md) | Expenses, donations, net profit, exchange rates |
| [Wallet](wallet.md) | Student balances: top-ups, paying from the wallet, adjustments |
| [Vouchers](vouchers.md) | System codes: kinds, redemption, discounts |
| [Payroll](payroll.md) | Teacher rates, adjustments, fixed salaries, payslips, balances and payouts, projections |

## Learning

| Page | Covers |
|---|---|
| [Curriculum](curriculum.md) | Levels, topics, Qur'an chapters, student progress, upgrade requests |
| [Homework & content](homework-content.md) | Homework set and answered, educational content |
| [Reviews & honour board](reviews-honour.md) | Session reviews, the honour board |
| [Certificates](certificates.md) | Templates, issuing, printing, public verification |
| [Student reports](student-reports.md) | Monthly student reports with AI drafts |
| [Library](library.md) | The academy's public file library |

## Communication

| Page | Covers |
|---|---|
| [Notifications](notifications.md) | Notice catalogue, the scanner, recipients, preferences, templates, inbox |
| [Email, WhatsApp & broadcasts](email-whatsapp.md) | Delivery channels and broadcasts |
| [Chat](chat.md) | Conversations, groups, attachments, moderation |
| [Web push](web-push.md) | Push subscriptions and delivery |

## Sales add-ons

| Page | Covers |
|---|---|
| [Recorded courses](recorded-courses.md) | Selling recorded courses: store, enrolment, lessons, progress, codes, reviews |
| [Consultations](consultations.md) | Consultation products, slots, booking and payment, reports |

## Website, AI and apps

| Page | Covers |
|---|---|
| [Website](website.md) | The academy's public Astro site, branding, pages and page builder, inquiries |
| [Website content](website-content.md) | FAQs, advertisements, redirects, articles, videos |
| [AI](ai.md) | AI drafts: task registry, worker, token metering |
| [Apps](apps.md) | Installable web app (manifest, icons) and web push. Native apps on hold |
