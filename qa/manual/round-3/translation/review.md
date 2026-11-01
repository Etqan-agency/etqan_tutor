# Translation round 3: gate review (Agent 2)

Date: 2026-11-01. Reviewed: Agent 4's change logs `group1.md` (208), `group2.md` (177), `group3.md` (155),
`group4.md` (197) and `marketing.md` (20 changes, 21 strings), against `round-3/glossary.md`.

## Verdict: PASSED (with 5 follow-up bugs, 1 × P3 and 4 × P4)

The rewrite is good. The Arabic now reads as native product Arabic: masdar buttons, «تم + masdar» toasts,
«تعذّر …» errors, «لا توجد … بعد» empty states, internal passive instead of «سيتم», and no «يرجى»,
«الخاص بك», «بواسطة» or «بنجاح» left. Glossary terms are applied consistently, and meaning is accurate,
with several real meaning fixes (`consultations:attendance.not_set`, `people:field.payout_method`,
`consultations:dialog.fields.time`). None of the issues found blocks the pass. Each one is filed and
must be fixed under the round-3 "fix everything" rule.

## 1. Mechanical checks (all 737 dashboard rows)
- I parsed every change-log row with a script and compared it with the current JSON and the English
  source (`qa/manual/round-3/translation/`, script kept in the session scratchpad).
- **Result:** all 737 rows match the files exactly, and no key is missing.
- Every `ar/*.json` and `es/*.json` file is valid JSON.
- **Placeholders and tags:** no Arabic string has a `{{placeholder}}` the English lacks, and no `<tag>`
  differs.
  - The one difference is `scheduling:pauses.left_one`, which drops `{{count}}`. That is correct: count
    is 1, and the glossary prescribes this wording.
- A whole-tree scan of `ar/` finds 0 cases of each of these: يرجى، الرجاء، الخاص بك، بنجاح، سيتم،
  «ـاً»، استرجاع، بواسطة، هل أنت متأكد، التحضير، كوبون، الأسرة، رفع المستوى، أعد المحاولة، كورس.
  - «Etqan» appears only in key names.
  - «جلسة» appears only in consultations.
  - «معلّم» with shadda appears only in registration's gender choice, as the glossary allows.

## 2. Sample judged by reading (≈ 330 rows read in full, all groups; ≥ 80 judged in depth)
I read every Arabic row in groups 1–4, all the Spanish rows in groups 2–4 and part of group 1, and all 20
marketing changes, each against the English source.

| Group | Read | Verdict |
|---|---|---|
| 1 (website, gateways, chat, schedules, account, ai …) | 177 AR + 15 ES | Natural and accurate. The gateway "attention" set and the setup-guide tips are notably good. One issue: `website:setup.progress` (QA-1700). |
| 2 (scheduling, errors, vouchers, recorded, signIn …) | 153 AR + 24 ES | Good. The plural sets are complete (`bulk.archiveBody_*`, `pauses.left_*` follow the glossary). |
| 3 (payroll, people, integrations, notifications …) | 135 AR + 20 ES | Good. «طريقة الاستلام»، «قبول»، «غائب بعذر» and «مجمَّد» vs «موقوف مؤقتًا» are applied correctly. |
| 4 (consultations, billing, registration, auth …) | 177 AR + 20 ES | Good. Registration codes now use «كود» (redeemed) vs «رمز» (security), matching the glossary rule. Gives the ميغابايت spelling (QA-1701) and the throttled wording (QA-1704). |
| marketing | 20 | Good. The new `SESSIONS` plural table and `packageLineText` are correct for 1, 2, 3–10 and 11+. Two term changes weren't mirrored in the dashboard (QA-1702, QA-1703). |

Small stylistic notes. These are acceptable, so I didn't file them:
- `account:makePrimary` «تعيينه أساسيًا» has a pronoun with no antecedent in the button. It is clear
  in its row.
- `scheduling:session.startAsHost` «البدء كمضيف» and `website:inquiries.markHandled` «وضع علامة
  كمُعالَج» use «كـ». That is common, accepted UI Arabic.
- `registration:doneReview` moves its subject from «الأكاديمية» to «سنراسلك», which is consistent with
  `auth:verified`.
- `chat:attachments.tooMany` «{{count}} ملفات» is correct, because `MAX_FILES = 3`.

Spanish is consistent with §4 throughout: tú, «sesión», «recibo de pago» vs «nómina», «pausa»,
«pospuesta» and «padre o madre».

## 3. On screen (Arabic, `step.mjs`, 1440 and 375)
Screenshots are in `qa/manual/screens/r3/translation/`:

| Shot | Screen | Result |
|---|---|---|
| 01 / 15 | Admin home 1440 / 375 | OK. No overflow. «الفواتير المتأخرة: 92»، «المستحق (81):» |
| 02 | Students 1440 | OK. «موقوف مؤقتًا» tab (account status, per glossary) |
| 03 / 03b | Sessions / subscriptions 1440 | OK. The status chips agree in gender. |
| 04 / 16 | Invoices 1440 / 375 | OK. «المسؤول عن الدفع» fits the column and the phone card. Chips: مدفوعة جزئيًا، ملغاة. |
| 05 | Payslips 1440 | OK. «توقعات الرواتب»، «مسودة / صادر / مدفوع» |
| 06 | Academy settings 1440 | OK. «غياب الطالب بعذر» |
| 07 / 07b / 21 | Website setup guide 1440 / 375 | Text fits. The bidi of «‎+201001234567» and «https://» renders correctly (07b). The progress line has the plural bug **QA-1700**, and at 375 "24 / دقيقة تقريبًا" wraps. |
| 09 / 17 | Teacher home / my sessions 1440 / 375 | OK. «يُتاح زر «دخلت» قبل بدء الحصة بـ 15 دقيقة …» |
| 10 | Teacher balance 1440 | OK. The withdrawal status «ملغى» agrees with الطلب. |
| 11 / 12 / 18 | Student home / invoices 1440 / 375 | OK. «38 فاتورة»، «4 فواتير»، «فاتورة واحدة»: the plurals are right. «للطالب …، تستحق في …» |
| 13 / 19 / 22 | Public site home, courses, consultations | OK. «يعمل بمنصة إتقان» in the footer; «45 دقيقة · مكالمة فيديو» |
| 14 / 20 | Registration 1440 / 375 | OK. «وليّ أمر يسجّل من ابن واحد إلى خمسة أبناء.» fits the card. |

No leftover English (other than brand names and test data), no overflow, and no clipped label from the
longer strings.

## 4. Tests
- `dashboard src/locales/locales.test.ts --maxWorkers=1`: **9/9 pass**.
- Marketing `test/consultations`, `components`, `closed`, `round3-m16` (`--maxWorkers=1`): **4 files,
  82 tests pass**. The log reports `round2-a2` and `carousel` passing too; I didn't re-run them.
- `pnpm exec tsc --noEmit` (dashboard): **1 error, not from the translation work.**
  - The error is `src/features/billing/qa-m08-r3.test.tsx(295,33) TS2873 "This kind of expression is
    always falsy"` (`{"" || null}`).
  - It comes from an untracked M08 round-3 test file, so it belongs to M08. I flagged it here and
    didn't file it in the translation range.

## 5. Bugs filed (`qa/bug-register.md` § "--- Translation round 3 ---")
| ID | Sev | Summary |
|---|---|---|
| ETQAN-QA-1700 | P3 | `website.setup.progress` uses a fixed «{{minutes}} دقيقة», which is wrong for 1, 2 and 3–10. Pass the existing `website.setup.minutes` plural. |
| ETQAN-QA-1701 | P4 | «ميغابايت» (billing, certificates, content, homework, library) vs «ميجابايت» (chat, contracts, recorded, website). Groups 1 and 4 disagree. |
| ETQAN-QA-1702 | P4 | The dashboard status card says «تحت الصيانة»; the public site now says «قيد الصيانة». |
| ETQAN-QA-1703 | P4 | The dashboard hero slides say «عرض متحرك»; the public site now says «عرض شرائح». |
| ETQAN-QA-1704 | P4 | `twoFactor:throttled` lacks «جدًا», unlike `signIn` and `codeReset`, for the same English source. |

Glossary follow-up: add «ميجابايت» and «قيد الصيانة» to §1, so later edits keep them.

## 6. Retest of the follow-up bugs (Agent 2 gate, 2026-11-01)

All five are **VERIFIED**. Each was checked on screen in Arabic with `step.mjs` or Playwright, the
before/after shots were opened and looked at, and the tests were re-run inside the `dashboard`
container.

| ID | Result | On screen (after) | Shots in `qa/manual/screens/r3/translation/` |
|---|---|---|---|
| ETQAN-QA-1700 | VERIFIED | Setup guide: «الوقت المتبقي: 24 دقيقة تقريبًا» now comes from the `website.setup.minutes` plural. EN shows "about 24 min left". 1, 2 and 3–10 are covered by the unit test, because qa has 24 minutes left. | 1700-before-setup-ar-1440/-375, 1700-after-setup-ar-1440/-375, 1700-after-setup-en-1440 |
| ETQAN-QA-1701 | VERIFIED | Library upload «حتى 20 ميجابايت للملف الواحد.» (was ميغابايت), certificate template «حتى 5 ميجابايت». 0 «ميغابايت» left in `ar/`. | 1701-before-library-upload-ar-1440, 1701-after-library-upload-ar-1440, 1701-after-cert-template-ar-1440 |
| ETQAN-QA-1702 | VERIFIED | Site status card «قيد الصيانة» (was «تحت الصيانة»), same as marketing «الموقع قيد الصيانة». | 1702-before-status-ar-768, 1702-after-status-ar-1440 |
| ETQAN-QA-1703 | VERIFIED | Section «شرائح الغلاف», intro «… عرض شرائح», delete dialog «… من شرائح الغلاف في الصفحة الرئيسية.», hero tip quotes «شرائح الغلاف». 0 «متحرك» left. | 1703-before-slides-ar-1440, 1703-after-slides-ar-1440, 1703-after-delete-dialog-ar-1440 |
| ETQAN-QA-1704 | VERIFIED | Sign-in and code reset (429 stubbed in the browser, so no real lockout) both show «محاولات كثيرة. حاول مرة أخرى لاحقًا.», the same as `twoFactor:throttled`. | 1704-before-strings-register (a labelled card: no pre-fix screen existed), 1704-after-signin-throttled-ar-1440, 1704-after-codereset-throttled-ar-1440 |

**Tests:** `npx vitest run` with `--maxWorkers=1` in the dashboard container covered
`src/locales/locales.test.ts`, `src/locales/translation-r3.test.ts`,
`src/features/website/{SetupGuide,SiteSettingsForm,m13Round3,HeroSlidesManager}.test.tsx`.
**6 files and 47 tests pass.** The log is `qa/manual/round-3/logs/translation/gate/vitest.txt`. There
are only `act(...)` warnings from HeroSlidesManager, and no failures.

**Observation, not a blocker:** at 375 the setup guide progress line still wraps between «24» and
«دقيقة تقريبًا», as it did before. A `whitespace-nowrap` on the minutes phrase would keep the number with
its unit. It is cosmetic and outside 1700's expected result.

**Translation round 3 follow-ups: CLOSED.**
