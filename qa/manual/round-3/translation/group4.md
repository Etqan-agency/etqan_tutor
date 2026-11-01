# Translation review, group 4 (Agent 4)

Date: 2026-11-01. Files: consultations, billing, registration, certificates, finance, bundles, auth,
sessionActivity, reviews, twoFactor, studyGroups, apps, honour, common, appearance (ar + es).
Rules: `round-3/glossary.md`. Keys, `{{placeholders}}` and `<tags>` unchanged; JSON valid.

**197 strings changed** (177 Arabic, 20 Spanish). No changes were needed in `appearance`.

## Tests
- `src/locales/locales.test.ts`: 9/9 pass (`dc.sh exec -T dashboard npx vitest run … --maxWorkers=1`).
- I updated these tests to the new wording, and they pass:
  - `features/billing/InvoicesList.test.tsx` (مسؤول الدفع → المسؤول عن الدفع)
  - `features/billing/SubscriptionInvoices.test.tsx` (لا فواتير لهذا الاشتراك. → لا توجد فواتير لهذا الاشتراك.)
  - `features/billing/InvoicePage.test.tsx` (مستردة → مستردّة)
  - `routes/reset-password.test.tsx` (عيّن كلمة المرور → تعيين كلمة المرور)
- `src/qa-round3-m15.test.tsx` still passes (56/56).

## Not changed (on purpose)
- `certificates:child` and `reviews:child` "الابن/الابنة" break glossary §2.2 (no slash gender forms),
  but ETQAN-QA-1335 (`qa-round3-m15.test.tsx`) pins the same label across six files, and four of
  them belong to other groups (homework, scheduling, recorded, curriculum). If it changes, change all
  six at once together with that test, for example to "الابن".
- `es/finance:types.marketing` "Mercadeo": "Marketing" would match the English, and the locale test
  forbids Spanish strings that copy the English.
- The minute counts `consultations:minutes`, `consultations:book.minutes` and `sessionActivity:minutes`
  ("{{count}} دقيقة") have no plural set in English. Values are usually 15 minutes or more, where دقيقة
  is correct. Adding `_few` keys would change the key set, so I left them.

## Changes
| File | Key | Before | After | Why |
|---|---|---|---|---|
| ar/consultations.json | `statuses.confirmed` | تم التأكيد وتأكيد الموعد | مؤكَّد | Redundant phrase; status chip agrees with الطلب |
| ar/consultations.json | `statuses.reschedule_requested` | تم طلب إعادة الجدولة | طُلبت إعادة الجدولة | Internal passive, matches requests.actions.requestReschedule |
| ar/consultations.json | `statuses.cancelled` | ملغي | ملغى | Spelling (alif maqsura) |
| ar/consultations.json | `session.absent` | غياب | غائب | Glossary: absent = غائب |
| ar/consultations.json | `attendance.not_set` | لم يبدأ | لم يُسجَّل | Meaning was wrong (Not recorded, not 'not started') |
| ar/consultations.json | `products.tabHasErrors` | (فيه أخطاء) | (يحتوي على أخطاء) | Colloquial; standard phrasing |
| ar/consultations.json | `products.teachersHint` | تظهر هنا فقط أسماء المعلمين الذين فعّلوا «يقدم استشارات». فعّلها لمعلم آخر من صفحته في قائمة المعلمين. | تظهر هنا فقط أسماء المعلمين المفعَّل لهم «يقدّم استشارات». فعّله لمعلم آخر من صفحته في قائمة المعلمين. | Admin turns it on, not the teacher; label match with consultant.offers |
| ar/consultations.json | `products.deleteConfirm` | حذف هذه الاستشارة؟ لا يمكن التراجع. | حذف هذه الاستشارة؟ لا يمكن التراجع عن ذلك. | Glossary confirm body |
| ar/consultations.json | `products.fields.validityHint` | يجب استخدامها خلال هذا العدد من الأيام بعد الدفع. | يجب استخدام الحجز خلال هذا العدد من الأيام بعد الدفع. | Unclear pronoun |
| ar/consultations.json | `products.fields.reschedulable` | إمكانية إعادة الجدولة | قابلة لإعادة الجدولة | Checkbox label reads as a statement |
| ar/consultations.json | `consultant.offers` | يقدم استشارات | يقدّم استشارات | Shadda consistent with products.notOffering |
| ar/consultations.json | `requests.subtitle` | احجز الاستشارات وأكدها وتابعها. | حجز الاستشارات وتأكيدها ومتابعتها. | Admin page subtitle; masdar instead of imperative |
| ar/consultations.json | `requests.filters.selfBooked` | الحجز | طريقة الحجز | Filter label was ambiguous |
| ar/consultations.json | `requests.selfBooked` | إلكتروني | إلكترونيًا | Glossary online = إلكترونيًا; pairs with «عبر الإدارة» |
| ar/consultations.json | `dialog.fields.time` | الوقت (توقيت النظام) | الوقت (بتوقيت الأكاديمية) | EN says academy clock |
| ar/consultations.json | `dialog.pickTeacherFirst` | يرجى اختيار المعلم أولاً لعرض المواعيد المتاحة | اختر المعلم أولًا لعرض المواعيد المتاحة. | Glossary: no يرجى, tanween on letter before alif |
| ar/consultations.json | `dialog.slots.off` | إتاحة المعلمين متوقفة: اكتب الوقت بنفسك. | ميزة أوقات إتاحة المعلمين غير مفعّلة: اكتب الوقت بنفسك. | Literal/awkward; feature on/off wording |
| ar/consultations.json | `dialog.slots.remaining` | متبقٍ {{count}} | المتبقي: {{count}} | Awkward agreement with a number |
| ar/consultations.json | `dialog.slots.previous` | أيام سابقة | الأيام السابقة | Consistent with book.earlier |
| ar/consultations.json | `dialog.slots.next` | أيام لاحقة | الأيام التالية | Consistent with book.later |
| ar/consultations.json | `dialog.refunded` | مُسترد في الفوترة | مستردّ في الفواتير | Spelling; billing area is الفواتير |
| ar/consultations.json | `payment.hint` | لتيلدا وباي موب وما شابه، اختر «أخرى» واكتب الاسم في المرجع. | عند الدفع عبر تيلدا أو باي موب أو ما شابههما، اختر «أخرى» واكتب الاسم في المرجع. | Literal 'For Telda…' calque |
| ar/consultations.json | `payment.byName` | سجّل الدفعة باسم الشخص (لا بحساب الطالب) | تسجيل الدفعة باسم الشخص (وليس على حساب الطالب) | Checkbox label: masdar |
| ar/consultations.json | `payment.studentRefused` | تعذّر على الفوترة استخدام حساب الطالب. يمكنك تسجيل الدفعة باسم الشخص بدلًا من ذلك. | تعذّر استخدام حساب الطالب في الفواتير. يمكنك تسجيل الدفعة باسم الشخص بدلًا من ذلك. | Calque: billing as the subject |
| ar/consultations.json | `calendar.empty` | لا حجوزات هذا الأسبوع. | لا توجد حجوزات هذا الأسبوع. | Empty-state pattern |
| ar/consultations.json | `errors.not_delivered` | سجّل ما جرى في الجلسة أولًا. | سجّل حضور الجلسة أولًا. | Literal 'how it went'; the action is recording attendance |
| ar/consultations.json | `errors.too_many_pending` | حجوزات كثيرة بانتظار الدفع. ادفع أحدها أو انتظر 30 دقيقة. | لديك حجوزات كثيرة بانتظار الدفع. ادفع أحدها أو انتظر 30 دقيقة. | Sentence had no verb/subject |
| ar/consultations.json | `book.fee` | قد تُضاف رسوم دفع عند الدفع. | قد تُضاف رسوم معالجة الدفع عند إتمام الطلب. | Repetitive 'دفع عند الدفع' |
| ar/consultations.json | `book.self` | لي | لنفسي | Bare 'لي' reads oddly as an option |
| ar/consultations.json | `manage.noTime` | الإجابة بالبريد الإلكتروني | الرد عبر البريد الإلكتروني | More natural |
| ar/consultations.json | `manage.nextPaidReview` | تم الدفع. ستراجع الأكاديمية الحجز وتؤكد الموعد قريبًا، وتابع حالته من هذه الصفحة؛ احتفظ برابطها. | تم الدفع. ستراجع الأكاديمية الحجز وتؤكد الموعد قريبًا. تابع حالته من هذه الصفحة، واحتفظ برابطها. | Run-on sentence |
| ar/consultations.json | `manage.payTitle` | ادفع ثمن حجزك | ادفع قيمة حجزك | ثمن is for goods; قيمة for a booking |
| ar/consultations.json | `manage.sendReview` | أرسل التقييم | إرسال التقييم | Button masdar, matches manage.send |
| ar/consultations.json | `manage.reviewSent` | شكرًا لك. تقييمك بانتظار موافقة الأكاديمية. | شكرًا لك. تقييمك بانتظار مراجعة الأكاديمية. | Glossary: approve = قبول, avoid موافقة |
| ar/consultations.json | `reviews.approve` | اعتماد | قبول | Glossary: approve = قبول |
| ar/consultations.json | `reviews.statuses.approved` | معتمد | مقبول | Matches قبول |
| ar/consultations.json | `return.paidFor` | ما دفعت مقابله | ما دفعت ثمنه | More natural |
| ar/consultations.json | `margins.exportDetail` | تصدير التفاصيل CSV | تصدير التفاصيل (CSV) | Latin run punctuation |
| ar/consultations.json | `margins.columns.share` | حصة المعلم | نصيب المعلم | حصة means a session; matches products.fields.share |
| ar/consultations.json | `margins.excluded` | مستبعد: {{count}} (غير مدفوعة أو مستردة أو مرصودة في المحفظة، أو حُذفت دفعتها). | المستبعدة: {{count}} (غير مدفوعة، أو مستردّة، أو أُضيفت إلى الرصيد، أو حُذفت دفعتها). | Glossary: no محفظة, use رصيد; agreement |
| ar/consultations.json | `margins.estimate` | ≈ بعملة {{currency}} وفق أسعارك الحالية (تقدير، الأسعار بتاريخ {{asOf}}): المستلم {{amount}}، الرسوم {{fee}}، حصة المعلمين {{share}}، الهامش {{margin}}. | ≈ بعملة {{currency}} وفق أسعار الصرف الحالية لديك (تقدير، بأسعار {{asOf}}): المستلم {{amount}}، الرسوم {{fee}}، نصيب المعلمين {{share}}، الهامش {{margin}}. | 'rates' are exchange rates; حصة → نصيب |
| ar/billing.json | `list.empty` | لا فواتير هنا. | لا توجد فواتير هنا. | Empty-state pattern |
| ar/billing.json | `errors.dueBeforeIssue` | اجعل الاستحقاق في تاريخ الإصدار أو بعده. | اجعل تاريخ الاستحقاق في يوم الإصدار أو بعده. | Missing noun |
| ar/billing.json | `errors.overBalance` | هذا أكثر من الرصيد المتبقي. | هذا المبلغ أكبر من المتبقي على الفاتورة. | Glossary: balance due = المتبقي, not الرصيد |
| ar/billing.json | `columns.payer` | مسؤول الدفع | المسؤول عن الدفع | Consistent with invoice.payer |
| ar/billing.json | `invoice.openSubscription` | افتح الاشتراك | فتح الاشتراك | Link/button masdar |
| ar/billing.json | `subscription.none` | لا فواتير لهذا الاشتراك. | لا توجد فواتير لهذا الاشتراك. | Empty-state pattern |
| ar/billing.json | `form.payerOption.family` | {{name}} (دافع العائلة) | {{name}} (المسؤول عن الدفع في العائلة) | Literal calque |
| ar/billing.json | `form.alreadyInvoiced` | هذا الاشتراك له فاتورة بالفعل: {{invoices}}. أنشئ فاتورة أخرى فقط لرسوم إضافية. | هذا الاشتراك له فاتورة بالفعل: {{invoices}}. لا تُنشئ فاتورة أخرى إلا لرسوم إضافية. | Word order of 'only' |
| ar/billing.json | `void.body` | الفاتورة الملغاة لا تقبل دفعات ولا يمكن استعادتها. تبقى في القائمة للسجل. | الفاتورة الملغاة لا تقبل دفعات ولا يمكن استعادتها، وتبقى في القائمة للرجوع إليها. | Literal 'for the record' |
| ar/billing.json | `payments.refunded` | مستردة | مستردّة | Shadda (glossary spelling) |
| ar/billing.json | `payments.refundBody` | لن تُحتسب ضمن الفاتورة والإيرادات. لا تُعيد إتقان أي أموال. | لن تُحتسب بعد الآن في الفاتورة ولا في الإيرادات. لن تُعيد إتقان أي مبلغ. | Smoother, keeps meaning |
| ar/billing.json | `payments.none` | لا دفعات بعد. | لا توجد دفعات بعد. | Empty-state pattern |
| ar/billing.json | `payments.deleteBody` | فقط لدفعة سُجّلت خطأً. يتبعها رصيد الفاتورة وحالتها. | استخدم هذا فقط لدفعة سُجّلت بالخطأ. سيُحدَّث المتبقي على الفاتورة وحالتها تبعًا لذلك. | Literal 'follow'; glossary المتبقي |
| ar/billing.json | `payments.refundedOn` | استُردت في {{date}} | استُردّت في {{date}} | Shadda |
| ar/billing.json | `print.balanceDue` | المبلغ المستحق | المبلغ المتبقي | Glossary: balance due = المتبقي |
| ar/billing.json | `family.line` | الطالب: {{student}}، تستحق في {{date}} | للطالب {{student}}، تستحق في {{date}} | Natural 'For X' |
| ar/billing.json | `family.nothingDue` | لا شيء مستحق الآن. | لا توجد مبالغ مستحقة الآن. | Empty-state pattern |
| ar/billing.json | `home.seeOverdue` | اعرض الفواتير المتأخرة | عرض الفواتير المتأخرة | Link masdar |
| ar/billing.json | `records.deleteBody` | فقط للسجل الذي أُنشئ بالخطأ. لا يمكن التراجع عن ذلك. | استخدم هذا فقط لسجل أُنشئ بالخطأ. لا يمكن التراجع عن ذلك. | Fragment sentence |
| ar/billing.json | `records.status.refunded` | مسترد | مستردّ | Shadda |
| ar/billing.json | `records.status.credited` | محوَّلة إلى الرصيد | محوَّل إلى الرصيد | Agreement with masculine siblings (مكتمل، مستردّ) |
| ar/billing.json | `receipts.refunded` | مُسترد | مستردّ | Spelling consistency |
| ar/billing.json | `terms.note` | للمكتب فقط. لا يغيّر شيء هنا طريقة فوترة الاشتراك. | للإدارة فقط. لا يغيّر أي شيء هنا طريقة فوترة الاشتراك. | 'office' = the administration in this UI |
| ar/billing.json | `local.switchHint` | ترى الأسر طرق الدفع الخاصة بدولتها على الفاتورة غير المدفوعة، وتسجّل أنت مدفوعاتها يدويًا. | ترى العائلات طرق الدفع المتاحة في دولتها على الفاتورة غير المدفوعة، وتسجّل أنت مدفوعاتها يدويًا. | Glossary: العائلات not الأسر; الخاصة calque |
| ar/billing.json | `local.switchSaved` | تم تحديث الدفع المحلي. | تم تحديث إعداد الدفع المحلي. | It is the setting that changed |
| ar/billing.json | `local.dialogBody` | ترى الأسر الاسم والشعار وهذه التعليمات على فاتورتها. | ترى العائلات الاسم والشعار وهذه التعليمات على فواتيرها. | Glossary: العائلات |
| ar/billing.json | `local.deleteBody` | لن تراها الأسر على فواتيرها بعد الآن. | لن تراها العائلات على فواتيرها بعد الآن. | Glossary: العائلات |
| ar/billing.json | `local.errors.position` | أدخل عددًا صحيحًا من 0. | أدخل عددًا صحيحًا يساوي 0 أو أكثر. | Literal 'from 0' |
| ar/registration.json | `steps.preferences` | تفضيلات الدروس | تفضيلات الحصص | Glossary: live lessons = حصص |
| ar/registration.json | `who.parentHint` | وليّ أمر يسجّل من طفل إلى خمسة أطفال. | وليّ أمر يسجّل من ابن واحد إلى خمسة أبناء. | Glossary: children = الأبناء |
| ar/registration.json | `fields.teacherGender` | تفضيل المعلّم | تفضيل المعلم | Glossary: no shadda outside the gender choice |
| ar/registration.json | `fields.code` | رمز التسجيل (اختياري) | كود التسجيل (اختياري) | Glossary: redeemed code = كود |
| ar/registration.json | `fields.codeHint` | لديك رمز من الأكاديمية؟ أدخله لتتجاوز قائمة الانتظار. | لديك كود من الأكاديمية؟ أدخله لتتجاوز قائمة الانتظار. | Glossary: كود |
| ar/registration.json | `children.heading` | الأطفال | الأبناء | Glossary: الأبناء; matches review.children |
| ar/registration.json | `children.child` | الطفل {{n}} | الابن {{n}} | Glossary: الأبناء |
| ar/registration.json | `children.add` | إضافة طفل | إضافة ابن | Glossary: الأبناء |
| ar/registration.json | `children.remove` | إزالة الطفل {{n}} | إزالة الابن {{n}} | Glossary: الأبناء |
| ar/registration.json | `back` | السابق | رجوع | Glossary: Back = رجوع |
| ar/registration.json | `doneReview` | بعد تأكيد بريدك ستراجع الأكاديمية طلبك، وسنراسلك عند قبوله لتتمكن من تسجيل الدخول. | بعد تأكيد بريدك، ستراجع الأكاديمية طلبك، وسنراسلك عند قبوله لتتمكن من تسجيل الدخول. | Missing comma after the time clause |
| ar/registration.json | `closedBody` | لا تستقبل هذه الأكاديمية التسجيل عبر الإنترنت. يُرجى التواصل مع الأكاديمية. | لا تستقبل هذه الأكاديمية طلبات التسجيل عبر الإنترنت. تواصل مع الأكاديمية مباشرة. | Glossary: no يُرجى |
| ar/registration.json | `throttled` | طلبات تسجيل كثيرة. حاول مرة أخرى لاحقًا. | أُرسلت طلبات تسجيل كثيرة. حاول مرة أخرى لاحقًا. | Sentence had no verb |
| ar/registration.json | `failed` | تعذّر إرسال طلب تسجيلك. يُرجى المحاولة مرة أخرى. | تعذّر إرسال طلب تسجيلك. حاول مرة أخرى. | Glossary: no يُرجى; 'حاول مرة أخرى' |
| ar/registration.json | `errors.childTooOld` | يجب أن يكون عمر الطفل أقل من 18 عامًا. | يجب أن يكون عمر الابن أقل من 18 عامًا. | Glossary: الأبناء |
| ar/registration.json | `errors.genderRequired` | اختر ذكر أو أنثى. | اختر «ذكر» أو «أنثى». | Grammar: option names need quotes (else case is wrong) |
| ar/registration.json | `errors.childrenCount` | أضف من طفل إلى خمسة أطفال. | أضف من ابن واحد إلى خمسة أبناء. | Glossary: الأبناء |
| ar/registration.json | `errors.consentRequired` | يجب أن توافق للمتابعة. | يجب الموافقة للمتابعة. | More natural |
| ar/registration.json | `errors.dateOfBirthFuture` | تاريخ الميلاد لا يمكن أن يكون في المستقبل. | لا يمكن أن يكون تاريخ الميلاد في المستقبل. | Natural word order |
| ar/registration.json | `errors.codeInvalid` | رمز التسجيل غير صحيح أو منتهي الصلاحية. | كود التسجيل غير صحيح أو منتهي الصلاحية. | Glossary: كود |
| ar/registration.json | `admin.subtitle` | الأشخاص الذين سجّلوا عبر الإنترنت. وافق على المنتظرين أو ارفضهم. | الأشخاص الذين سجّلوا عبر الإنترنت. اقبل طلبات المنتظرين أو ارفضها. | Glossary: approve = قبول |
| ar/registration.json | `admin.detail.code` | رمز التسجيل | كود التسجيل | Glossary: كود |
| ar/registration.json | `admin.detail.teacherGender` | تفضيل المعلّم | تفضيل المعلم | Glossary spelling; matches fields.teacherGender |
| ar/registration.json | `admin.detail.gender` | النوع | الجنس | Consistent with fields.gender |
| ar/registration.json | `admin.approve` | موافقة | قبول | Glossary: approve = قبول |
| ar/registration.json | `admin.approved` | تمت الموافقة على التسجيل. | تم قبول التسجيل. | Glossary: قبول |
| ar/registration.json | `admin.waitingForEmail` | تصبح الموافقة متاحة بعد أن يؤكّد المسجِّل بريده الإلكتروني. | يصبح القبول متاحًا بعد أن يؤكّد المسجِّل بريده الإلكتروني. | Glossary: قبول |
| ar/registration.json | `admin.codes.nav` | رموز التسجيل | أكواد التسجيل | Glossary: كود |
| ar/registration.json | `admin.codes.title` | رموز التسجيل | أكواد التسجيل | Glossary: كود |
| ar/registration.json | `admin.codes.subtitle` | يتيح الرمز الصالح للمسجِّل تخطّي قائمة الانتظار. | يتيح الكود الصالح للمسجِّل تخطّي قائمة الانتظار. | Glossary: كود |
| ar/registration.json | `admin.codes.empty` | لا توجد رموز تسجيل بعد. | لا توجد أكواد تسجيل بعد. | Glossary: كود |
| ar/registration.json | `admin.codes.loadError` | تعذّر تحميل رموز التسجيل. | تعذّر تحميل أكواد التسجيل. | Glossary: كود |
| ar/registration.json | `admin.codes.add` | إضافة رمز | إضافة كود | Glossary names this key explicitly |
| ar/registration.json | `admin.codes.create` | إنشاء الرمز | إنشاء الكود | Glossary: كود |
| ar/registration.json | `admin.codes.code` | الرمز | الكود | Glossary: كود |
| ar/registration.json | `admin.codes.codeHint` | من 6 إلى 32 خانة: أحرف إنجليزية وأرقام وشَرطات (-) فقط. لا يفرّق الرمز بين الأحرف الكبيرة والصغيرة. | من 6 إلى 32 خانة: أحرف إنجليزية وأرقام وشَرطات (-) فقط. لا يفرّق الكود بين الأحرف الكبيرة والصغيرة. | Glossary: كود |
| ar/registration.json | `admin.codes.expiresHint` | بتوقيت الأكاديمية ({{zone}}). اتركه فارغًا ليبقى دون انتهاء. | بتوقيت الأكاديمية ({{zone}}). اتركه فارغًا إن لم يكن للكود تاريخ انتهاء. | Awkward phrasing |
| ar/registration.json | `admin.codes.never` | دون انتهاء | بلا تاريخ انتهاء | Clearer |
| ar/registration.json | `admin.codes.created` | تم إنشاء الرمز. | تم إنشاء الكود. | Glossary: كود |
| ar/registration.json | `admin.codes.deactivated` | تم إيقاف الرمز. | تم إيقاف الكود. | Glossary: كود |
| ar/registration.json | `admin.codes.errors.codeLength` | اجعل الرمز من 6 إلى 32 خانة. | اجعل الكود من 6 إلى 32 خانة. | Glossary: كود |
| ar/certificates.json | `templates.imageHint` | PNG أو JPEG أو WEBP حتى 5 ميغابايت. يُفضَّل تصميم بحجم A4 أفقي. | PNG أو JPEG أو WEBP، حتى 5 ميغابايت. يُفضَّل تصميم أفقي بحجم A4. | Punctuation; adjective order |
| ar/certificates.json | `print.verifyOn` | تحقق من هذه الشهادة على | تحقّق من صحة هذه الشهادة على | Shadda; clearer |
| ar/certificates.json | `verify.validHint` | أصدرت {{academy}} هذه الشهادة وهي صحيحة. | هذه الشهادة صحيحة، وصادرة عن {{academy}}. | Awkward verb-first with a name of unknown gender |
| ar/certificates.json | `verify.revokedHint` | أبطلت {{academy}} هذه الشهادة. | أبطلت الجهة المصدِرة ({{academy}}) هذه الشهادة. | Avoid verb agreement with a name of unknown gender |
| ar/certificates.json | `toast.courseOn` | أصبحت {{course}} تمنح شهادات. | أصبحت دورة «{{course}}» تمنح شهادات. | Verb agreed with a bare name; add noun + quotes |
| ar/certificates.json | `toast.courseOff` | لم تعد {{course}} تمنح شهادات. | لم تعد دورة «{{course}}» تمنح شهادات. | Same as courseOn |
| ar/certificates.json | `empty.filtered` | لا توجد شهادات تطابق هذه الفلاتر. | لا توجد شهادات تطابق عوامل التصفية هذه. | English loanword 'فلاتر'; UI term is التصفية |
| ar/certificates.json | `required.sessions` | أدخل رقمًا من 0 إلى 9999. | أدخل عددًا من 0 إلى 9999. | A count is عدد |
| ar/finance.json | `statuses.refunded` | مسترد | مستردّ | Shadda |
| ar/finance.json | `types.utilities` | مرافق | خدمات المرافق | Bare 'مرافق' means facilities |
| ar/finance.json | `donations.body` | هبة للأكاديمية. التبرعات ليست إيرادات. | مبلغ مُهدى للأكاديمية. لا تُحتسب التبرعات ضمن الإيرادات. | Literal and stiff |
| ar/finance.json | `dialog.settingsError` | تعذّر تحميل إعدادات الأكاديمية، فلا يمكن بدء هذا النموذج. | تعذّر تحميل إعدادات الأكاديمية، فلا يمكن فتح هذا النموذج. | Literal 'start a form' |
| ar/finance.json | `rates.dialogBody` | كم {{base}} تساوي وحدة واحدة من هذه العملة. | قيمة الوحدة الواحدة من هذه العملة بعملة {{base}}. | Question form without ؟ ; awkward |
| ar/finance.json | `rates.errors.rateInvalid` | أدخل رقمًا أكبر من صفر، بحد أقصى 10 أرقام قبل الفاصلة و10 بعدها، مثل 4.12. | أدخل رقمًا أكبر من صفر، بحد أقصى 10 أرقام قبل الفاصلة العشرية و10 بعدها، مثل 4.12. | Clarify decimal point |
| ar/bundles.json | `kind.group` | مجموعة | جماعية | Adjective like siblings; 'حزمة مجموعة' was ungrammatical |
| ar/bundles.json | `types.group` | مجموعة | جماعي | Adjective like فردي/عائلي |
| ar/bundles.json | `form.startsOn` | يبدأ | تاريخ البدء | Field label, not a verb |
| ar/bundles.json | `form.removeRow` | حذف الدورة {{n}} | إزالة الدورة {{n}} | Glossary: remove = إزالة |
| ar/bundles.json | `form.removeStudentRow` | حذف الطالب {{n}} | إزالة الطالب {{n}} | Glossary: remove = إزالة |
| ar/bundles.json | `members.earlier` | فترة سابقة | مدة سابقة | Glossary names this key: term = مدة |
| ar/bundles.json | `members.period` | الفترة | المدة | Glossary: term = مدة |
| ar/bundles.json | `actions.renewBody` | يُجدَّد كل عضو حالي، كلٌّ في اشتراكه الخاص. اترك التاريخ فارغًا ليبدأ كلٌّ منها عند نهاية فترته. | يُجدَّد اشتراك كل عضو حالي على حدة. اترك التاريخ فارغًا ليبدأ كل تجديد عند نهاية مدة اشتراكه. | Literal; pronoun mismatch; term = مدة |
| ar/bundles.json | `actions.cancelBody` | يُلغى كل عضو سارٍ، وكذلك أي تجديد لم يبدأ بعد. | تُلغى كل الاشتراكات السارية في الحزمة، وكذلك أي تجديد لم يبدأ بعد. | A member (person) is not cancelled; the subscription is |
| ar/bundles.json | `actions.archiveBody` | يُؤرشف كل عضو مع حصصه. | يُؤرشف كل اشتراك في الحزمة مع حصصه. | Same: subscription, not person |
| ar/bundles.json | `actions.restore` | استرجاع الحزمة | استعادة الحزمة | Glossary: restore = استعادة |
| ar/bundles.json | `actions.restoreBody` | يعود كل عضو مؤرشف. | يُستعاد كل اشتراك مؤرشف في الحزمة. | Literal 'comes back'; glossary استعادة |
| ar/bundles.json | `actions.addBody` | يحصل الطالب على دورة الحلقة ومعلمها وباقتها وسعرها ومواعيدها من اليوم الذي تختاره. | يحصل الطالب على دورة المجموعة ومعلمها وباقتها وسعرها ومواعيدها بدءًا من اليوم الذي تختاره. | Glossary: study group = المجموعة, not الحلقة |
| ar/auth.json | `notVerified` | لم يتم تأكيد بريدك الإلكتروني بعد. | لم يُؤكَّد بريدك الإلكتروني بعد. | Internal passive instead of لم يتم + masdar |
| ar/auth.json | `resendThrottled` | يرجى الانتظار قليلًا قبل طلب رسالة أخرى. | انتظر قليلًا قبل طلب رسالة أخرى. | Glossary names this key: no يرجى |
| ar/auth.json | `verified` | تم تأكيد البريد. سجّل الدخول، وإن كان تسجيلك ينتظر موافقة الأكاديمية فسنراسلك فور الموافقة عليه. | تم تأكيد البريد. سجّل الدخول، وإن كان تسجيلك ينتظر قبول الأكاديمية، فسنراسلك فور قبوله. | Glossary: approve = قبول |
| ar/auth.json | `requestNewLink` | اطلب رابطًا جديدًا | طلب رابط جديد | Button masdar |
| ar/auth.json | `goToSignIn` | اذهب إلى تسجيل الدخول | الانتقال إلى تسجيل الدخول | Button masdar |
| ar/auth.json | `signOutFailed` | تعذّر تسجيل الخروج. يُرجى المحاولة مرة أخرى. | تعذّر تسجيل الخروج. حاول مرة أخرى. | Glossary: no يُرجى |
| ar/auth.json | `sendResetLink` | إرسال رابط الإعادة | إرسال رابط إعادة التعيين | Truncated phrase |
| ar/auth.json | `resetPasswordTitle` | عيّن كلمة المرور | تعيين كلمة المرور | Title masdar |
| ar/auth.json | `passwordReset` | تم حفظ كلمة المرور — يمكنك الآن تسجيل الدخول. | تم حفظ كلمة المرور. يمكنك الآن تسجيل الدخول. | Glossary: keep em dash rare |
| ar/auth.json | `resetLinkInvalid` | الرابط غير صالح أو منتهي الصلاحية. يرجى طلب رابط جديد. | الرابط غير صالح أو منتهي الصلاحية. اطلب رابطًا جديدًا. | Glossary names this key: no يرجى |
| ar/auth.json | `studentEmpty` | لا توجد جلسات مجدولة بعد. | لا توجد حصص مجدولة بعد. | Glossary names this key: session = حصة |
| ar/auth.json | `connectionRetryNow` | أعد المحاولة الآن | حاول مرة أخرى الآن | Glossary: try again = حاول مرة أخرى |
| ar/sessionActivity.json | `withStudent` | {{when}} (عند الطالب: {{time}}) | {{when}} (بتوقيت الطالب: {{time}}) | It is the student's local time |
| ar/sessionActivity.json | `actions.restore` | استرجاع الحصة | استعادة الحصة | Glossary: restore = استعادة |
| ar/sessionActivity.json | `actions.unarchive` | استرجاعها من الأرشيف | استعادتها من الأرشيف | Glossary: استعادة |
| ar/sessionActivity.json | `actions.subscription_restored` | استُرجعت مع اشتراكها | استُعيدت مع اشتراكها | Glossary: استعادة |
| ar/sessionActivity.json | `fields.pays_teacher` | تدفع أجر المعلم | يُدفع للمعلم | Subject was unclear (the session doesn't pay) |
| ar/sessionActivity.json | `fields.starts_at` | البدء | وقت البدء | Field label needs the noun |
| ar/sessionActivity.json | `fields.actual_minutes` | الدقائق المُدرَّسة | دقائق التدريس الفعلية | Literal calque |
| ar/sessionActivity.json | `revert.body` | سيُلغى «{{action}}» الذي قام به {{actor}}. لا يمكن التراجع إذا تغيّرت الحصة بعده. | سيُلغى «{{action}}» الذي أجراه {{actor}}، وفق القواعد نفسها التي تنطبق على أي تغيير جديد. يُرفض التراجع إذا تغيّر شيء بعده. | Dropped half of the meaning; 'قام به' calque |
| ar/reviews.json | `nav.rate` | قيّم حصصك | تقييم الحصص | Glossary: menu labels are nouns |
| ar/reviews.json | `emptyFiltered` | لا توجد تقييمات تطابق هذه المرشحات. | لا توجد تقييمات تطابق عوامل التصفية هذه. | UI term is التصفية |
| ar/twoFactor.json | `throttled` | محاولات كثيرة، حاول لاحقًا. | محاولات كثيرة. حاول مرة أخرى لاحقًا. | Comma splice; glossary try-again wording |
| ar/twoFactor.json | `download` | تنزيل كملف نصي | تنزيل ملف نصي (.txt) | Calque 'as a text file' |
| ar/studyGroups.json | `addBody` | سمِّ المجموعة واختر طلابها. | اكتب اسم المجموعة واختر طلابها. | سمِّ is rare/stiff in UI |
| ar/studyGroups.json | `noMatches` | لا يمكن لأي طالب الانضمام: إما غير نشط أو في مجموعة أخرى. | لا يوجد طالب يمكن ضمّه: الطلاب الآخرون غير نشطين أو في مجموعات أخرى. | Broken agreement (إما without subject) |
| ar/studyGroups.json | `errors.nameTooLong` | لا يزيد الاسم على 120 حرفًا. | اجعل الاسم 120 حرفًا على الأكثر. | Statement, not an instruction |
| ar/studyGroups.json | `moreHint` | تظهر أول {{count}} نتيجة. اكتب الاسم للوصول إلى البقية. | تظهر أول النتائج فقط ({{count}}). اكتب الاسم للوصول إلى البقية. | Fixed noun after a variable number (wrong for 3–10) |
| ar/apps.json | `title` | ثبّت التطبيق | تثبيت التطبيق | Title masdar |
| ar/apps.json | `ios` | على iPhone أو iPad: اضغط زر المشاركة ثم «إضافة إلى الشاشة الرئيسية». | على iPhone أو iPad: اضغط زر «مشاركة»، ثم «إضافة إلى الشاشة الرئيسية». | Punctuation; quote the button |
| ar/apps.json | `iosGoogle` | داخل التطبيق المثبّت سجّل الدخول ببريدك الإلكتروني وكلمة المرور: قد لا يُبقيك تسجيل الدخول عبر Google متصلًا هناك. | في التطبيق المثبّت، سجّل الدخول ببريدك الإلكتروني وكلمة المرور، فقد لا تبقى مسجّلًا الدخول هناك إذا دخلت عبر Google. | Literal 'keep you signed in' |
| ar/apps.json | `push.iosInstall` | على iPhone أو iPad ثبّت التطبيق أولًا (انظر «ثبّت التطبيق»)، ثم فعّل الإشعارات من التطبيق المثبّت. | على iPhone أو iPad، ثبّت التطبيق أولًا (انظر «تثبيت التطبيق»)، ثم فعّل الإشعارات من التطبيق المثبّت. | Matches new title; comma |
| ar/apps.json | `push.denied` | الإشعارات محظورة لهذا الموقع. اسمح بها من إعدادات الموقع في متصفحك ثم عد إلى هنا. | الإشعارات محظورة لهذا الموقع. اسمح بها من إعدادات الموقع في متصفحك، ثم عُد إلى هنا. | Punctuation; spelling |
| ar/apps.json | `push.lastDelivered` | آخر تسليم {{when}} | آخر إشعار وصل: {{when}} | Literal 'delivery' |
| ar/apps.json | `push.never` | لم يُسلَّم شيء بعد | لم يصل أي إشعار بعد | Literal 'delivered' |
| ar/honour.json | `subtitle` | كرّم الطلاب المتميزين كل شهر. | تكريم الطلاب المتميزين كل شهر. | Page subtitle masdar |
| ar/honour.json | `emptyPublished` | لا أحد على لوحة الشرف بعد. | لا يوجد أحد على لوحة الشرف بعد. | Empty-state pattern |
| ar/honour.json | `loadFailed` | تعذر تحميل لوحة الشرف. | تعذّر تحميل لوحة الشرف. | Glossary: تعذّر with shadda |
| ar/common.json | `pager.page` | صفحة {{page}} من {{pages}} | الصفحة {{page}} من {{pages}} | Definite article |
| ar/common.json | `unsavedChanges` | لديك تغييرات غير محفوظة، هل تريد مغادرة الصفحة؟ | لديك تغييرات غير محفوظة. هل تريد مغادرة الصفحة رغم ذلك؟ | Comma splice; dropped 'anyway' |
| es/billing.json | `tabs.partial` | Pagadas en parte | Pagadas parcialmente | More natural |
| es/billing.json | `status.partial` | Pagada en parte | Pagada parcialmente | More natural |
| es/billing.json | `paymentStatus.partial` | Pagada en parte | Pagada parcialmente | More natural |
| es/billing.json | `columns.due` | Vence | Vencimiento | Column header noun |
| es/billing.json | `form.payerOption.guardian` | {{name}} (tutor legal) | {{name}} (padre o madre) | Glossary: parent/guardian = padre o madre |
| es/billing.json | `form.noStudentAccess` | Emitir una factura requiere permiso para ver estudiantes. Pide a un administrador de la academia que lo añada a tu rol. | Emitir una factura requiere permiso para ver estudiantes. Pide a un administrador de la academia que lo agregue a tu rol. | Glossary: agregar, not añadir |
| es/billing.json | `payments.refundDone` | Pago marcado como reembolsado | Pago marcado como reembolsado. | Toast punctuation like siblings |
| es/billing.json | `print.serviceFees` | Comisiones del servicio | Comisiones de servicio | Natural |
| es/billing.json | `home.title` | Dinero | Finanzas | Too literal for a dashboard card |
| es/registration.json | `steps.preferences` | Preferencias de clases | Preferencias de sesiones | Glossary: sesión, not clase |
| es/registration.json | `admin.detail.student` | Ficha del alumno | Ficha del estudiante | Glossary: estudiante, not alumno |
| es/registration.json | `doneReview` | Después de confirmar, la academia revisará tu solicitud y te escribirá cuando la apruebe para que puedas iniciar sesión. | Después de confirmar, la academia revisará tu solicitud y te escribirá cuando la apruebe, para que puedas iniciar sesión. | Punctuation |
| es/finance.json | `expenses.deleteBody` | Sale de las cifras de este mes. Esto no se puede deshacer. | Se quitará de las cifras de este mes. Esto no se puede deshacer. | Literal 'leaves' |
| es/finance.json | `donations.body` | Un regalo para la academia. Las donaciones no son ingresos. | Un aporte a la academia. Las donaciones no cuentan como ingresos. | Literal 'gift' |
| es/auth.json | `verified` | Correo verificado. Inicia sesión; si tu inscripción espera la aprobación de la academia, te escribiremos en cuanto la aprueben. | Correo verificado. Inicia sesión; si tu registro espera la aprobación de la academia, te escribiremos en cuanto lo aprueben. | Glossary: registro |
| es/auth.json | `connectionRetryNow` | Reintentar ahora | Intentar de nuevo ahora | Glossary: Intentar de nuevo |
| es/sessionActivity.json | `actions.pays_teacher` | Cambió si se le paga al profesor | Pago al profesor cambiado | Awkward literal phrasing |
| es/sessionActivity.json | `fields.pays_teacher` | Se le paga al profesor | Pago al profesor | Field label |
| es/reviews.json | `nav.rate` | Valorar clases | Valorar sesiones | Glossary: sesión, not clase |
| es/common.json | `back` | Volver | Atrás | Glossary: Back = Atrás |
