# Translation review: marketing (academy public site)

Agent 4 (translation reviewer), round 3, 2026-11-01. Follows `round-3/glossary.md`.

## Scope
- Reviewed every Arabic string a visitor sees. They all live in `marketing/src/lib/i18n.ts`
  (STRINGS.ar and the plural tables).
- A search of `src/components`, `src/pages`, `src/layouts` and the other `src/lib` files found no
  hard-coded Arabic.
- The site has no Spanish (`LANGS = ["ar", "en"]`).
- English was not reworded, except for the `packageLine` template (see #17).

## Changes
| # | File | Key / location | Before | After | Why |
|---|---|---|---|---|---|
| 1 | src/lib/i18n.ts | `ar.whatsapp` | لدي واتساب على هذا الرقم | هذا الرقم مسجّل على واتساب | "لدي واتساب" is a calque of "I have WhatsApp". The new wording is the natural way to say it. |
| 2 | src/lib/i18n.ts | `ar.sent` | تم استلام رسالتك، سنتواصل معك قريباً. | استلمنا رسالتك، وسنتواصل معك قريبًا. | Glossary §3: the comma run-on needs و. Tanween goes on the letter before the alif (§2.12). The active voice is warmer for visitors. |
| 3 | src/lib/i18n.ts | `ar.failed` | تعذر الإرسال، حاول مرة أخرى. | تعذّر الإرسال. حاول مرة أخرى. | Adds the shadda (§2.5). The comma joining two sentences becomes a full stop. |
| 4 | src/lib/i18n.ts | `ar.contactMethodRequired` | يرجى إدخال بريد إلكتروني أو رقم هاتف للتواصل معك. | أدخل بريدًا إلكترونيًا أو رقم هاتف لنتمكن من التواصل معك. | §2.2: no "يرجى". "للتواصل معك" didn't say who would make contact. |
| 5 | src/lib/i18n.ts | `ar.trialNote` | سيصل طلبك إلى الأكاديمية كطلب حصة تجريبية، وسيتواصلون معك لتحديد موعدها. | سيصل طلبك إلى الأكاديمية، وسيتواصل معك فريقها لتحديد موعد الحصة التجريبية. | "كطلب" is the English "as a …" calque. The plural "سيتواصلون" had no subject. |
| 6 | src/lib/i18n.ts | `ar.trialSent` | استلمنا طلب الحصة التجريبية، سنتواصل معك قريبًا لتحديد الموعد. | استلمنا طلب الحصة التجريبية، وسنتواصل معك قريبًا لتحديد الموعد. | Comma run-on, fixed with و (§3). |
| 7 | src/lib/i18n.ts | `ar.unavailableTitle` | الموقع غير متاح مؤقتاً | الموقع غير متاح مؤقتًا | Tanween spelling (§2.12). |
| 8 | src/lib/i18n.ts | `ar.unavailableBody` | يرجى المحاولة لاحقاً. | حاول مرة أخرى لاحقًا. | No "يرجى" (§2.2). Uses the standard "حاول مرة أخرى" and fixes the tanween. |
| 9 | src/lib/i18n.ts | `ar.poweredBy` | مدعوم من إتقان | يعمل بمنصة إتقان | "مدعوم من" is a literal "powered by" and reads as "sponsored by". |
| 10 | src/lib/i18n.ts | `ar.betaBanner` | نسخة تجريبية — هذا الموقع قيد الاختبار | نسخة تجريبية: هذا الموقع ما زال قيد الاختبار | Keep the em dash rare (§2.11). "ما زال" carries "still". |
| 11 | src/lib/i18n.ts | `ar.maintenanceTitle` | الموقع تحت الصيانة | الموقع قيد الصيانة | "تحت الصيانة" is a calque of "under maintenance". "قيد" is the standard form and matches "قيد الاختبار". |
| 12 | src/lib/i18n.ts | `ar.maintenanceBody` | سنعود قريباً. | سنعود قريبًا. | Tanween spelling (§2.12). |
| 13 | src/lib/i18n.ts | `ar.signInToBuy` | الشراء يحتاج إلى حساب: سجّل الدخول أو أنشئ حسابًا، وستعود إلى هذه الدورة. | لشراء الدورة تحتاج إلى حساب. سجّل الدخول أو أنشئ حسابًا، وسنعيدك إلى هذه الدورة مباشرة. | "الشراء يحتاج" gives "buying" a need, word for word from English. The new wording speaks to the visitor and promises the return. |
| 14 | src/lib/i18n.ts | `ar.consultFee` | قد تُضاف رسوم دفع عند الدفع. | قد تُضاف رسوم الدفع الإلكتروني عند إتمام الحجز. | "دفع … الدفع" repeated the same word, and the meaning was unclear. Uses the glossary term الدفع الإلكتروني. |
| 15 | src/lib/i18n.ts | `ar.validUntil` | ساري حتى {d} | العرض سارٍ حتى {d} | Grammar: the indefinite manqūṣ adjective is "سارٍ", not "ساري". With "العرض" it reads as a full phrase. |
| 16 | src/lib/i18n.ts | `ar.contactLead` | اترك بياناتك وسيتواصل معك فريقنا خلال يوم عمل لترتيب حصتك الأولى. | اترك بياناتك، وسيتواصل معك فريقنا خلال يوم عمل واحد لترتيب حصتك الأولى. | Adds a pause before the clause. "يوم عمل واحد" is the natural form of "one working day". |
| 17 | src/lib/i18n.ts + src/components/LiveCatalogue.astro | `ar.packageLine` / `en.packageLine`, new `packageLineText()` | {n} حصص في الأسبوع · {m} دقيقة | {n} في الأسبوع · {m}, where {n} and {m} are now full plural phrases | Glossary §3: "حصص" is wrong for 1, 2 and 11+ ("2 حصص", "1 حصص"), and "دقيقة" is wrong for 3–10. The new `SESSIONS` table and `minutesText` give "حصتان في الأسبوع · 45 دقيقة" and "3 حصص في الأسبوع · 5 دقائق". English gets the same fix for 1 ("1 lesson a week"). |
| 18 | src/lib/i18n.ts | `ar.carousel` | عرض متحرك | عرض شرائح | Screen-reader role description. "عرض شرائح" is the standard Arabic term for a slideshow. "عرض متحرك" means an animation. |
| 19 | src/lib/i18n.ts | `ar.goToSlide` | اعرض الشريحة {n} | عرض الشريحة {n} | Button label, so it takes the masdar (§2.1). It now matches الشريحة السابقة/التالية. |
| 20 | src/lib/i18n.ts | `ar.myDashboard` | لوحتي | لوحة التحكم | Glossary term for Dashboard. "لوحتي" ("my board") is ambiguous for a first-time visitor. |

**Total: 20 changes** (21 strings, because #17 also changes the English template).

## Reviewed and kept
- `consultMinutes` "{n} دقيقة": the glossary flags it, but it is **dead**. Nothing renders it,
  because every caller uses `minutesText()`. The key was left unchanged.
- These were all checked and are natural and correct, so they stay as they are:
  - navigation and footer;
  - eyebrows and titles (the "دورات مسجّلة بإتقان" brand pun is deliberate);
  - empty states (لا توجد … بعد.);
  - the plural tables `LESSONS`, `MINUTES` and `HOURS`;
  - `lengthText`;
  - `starsOf`, `slideOf`;
  - `phoneInvalid`;
  - `pageNotFoundBody`;
  - `free` ("مجانية", which agrees with الدورة).
- `modeEmail` "بالبريد الإلكتروني" was kept, as the existing test asserts. Its form is a little
  inconsistent with the other two modes, which are nouns, but it reads naturally after "·".

## Tests
- Updated:
  - `test/closed.test.ts` (maintenance title);
  - `test/components.test.ts` (contact-required and trial note; added an Arabic `packageLine`
    assertion);
  - `test/round3-m16.test.ts` (لوحة التحكم ×2).
- Added: `test/consultations.test.ts` › "words a package's weekly sessions with Arabic plurals",
  which covers 1, 2, 3 and 12, plus English 1.
- Run inside the `etqan_tutor-marketing-1` container with `--maxWorkers=1`. The six files
  `consultations`, `components`, `closed`, `round3-m16`, `round2-a2` and `carousel` all passed:
  **97 tests**. Biome check is clean on the touched files.
