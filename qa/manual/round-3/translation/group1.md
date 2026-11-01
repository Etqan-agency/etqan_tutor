# Translation review, group 1 (Agent 4, round 3)

Date: 2026-11-01. Rules: `qa/manual/round-3/glossary.md`.

Files: website, gateways, chat, schedules, broadcasts, studentReports, sessionClasses, ai, codeReset, signInGoogle, translations, account, contracts, locale, theme (`dashboard/src/locales/{ar,es}/`).

**Strings changed: 208** (Arabic 177, Spanish 31). Keys, placeholders and tags unchanged; English unchanged. `theme` and `locale` reviewed, no change needed.

## Tests

- Updated to the new wording: `qa-round3-m03.test.tsx` (ES sign-in settings name), `features/ai/AiDraftButton.test.tsx`, `features/gateways/ReturnPage.test.tsx` (2), `features/gateways/CheckoutsList.test.tsx`, `features/website/BrandingForm.test.tsx`.
- Kept on purpose: `studentReports:facts.status.at_disposal` stays «تحت التصرف» (asserted by ETQAN-QA-1509 in `qa-round3-m11.test.tsx`); ES `sessionClasses:tabs.regular` stays «Normal» (ETQAN-QA-261 wants the tab and the kind to match).
- Run in the dashboard container with `--maxWorkers=1`: `src/locales` (all), the copy suites above, and 25 Arabic-rendering component tests for these namespaces. All pass, except failures in files outside this group: `qa-round3-m02` (twoFactor «.txt»), `qa-round3-m05` (content), `locales/copy.test.ts` (auth sign-up line), `scheduling/qa-round3-m07` (scheduling undo dialog).

## Arabic

| File | Key | Before | After | Why |
|---|---|---|---|---|
| ar/contracts.json | `accepted` | PDF أو Word (.docx) أو صورة، حتى 10 ميجابايت | ⁦PDF⁩ أو ⁦Word (.docx)⁩ أو صورة، بحجم أقصى 10 ميجابايت | عزل النص اللاتيني وصياغة أوضح للحد |
| ar/account.json | `makePrimary` | تعيين كأساسي | تعيينه أساسيًا | تجنّب «كـ» المترجمة |
| ar/account.json | `makePrimaryTitle` | هل تجعل هذا بريدك الأساسي؟ | تعيين هذا البريد أساسيًا؟ | عنوان تأكيد بالمصدر (§2.7) |
| ar/account.json | `makePrimaryBody` | سيصبح {{email}} عنوان تسجيل الدخول الخاص بك. | سيصبح {{email}} عنوانك لتسجيل الدخول. | إزالة «الخاص بك» (§3) |
| ar/account.json | `removeBody` | ستتم إزالة {{email}} من حسابك. | سيُزال {{email}} من حسابك. | المبني للمجهول بدل «ستتم + مصدر» (§2.8) |
| ar/account.json | `resend` | إعادة إرسال التحقق | إعادة إرسال رابط التحقق | «إرسال التحقق» ناقصة المعنى |
| ar/account.json | `unverifiedBadge` | غير مُتحقَّق | غير مُتحقَّق منه | اسم المفعول يحتاج «منه» |
| ar/account.json | `resent` | إذا كان لا يزال بحاجة إلى تحقق، فهناك رابط جديد في الطريق. | إن لم يُتحقَّق من العنوان بعد، فسيصلك رابط جديد قريبًا. | صياغة حرفية «في الطريق» |
| ar/account.json | `throttled` | يرجى الانتظار لحظة قبل المحاولة مرة أخرى. | انتظر لحظة ثم حاول مرة أخرى. | بلا «يرجى» (§2.2) |
| ar/account.json | `genericError` | حدث خطأ ما. يرجى المحاولة مرة أخرى. | حدث خطأ ما. حاول مرة أخرى. | الصيغة العامة المعتمدة (§2.5) |
| ar/account.json | `myProfile` | ملفي | ملفي الشخصي | المصطلح المعتمد «الملف الشخصي» |
| ar/account.json | `nameTooLong` | الاسم طويل جدًا، الحد الأقصى 255 حرفًا. | الاسم طويل جدًا، فالحد الأقصى 255 حرفًا. | ربط الجملتين بشكل طبيعي |
| ar/translations.json | `keep` | احتفظ بهذه العناصر النائبة: {{list}} | أبقِ هذه المتغيرات كما هي: {{list}} | «العناصر النائبة» ترجمة حرفية؛ «المتغيرات» أوضح |
| ar/translations.json | `errors.unsafe` | استخدم نصًا عاديًا فقط: بلا أقواس زاوية، والعناصر النائبة بالشكل {{example}} فقط. | استخدم نصًا عاديًا فقط: بلا أقواس زاوية، واكتب المتغيرات بالشكل {{example}} فقط. | نفس المصطلح «المتغيرات» |
| ar/translations.json | `errors.placeholders` | احتفظ بالعناصر النائبة للنص الأصلي كما هي: {{list}}. | أبقِ متغيرات النص الأصلي كما هي تمامًا: {{list}}. | نفس المصطلح «المتغيرات» |
| ar/translations.json | `errors.noPlaceholders` | لا يحتوي النص الأصلي على عناصر نائبة: احذفها. | لا يحتوي النص الأصلي على متغيرات، فاحذفها. | نفس المصطلح وربط طبيعي |
| ar/signInGoogle.json | `subtitle` | اسمح للطلاب وأولياء الأمور بتسجيل الدخول بحساباتهم في Google، من خلال تطبيق Google الخاص بأكاديميتك. | اسمح للطلاب وأولياء الأمور بتسجيل الدخول بحساباتهم في Google، عبر تطبيق Google التابع لأكاديميتك. | إزالة «الخاص بـ» (§3) |
| ar/signInGoogle.json | `removeTitle` | إزالة المفتاح السري لـ Google؟ | إزالة مفتاح Google السري؟ | صياغة أقصر وأطبع من «لـ Google» |
| ar/signInGoogle.json | `removed` | تمت إزالة المفتاح السري لـ Google. | تمت إزالة مفتاح Google السري. | نفس صياغة العنوان |
| ar/codeReset.json | `check` | تحقق من الرمز | التحقق من الرمز | الأزرار بالمصدر (§2.1) |
| ar/codeReset.json | `resend` | أرسل رمزًا جديدًا | إرسال رمز جديد | الأزرار بالمصدر، مثل «إرسال الرمز» |
| ar/codeReset.json | `changeEmail` | استخدم بريدًا إلكترونيًا آخر | استخدام بريد إلكتروني آخر | الأزرار بالمصدر |
| ar/codeReset.json | `changePhone` | استخدم رقمًا آخر | استخدام رقم آخر | الأزرار بالمصدر |
| ar/codeReset.json | `done` | تمت إعادة تعيين كلمة المرور — يمكنك الآن تسجيل الدخول. | تمت إعادة تعيين كلمة المرور. يمكنك الآن تسجيل الدخول. | تقليل الشرطة الطويلة (§2.11) |
| ar/codeReset.json | `throttled` | محاولات كثيرة، حاول لاحقًا. | محاولات كثيرة جدًا. حاول مرة أخرى لاحقًا. | جملتان كاملتان بدل فاصلة |
| ar/ai.json | `button` | اكتب بالذكاء الاصطناعي | الكتابة بالذكاء الاصطناعي | الأزرار بالمصدر (§2.1) |
| ar/ai.json | `notSetUpForm` | «اكتب بالذكاء الاصطناعي» غير متاح بعد: فعّل الذكاء الاصطناعي من صفحة التكاملات. | «الكتابة بالذكاء الاصطناعي» غير متاحة بعد: فعّل الذكاء الاصطناعي من صفحة التكاملات. | مطابقة نص الزر الجديد |
| ar/ai.json | `instructionsHint` | مثلاً: أسلوب ودود، واذكر الحصة التجريبية المجانية. | مثلًا: أسلوب ودود، مع ذكر الحصة التجريبية المجانية. | تنوين الفتح قبل الألف (§2.12) وصياغة أسلس |
| ar/ai.json | `append` | إضافة في النهاية | إضافة إلى النهاية | حرف الجر الأنسب |
| ar/ai.json | `errors.provider_rejected` | رفض مزوّد الذكاء الاصطناعي مفتاح API الخاص بالأكاديمية. تحقّق منه في الإعدادات ← التكاملات. | رفض مزوّد الذكاء الاصطناعي مفتاح ⁦API⁩ المحفوظ للأكاديمية. تحقّق منه في الإعدادات ← التكاملات. | إزالة «الخاص بـ» وعزل اللاتيني |
| ar/ai.json | `errors.billing` | رفض مزوّد الذكاء الاصطناعي الطلب لأسباب تتعلق بالفوترة. تحقّق من الفوترة في حساب Claude. | رفض مزوّد الذكاء الاصطناعي الطلب لسبب يتعلق بالدفع. تحقّق من الفوترة في حسابك على Claude. | صياغة أطبع |
| ar/ai.json | `errors.busy` | خدمة الذكاء الاصطناعي مشغولة. حاول بعد دقيقة. | خدمة الذكاء الاصطناعي مشغولة. حاول مرة أخرى بعد دقيقة. | العبارة المعتمدة «حاول مرة أخرى» |
| ar/ai.json | `errors.timeout` | استغرق الذكاء الاصطناعي وقتاً طويلاً للرد. حاول مرة أخرى. | استغرق الذكاء الاصطناعي وقتًا طويلًا في الرد. حاول مرة أخرى. | تنوين الفتح قبل الألف (§2.12) |
| ar/ai.json | `errors.throttled` | طلبت مسودات كثيرة في هذه الساعة. حاول لاحقاً. | طلبت مسودات كثيرة خلال هذه الساعة. حاول مرة أخرى لاحقًا. | تنوين الفتح قبل الألف (§2.12) |
| ar/chat.json | `badge` | {{count}} رسائل غير مقروءة | غير المقروءة: {{count}} | العدد بلا صيغ جمع؛ صيغة محايدة تصح لكل الأعداد |
| ar/chat.json | `access.title` | المحادثة | المحادثات | المصطلح المعتمد «المحادثات» |
| ar/chat.json | `access.enabled` | يمكنه استخدام المحادثة | يمكنه استخدام المحادثات | المصطلح المعتمد |
| ar/chat.json | `access.enabledHint` | أوقفه لإزالة هذا الطالب من المحادثة. | أوقف هذا الخيار لإزالة الطالب من المحادثات. | «أوقفه» غامضة |
| ar/chat.json | `groups.dialog.imageHint` | PNG أو JPEG أو WEBP، حتى 2 ميغابايت. | PNG أو JPEG أو WEBP، حتى 2 ميجابايت. | توحيد كتابة «ميجابايت» |
| ar/chat.json | `groups.dialog.imageInvalid` | اختر صورة PNG أو JPEG أو WEBP لا يتجاوز حجمها 2 ميغابايت. | اختر صورة PNG أو JPEG أو WEBP لا يتجاوز حجمها 2 ميجابايت. | توحيد كتابة «ميجابايت» |
| ar/chat.json | `groups.dialog.imageClear` | لا تستخدم هذه الصورة | إلغاء اختيار الصورة | زر بصيغة المصدر بدل النهي |
| ar/chat.json | `attachments.tooMany` | يمكن أن تحمل الرسالة {{count}} ملفات على الأكثر. | يمكن إرفاق {{count}} ملفات بالرسالة كحد أقصى. | صياغة أطبع من «تحمل الرسالة» |
| ar/chat.json | `attachments.tooBig` | حجم {{name}} أكبر من 10 ميغابايت. | حجم {{name}} أكبر من 10 ميجابايت. | توحيد كتابة «ميجابايت» |
| ar/chat.json | `moderation.columns.sent` | أُرسلت | وقت الإرسال | عنوان عمود اسمي بدل فعل |
| ar/chat.json | `moderation.badRange` | يجب أن يكون تاريخ البداية قبل تاريخ النهاية أو مثله. | يجب ألا يكون تاريخ «من» بعد تاريخ «إلى». | أبسط وأوضح |
| ar/chat.json | `moderation.bodyRequired` | الرسالة التي بلا ملفات تحتاج إلى نص. | أضف نصًا، فالرسالة لا تحتوي على ملفات. | صياغة حرفية |
| ar/schedules.json | `subtitle` | الجدول الأسبوعي لكل اشتراك: أوقفه أو استأنفه، أو احذفه (ويمكن استرجاعه)، أو أسند حصصه إلى معلم بديل. | الجدول الأسبوعي لكل اشتراك: أوقفه أو استأنفه، أو احذفه (ويمكن استعادته)، أو أسند حصصه إلى معلم بديل. | «استعادة» لا «استرجاع» (§1) |
| ar/schedules.json | `kind.group` | مجموعة | جماعي | صفة متسقة مع فردي/عائلي |
| ar/schedules.json | `loadError` | تعذر تحميل الجداول. | تعذّر تحميل الجداول. | الشدة في «تعذّر» (§2.5) |
| ar/schedules.json | `calendar.subtitle` | أسبوع كل جدول نشط. لا تظهر هنا الإنابات ولا التأجيلات. | أسبوع كامل لكل الجداول النشطة. لا تظهر هنا الإنابات ولا التأجيلات. | «أسبوع كل جدول» حرفية |
| ar/schedules.json | `bulk.restore` | استرجاع | استعادة | «استعادة» لا «استرجاع» (§1) |
| ar/schedules.json | `bulk.substitute` | معلم بديل | تعيين معلم بديل | زر بصيغة المصدر |
| ar/schedules.json | `bulk.stopBody` | لن تُنشأ حصص جديدة. تُحذف الحصص القادمة التي لم يسجَّل فيها شيء. | لن تُنشأ حصص جديدة، وتُحذف الحصص القادمة التي لم يُسجَّل حضورها بعد. | «لم يسجَّل فيها شيء» حرفية |
| ar/schedules.json | `bulk.deleteBody` | تنتقل إلى تبويب المحذوفة ولا تُنشئ حصصًا. تُحذف الحصص القادمة التي لم يسجَّل فيها شيء. يمكنك استرجاعها. | تنتقل إلى تبويب «المحذوفة» ولا تُنشأ لها حصص، وتُحذف الحصص القادمة التي لم يُسجَّل حضورها بعد. يمكنك استعادتها لاحقًا. | «استعادة» وصياغة أطبع |
| ar/schedules.json | `teacher.body` | المعلم الجديد لكل جدول محدد. تنتقل إليه الحصص التي لم يسجَّل فيها شيء، وتبقى الإنابات. | المعلم الجديد لكل جدول محدد. تنتقل إليه الحصص التي لم يُسجَّل حضورها بعد، وتبقى الإنابات كما هي. | «لم يسجَّل فيها شيء» حرفية |
| ar/schedules.json | `substitute.body` | يدرّس المعلم البديل الحصص المولّدة في هذه التواريخ. تبقى الحصص المؤجلة والمضافة يدويًا مع معلمها. | يدرّس المعلم البديل الحصص المُنشأة تلقائيًا في هذه التواريخ، وتبقى الحصص المؤجلة والمضافة يدويًا مع معلمها. | «المولّدة» حرفية |
| ar/schedules.json | `card.changed` | تغيّر في {{date}} بواسطة {{name}} | غيّره {{name}} في {{date}} | بدل «بواسطة» (§3) |
| ar/schedules.json | `card.restore` | استرجاع الجدول | استعادة الجدول | «استعادة» لا «استرجاع» (§1) |
| ar/schedules.json | `card.restored` | تم استرجاع الجدول. | تمت استعادة الجدول. | «استعادة» لا «استرجاع» (§1) |
| ar/schedules.json | `card.removeBody` | تعود حصصها المولّدة إلى المعلم الأصلي. | تعود حصصها المُنشأة تلقائيًا إلى المعلم الأصلي. | «المولّدة» حرفية |
| ar/studentReports.json | `needsStudents` | يلزمك إذن عرض الطلاب لاختيار طالب هنا. | تحتاج إلى صلاحية عرض الطلاب لتختار طالبًا هنا. | المصطلح المعتمد «الصلاحيات» |
| ar/studentReports.json | `generatedAt` | تاريخ التوليد | تاريخ الإنشاء | «التوليد» حرفية |
| ar/studentReports.json | `exists` | لهذا الطالب تقرير لهذا الشهر بالفعل. | يوجد بالفعل تقرير لهذا الطالب عن هذا الشهر. | ترتيب كلمات أطبع |
| ar/studentReports.json | `openExisting` | افتح ذلك التقرير | فتح التقرير الموجود | زر بالمصدر وأوضح |
| ar/studentReports.json | `errors.bodyTooLong` | لا يتجاوز التقرير ١٠٬٠٠٠ حرف. | يجب ألا يتجاوز التقرير 10000 حرف. | أرقام غربية (§2.11) وصياغة كاملة |
| ar/studentReports.json | `facts.chooseStudent` | يرجى اختيار طالب أولًا. | اختر طالبًا أولًا. | بلا «يرجى» (§2.2) |
| ar/studentReports.json | `facts.subscriptionLine` | {{course}} · {{teacher}} · {{package}} · {{sessions}} حصة في الباقة | {{course}} · {{teacher}} · {{package}} · حصص الباقة: {{sessions}} | «{{sessions}} حصة» خطأ مع 3–10 |
| ar/studentReports.json | `facts.courseLine` | {{course}}: {{total}} حصة، حضر {{present}} | {{course}}: الحصص {{total}}، الحضور {{present}} | «{{total}} حصة» خطأ مع 3–10 |
| ar/studentReports.json | `facts.progressLine` | {{course}}: {{level}} · {{done}} من {{total}} موضوعًا | {{course}}: {{level}} · الموضوعات المنجزة: {{done}} من {{total}} | «موضوعًا» خطأ مع أغلب الأعداد |
| ar/studentReports.json | `facts.certificateKind.pride` | فخر | فخر واعتزاز | توحيد مع الشهادات |
| ar/studentReports.json | `facts.attendance.excused` | معتذر | غائب بعذر | المسرد (§1): لا «معتذر» |
| ar/studentReports.json | `facts.subscriptionStatus.paused` | موقوف مؤقتًا | مجمَّد | المسرد (§1): الاشتراك مجمَّد |
| ar/broadcasts.json | `subtitle` | اكتب رسالة واحدة لمجموعة من الأشخاص. تصل لكل منهم في التطبيق وبالبريد الإلكتروني. | اكتب رسالة واحدة لمجموعة من الأشخاص، فتصل إلى كل منهم في التطبيق وبالبريد الإلكتروني. | حرف الجر وربط الجملتين |
| ar/broadcasts.json | `counts.sent` | أُرسل {{n}} | أُرسلت: {{n}} | صيغة تسمية واضحة مع العدد |
| ar/broadcasts.json | `counts.failed` | فشل {{n}} | فشلت: {{n}} | صيغة تسمية واضحة مع العدد |
| ar/broadcasts.json | `counts.pending` | قيد الانتظار {{n}} | قيد الانتظار: {{n}} | صيغة تسمية واضحة مع العدد |
| ar/broadcasts.json | `audiences.teachers` | معلمون متعددون | عدة معلمين | «معلمون متعددون» حرفية |
| ar/broadcasts.json | `audiences.students` | طلاب متعددون | عدة طلاب | «طلاب متعددون» حرفية |
| ar/broadcasts.json | `composer.noMatches` | لا يوجد أحد مطابق. | لا توجد نتائج مطابقة. | «لا يوجد أحد مطابق» ركيكة |
| ar/broadcasts.json | `composer.noAccess` | لا يمكنك عرض هذه القائمة، لذا لا يمكنك الاختيار منها. | ليست لديك صلاحية عرض هذه القائمة، لذا لا يمكنك الاختيار منها. | المصطلح المعتمد «صلاحية» |
| ar/broadcasts.json | `detail.deleteBody` | حذف هذه الرسالة الجماعية؟ تختفي إشعاراتها من جرس الجميع. الرسائل المرسلة بالبريد تبقى مرسلة. | حذف هذه الرسالة الجماعية؟ ستختفي إشعاراتها من قائمة إشعارات الجميع، أما رسائل البريد الإلكتروني المُرسلة فتبقى كما هي. | «جرس الجميع» و«تبقى مرسلة» حرفيتان |
| ar/sessionClasses.json | `add.subscriptionSearch` | البحث باسم الطالب | ابحث باسم الطالب | حقول البحث بالأمر كبقية الواجهة |
| ar/sessionClasses.json | `add.timeHint` | بتوقيت الأكاديمية | حسب المنطقة الزمنية للأكاديمية | المسرد (§1): لا «التوقيت» |
| ar/sessionClasses.json | `add.minutesDefault` | اتركها فارغة للمدة المعتادة | اتركها فارغة لاستخدام المدة المعتادة | أوضح |
| ar/sessionClasses.json | `add.paysTeacher` | تُحتسب للمعلم | تُحتسب في راتب المعلم | «تُحتسب للمعلم» غامضة |
| ar/sessionClasses.json | `paysTeacher.label` | تُحتسب للمعلم | تُحتسب في راتب المعلم | «تُحتسب للمعلم» غامضة |
| ar/sessionClasses.json | `errors.required` | اختر واحدًا. | اختر خيارًا. | «اختر واحدًا» ناقصة |
| ar/gateways.json | `settings.subtitle` | اربط حساب Stripe أو PayPal الخاص بك ليتمكن أولياء الأمور من دفع الفواتير إلكترونيًا. | اربط حسابك في Stripe أو PayPal لتتمكن العائلات من دفع الفواتير إلكترونيًا. | إزالة «الخاص بك» و«العائلات» = families (§1) |
| ar/gateways.json | `return.paid` | تم الدفع بنجاح، شكرًا لك. | تم الدفع، شكرًا لك. | بلا «بنجاح» (§2.4) |
| ar/gateways.json | `return.processing` | لا تزال قيد المعالجة. قد يستغرق ذلك دقيقة. | لا تزال الدفعة قيد المعالجة. قد يستغرق ذلك دقيقة. | الفاعل غائب |
| ar/gateways.json | `checkouts.empty` | لا مدفوعات إلكترونية بعد. | لا توجد مدفوعات إلكترونية بعد. | صيغة الحالة الفارغة (§2.6) |
| ar/gateways.json | `checkouts.resolve` | تحديد كمُعالَجة | إغلاق المتابعة | «تحديد كمُعالَجة» حرفية؛ تقابل «تحتاج إلى متابعة» |
| ar/gateways.json | `checkouts.resolved` | حُدّدت كمُعالَجة | أُغلقت المتابعة. | نفس المصطلح |
| ar/gateways.json | `checkouts.resolveTitle` | تحديد كمُعالَجة؟ | إغلاق المتابعة؟ | نفس المصطلح |
| ar/gateways.json | `checkouts.resolveBody` | سيؤدي هذا إلى إخفاء علامة «تحتاج إلى متابعة» عن هذه الدفعة الإلكترونية، ولا يمكن التراجع عنه. | ستُزال علامة «تحتاج إلى متابعة» عن هذه الدفعة، ولا يمكن التراجع عن ذلك. | بدل «سيؤدي هذا إلى» |
| ar/gateways.json | `checkouts.emptyFiltered` | لا مدفوعات إلكترونية تطابق التصفية. | لا توجد مدفوعات إلكترونية تطابق عوامل التصفية. | صيغة الحالة الفارغة |
| ar/gateways.json | `attention.purpose_unknown` | لا شيء هنا يمكنه استقبال هذه الدفعة. | لا يوجد ما يمكن تسجيل هذه الدفعة عليه. | «لا شيء هنا يمكنه استقبال» حرفية |
| ar/gateways.json | `attention.provider_refunded` | استُرد المبلغ لدى مزوّد الدفع. حدّد الدفعة كمستردة ثم حدّدها كمُعالَجة. | استُرد المبلغ لدى مزوّد الدفع. سجّل الدفعة مستردّة، ثم أغلق المتابعة. | «حدّدها كمُعالَجة» حرفية؛ مطابقة زر الإغلاق |
| ar/gateways.json | `attention.provider_reversed` | عُكس الدفع لدى مزوّد الدفع (نزاع أو استرجاع). حدّد الدفعة كمستردة ثم حدّدها كمُعالَجة. | أُلغي الدفع لدى مزوّد الدفع (بسبب نزاع أو اعتراض من حامل البطاقة). سجّل الدفعة مستردّة، ثم أغلق المتابعة. | «عُكس الدفع» و«استرجاع» حرفيتان |
| ar/gateways.json | `attention.capture_unreadable` | يفيد PayPal بأن هذا المبلغ دُفع، لكن تعذّرت قراءة تفاصيل الدفعة. تحقّق منها في PayPal وسجّلها يدويًا ثم حدّدها كمُعالَجة. | يفيد PayPal بأن هذا المبلغ دُفع، لكن تعذّرت قراءة تفاصيل الدفعة. تحقّق منها في PayPal وسجّلها يدويًا، ثم أغلق المتابعة. | مطابقة زر الإغلاق |
| ar/gateways.json | `attention.link_closed` | كان الرابط مدفوعًا أو ملغيًا عند وصول المبلغ. | كان الرابط قد دُفع أو أُلغي عند وصول المبلغ. | «ملغيًا» خطأ إملائي وصياغة أطبع |
| ar/gateways.json | `attention.already_enrolled` | كان الطالب مشتركًا بالفعل؛ استرد المبلغ أو احتفظ به رصيدًا يدويًا. | كان الطالب مشتركًا بالفعل؛ استردّ المبلغ أو أضفه إلى رصيده يدويًا. | «احتفظ به رصيدًا» حرفية |
| ar/gateways.json | `attention.request_cancelled` | كان حجز الاستشارة ملغيًا عند وصول المبلغ؛ استرده أو أعد الحجز يدويًا. | كان حجز الاستشارة قد أُلغي عند وصول المبلغ؛ استردّ المبلغ أو أعد الحجز يدويًا. | «ملغيًا» خطأ والضمير بلا مرجع |
| ar/gateways.json | `attention.not_bookable` | لم تعد الاستشارة تقبل حجوزات عند وصول المبلغ؛ استرده أو سجّل الحجز يدويًا. | لم تعد الاستشارة تقبل حجوزات عند وصول المبلغ؛ استردّ المبلغ أو سجّل الحجز يدويًا. | الضمير بلا مرجع |
| ar/gateways.json | `errors.webhook_secret_required` | أدخل سر توقيع الـ webhook عند تغيير الوضع. | أدخل مفتاح توقيع الإشعارات عند تغيير الوضع. | المسرد (§3): لا «سر الـ webhook» |
| ar/gateways.json | `errors.no_webhook_secret` | أدخل سر توقيع الـ webhook الخاص بـ Stripe أولًا. | أدخل مفتاح توقيع الإشعارات من Stripe أولًا. | نفس مصطلح settings.webhookSecret |
| ar/gateways.json | `errors.checkout_starting` | جارٍ بدء عملية الدفع، حاول مرة أخرى بعد لحظة. | عملية الدفع قيد البدء. حاول مرة أخرى بعد لحظة. | جملتان بدل فاصلة |
| ar/gateways.json | `errors.provider_failed` | لم يستجب مزوّد الدفع. يُرجى المحاولة مرة أخرى بعد قليل. | لم يستجب مزوّد الدفع. حاول مرة أخرى بعد قليل. | بلا «يُرجى» (§2.2) |
| ar/gateways.json | `errors.locale` | استخدم رمز لغة مثل en-US. | استخدم رمز لغة مثل ⁦en-US⁩. | عزل النص اللاتيني (§2.13) |
| ar/gateways.json | `link.paid` | تم دفع هذا الرابط. شكرًا لك. | تم الدفع عبر هذا الرابط. شكرًا لك. | «تم دفع الرابط» حرفية |
| ar/gateways.json | `links.cancelBody` | لن يتمكن أحد من دفعه بعد الآن. المبلغ الذي في الطريق يُحفظ لتراجعه. | لن يتمكن أحد من الدفع عبره بعد الآن، وأي دفعة في طريقها إليك تُحفظ لتراجعها. | «المبلغ الذي في الطريق» ركيكة |
| ar/website.json | `genericError` | حدث خطأ ما. يرجى المحاولة مرة أخرى. | حدث خطأ ما. حاول مرة أخرى. | الصيغة العامة المعتمدة (§2.5) |
| ar/website.json | `nav.setup` | دليل التجهيز | دليل الإعداد | «التجهيز» أقل شيوعًا في البرمجيات |
| ar/website.json | `branding.tagline` | الشعار النصي | العبارة التعريفية | «الشعار النصي» يلتبس بالشعار (Logo) |
| ar/website.json | `home.heroTitle` | عنوان الصفحة الرئيسية | عنوان الواجهة | اتساق مع «صورة الواجهة» |
| ar/website.json | `home.heroSubtitle` | العنوان الفرعي | العنوان الفرعي للواجهة | اتساق مع «صورة الواجهة» |
| ar/website.json | `home.ctaLabel` | نص زر الدعوة للعمل | نص الزر الرئيسي | «زر الدعوة للعمل» حرفية |
| ar/website.json | `pages.slug` | المعرّف (slug) | رابط الصفحة (slug) | «المعرّف» غامض؛ مطابق لـ slug.label |
| ar/website.json | `pages.seoDescription` | وصف تحسين محركات البحث | الوصف لمحركات البحث | «وصف تحسين محركات البحث» حرفية |
| ar/website.json | `pages.deleteTitle` | هل تريد حذف هذه الصفحة؟ | حذف هذه الصفحة؟ | عنوان التأكيد بالمصدر (§2.7) |
| ar/website.json | `pages.deleteBody` | ستُحذف «{{title}}» نهائيًا من موقعك. | ستُحذف الصفحة «{{title}}» نهائيًا من موقعك. | توضيح المحذوف |
| ar/website.json | `pages.needsBuilder` | تحتاج منشئ الصفحات | تحتاج إلى منشئ الصفحات | حرف الجر |
| ar/website.json | `pages.needsBuilderNote` | منشئ الصفحات متوقف لأكاديميتك، لذا فهذه الصفحة مخفية عن موقعك. اطلب من إتقان تفعيله لتعديل كتلها. | منشئ الصفحات غير مفعّل في أكاديميتك، لذا هذه الصفحة مخفية من موقعك. اطلب من إتقان تفعيله لتتمكن من تعديل أقسامها. | «كتلها» حرفية؛ الواجهة تسميها أقسامًا |
| ar/website.json | `testimonials.deleteTitle` | هل تريد حذف هذا الرأي؟ | حذف هذا الرأي؟ | عنوان التأكيد بالمصدر (§2.7) |
| ar/website.json | `inquiries.statusHandled` | تمّت معالجتها | المُعالَجة | تسمية تبويب تقابل «الجديدة» |
| ar/website.json | `inquiries.markHandled` | تمّت المعالجة | وضع علامة كمُعالَج | الزر كان يقول «تمّت المعالجة» كأنه حالة |
| ar/website.json | `settings.status.confirmAction` | نعم، غيّر الحالة | تغيير الحالة | زر بالمصدر (§2.1) |
| ar/website.json | `ads.banner` | الصورة | صورة الإعلان | «الصورة» عامة جدًا |
| ar/website.json | `ads.active` | ساري | سارٍ | الاسم المنقوص النكرة (سارٍ) |
| ar/website.json | `ads.expired` | منتهي | منتهٍ | الاسم المنقوص النكرة (منتهٍ) |
| ar/website.json | `redirects.inactive` | موقوف | غير مفعّل | يقابل «مفعّل» |
| ar/website.json | `redirects.deleteBody` | سيتم حذف التحويل من {{from}} نهائيًا. | سيُحذف التحويل من {{from}} نهائيًا. | المسرد (§2.8): لا «سيتم حذف» |
| ar/website.json | `articles.status.scheduled` | مجدولة | مجدول | مطابقة المقال (مذكر) كما في «منشور» |
| ar/website.json | `articles.status.published` | منشورة | منشور | مطابقة المقال (مذكر) |
| ar/website.json | `articles.slug` | العنوان | الرابط | «العنوان» يلتبس بعنوان المقال |
| ar/website.json | `articles.seoTitle` | عنوان محركات البحث | العنوان لمحركات البحث | أطبع من «عنوان محركات البحث» |
| ar/website.json | `articles.seoDescription` | وصف تحسين محركات البحث | الوصف لمحركات البحث | «وصف تحسين محركات البحث» حرفية |
| ar/website.json | `videos.slug` | العنوان (الرابط) | الرابط | «العنوان (الرابط)» يلتبس بالعنوان |
| ar/website.json | `videos.seoTitle` | عنوان محركات البحث | العنوان لمحركات البحث | أطبع |
| ar/website.json | `videos.seoDescription` | وصف تحسين محركات البحث | الوصف لمحركات البحث | «وصف تحسين محركات البحث» حرفية |
| ar/website.json | `videos.usedByTestimonials` | آراء تستخدمه: {{n}} | آراء الطلاب التي تستخدمه: {{n}} | اتساق مع بقية القائمة |
| ar/website.json | `blocks.imageHint` | الصور التي لا تستخدمها أي كتلة محفوظة تُحذف عند حفظ الصفحة. | تُحذف الصور التي لا يستخدمها أي قسم محفوظ عند حفظ الصفحة. | «كتلة» حرفية؛ الواجهة تسميها «قسم» |
| ar/website.json | `blocks.noVideo` | لم يتم اختيار فيديو | لم يُختر فيديو | المبني للمجهول بدل «لم يتم + مصدر» |
| ar/website.json | `setup.title` | جهّز موقعك الإلكتروني | إعداد موقعك الإلكتروني | العنوان بالمصدر ومطابقة «دليل الإعداد» |
| ar/website.json | `setup.intro` | اتبع الخطوات بالترتيب، ومعظم الأكاديميات تنتهي في حوالي نصف ساعة. كل خطوة تُعلَّم تلقائيًا عند حفظ محتواها، ويظهر التغيير على الموقع خلال دقيقة تقريبًا. | اتبع الخطوات بالترتيب، وتنتهي معظم الأكاديميات منها في نحو نصف ساعة. تُعلَّم كل خطوة تلقائيًا عند حفظ محتواها، وتظهر التغييرات على الموقع العام خلال دقيقة تقريبًا. | ترتيب كلمات أطبع |
| ar/website.json | `setup.progressLabel` | تقدّم تجهيز الموقع | تقدّم إعداد الموقع | مطابقة «دليل الإعداد» |
| ar/website.json | `setup.progress` | تم {{done}} من {{total}} خطوة · يتبقى حوالي {{minutes}} دقيقة | الخطوات المنجزة: {{done}} من {{total}} · الوقت المتبقي: {{minutes}} دقيقة تقريبًا | «{{total}} خطوة» خطأ مع 3–10 |
| ar/website.json | `setup.allDone` | تم كل شيء! موقعك مكتمل، افتحه لترى النتيجة. | اكتمل كل شيء! موقعك جاهز، افتحه لترى النتيجة. | أطبع |
| ar/website.json | `setup.openSite` | افتح موقعي | فتح موقعي | زر بالمصدر؛ لا أمر مع ياء المتكلم (§2.3) |
| ar/website.json | `setup.start` | ابدأ | البدء | زر بالمصدر (§2.1) |
| ar/website.json | `setup.edit` | راجع | مراجعة | زر بالمصدر (§2.1) |
| ar/website.json | `setup.steps.contact.tip` | اكتب رقم واتساب مع كود الدولة، مثل ‎+201001234567. والصق روابط الحسابات كاملة تبدأ بـ ⁦https://⁩. | اكتب رقم واتساب مع رمز الدولة، مثل ‎+201001234567. والصق روابط الحسابات كاملة تبدأ بـ ⁦https://⁩. | المسرد: «رمز» الدولة لا «كود» |
| ar/website.json | `setup.steps.hero.tip` | استخدم صورة أفقية بحجم 1920×1080 تقريبًا وأقل من 2 ميجابايت (JPG). اجعل العنصر الأساسي بعيدًا عن جهة النص (اليمين في العربي). العنوان: وعد قصير، والوصف: جملة واحدة. تريد أكثر من غلاف؟ أضف شرائح من «شرائح الغلاف المتحركة» في نفس التبويب. | استخدم صورة أفقية بحجم 1920×1080 تقريبًا وأقل من 2 ميجابايت (JPG). اجعل العنصر الأساسي بعيدًا عن جهة النص (اليمين في النسخة العربية). العنوان: وعد قصير، والوصف: جملة واحدة. تريد أكثر من غلاف؟ أضف شرائح من «شرائح الغلاف المتحركة» في التبويب نفسه. | «في العربي» عامية و«نفس التبويب» |
| ar/website.json | `setup.steps.about.tip` | فقرة قصيرة، ثم 3–4 نقاط تبدأ بكلمة عريضة (مثل «حصص فردية — …»)، ويمكنك إضافة اقتباس قصير. | فقرة قصيرة، ثم 3–4 نقاط تبدأ بخط عريض (مثل «حصص فردية — …»)، ويمكنك إضافة اقتباس قصير. | «كلمة عريضة» حرفية |
| ar/website.json | `setup.steps.video.tip` | ارفع فيديو MP4 أفقيًا أقل من 20 ميجابايت، مدته 30–90 ثانية، مع صورة غلاف. ثم اختره «فيديو تعريفي» من تبويب الصفحة الرئيسية. | ارفع فيديو MP4 أفقيًا حجمه أقل من 20 ميجابايت ومدته 30–90 ثانية، مع صورة غلاف. ثم اختره فيديو تعريفيًا من تبويب الصفحة الرئيسية. | ترتيب أوضح |
| ar/website.json | `setup.steps.offers.why` | بانرات عريضة يظهر عليها العنوان، حتى التاريخ الذي تحدده. | صور إعلانية عريضة يظهر عليها العنوان، وتبقى حتى التاريخ الذي تحدده. | «بانرات» دخيلة |
| ar/website.json | `setup.steps.offers.tip` | بانر بحجم 1600×530 تقريبًا (3:1) وأقل من 2 ميجابايت، مع مساحة هادئة في الأسفل حيث يظهر النص. اختر نوع «خصم» لتظهر شارة الخصم. | صورة إعلان بحجم 1600×530 تقريبًا (3:1) وأقل من 2 ميجابايت، مع مساحة هادئة في الأسفل حيث يظهر النص. اختر نوع «خصم» لتظهر شارة الخصم. | «بانر» دخيلة |
| ar/website.json | `setup.steps.pages.tip` | استخدم منشئ الصفحات: عنوان، ونص، وصورة، وفيديو، وزر يوصل لنموذج التواصل. وأبقِ «إظهار في القائمة» مفعّلًا. | استخدم منشئ الصفحات: عنوان، ونص، وصورة، وفيديو، وزر يقود إلى نموذج التواصل. وأبقِ «إظهار في القائمة» مفعّلًا. | «يوصل لـ» عامية |
| ar/website.json | `setup.steps.pages.tipNoVideo` | استخدم منشئ الصفحات: عنوان، ونص، وصورة، وزر يوصل لنموذج التواصل. وأبقِ «إظهار في القائمة» مفعّلًا. | استخدم منشئ الصفحات: عنوان، ونص، وصورة، وزر يقود إلى نموذج التواصل. وأبقِ «إظهار في القائمة» مفعّلًا. | «يوصل لـ» عامية |
| ar/website.json | `setup.steps.articles.why` | أحدث ثلاث مقالات تظهر في الصفحة الرئيسية، والمقالات تجلب الزوار من جوجل. | أحدث ثلاث مقالات تظهر في الصفحة الرئيسية، والمقالات تجلب الزوار من Google. | أسماء العلامات باللاتينية (§2.13) |
| ar/website.json | `setup.steps.articles.tip` | كل مقال يحتاج تصنيفًا، وصورة غلاف (1600×900 تقريبًا)، وملخصًا قصيرًا، وتاريخ نشر. | يحتاج كل مقال إلى فئة، وصورة غلاف (1600×900 تقريبًا)، وملخص قصير، وتاريخ نشر. | «تصنيف» ← «فئة» كما في الواجهة |
| ar/website.json | `setup.steps.courses.tip` | صورة مصغرة 1280×720 تقريبًا، وفيديو تعريفي قصير، وعناوين دروس واضحة. والدورة المجانية طريقة ممتازة لجذب أسر جديدة. | صورة مصغرة 1280×720 تقريبًا، وفيديو تعريفي قصير، وعناوين دروس واضحة. والدورة المجانية طريقة ممتازة لجذب عائلات جديدة. | المسرد (§1): «عائلات» لا «أسر» |
| ar/website.json | `setup.steps.seo.why` | سطر التذييل يظهر في كل الصفحات، وكلمات البحث تساعد جوجل على فهم موقعك. | سطر التذييل يظهر في كل الصفحات، وكلمات البحث تساعد Google على فهم موقعك. | أسماء العلامات باللاتينية (§2.13) |
| ar/website.json | `setup.steps.seo.tip` | التذييل: جملة واحدة عن الأكاديمية. الكلمات: 4–6 عبارات تبحث عنها الأسر، تفصل بينها فواصل. | التذييل: جملة واحدة عن الأكاديمية. الكلمات: 4–6 عبارات تبحث عنها العائلات، تفصل بينها فواصل. | المسرد (§1): «العائلات» لا «الأسر» |
| ar/website.json | `slides.subtitle` | الوصف | العنوان الفرعي | EN Subtitle؛ اتساق مع الصفحة الرئيسية |
| ar/website.json | `slides.add` | أضف الشريحة | إضافة شريحة | زر بالمصدر (§2.1) |
| ar/website.json | `slides.saveEdit` | احفظ الشريحة | حفظ الشريحة | زر بالمصدر (§2.1) |
| ar/website.json | `slides.deleteBody` | ستُحذف «{{title}}» من العرض المتحرك في الصفحة الرئيسية. | ستُحذف الشريحة «{{title}}» من العرض المتحرك في الصفحة الرئيسية. | توضيح المحذوف |
| ar/website.json | `serverErrors.slideButton` | املأ نص الزر بالعربية والإنجليزية، واختر أين يذهب الزر. | املأ نص الزر بالعربية والإنجليزية، واختر وجهته. | «أين يذهب الزر» حرفية |
| ar/website.json | `clearFilters` | إلغاء التصفية | مسح التصفية | توحيد مع بقية الواجهة |
| ar/website.json | `errors.max.16` | الحد الأقصى 16 حرف. | الحد الأقصى 16 حرفًا. | تمييز العدد: «حرفًا» بعد 11–99 |
| ar/website.json | `errors.max.32` | الحد الأقصى 32 حرف. | الحد الأقصى 32 حرفًا. | تمييز العدد: «حرفًا» بعد 11–99 |
| ar/website.json | `errors.max.60` | الحد الأقصى 60 حرف. | الحد الأقصى 60 حرفًا. | تمييز العدد: «حرفًا» بعد 11–99 |
| ar/website.json | `errors.max.80` | الحد الأقصى 80 حرف. | الحد الأقصى 80 حرفًا. | تمييز العدد: «حرفًا» بعد 11–99 |
| ar/website.json | `errors.max.120` | الحد الأقصى 120 حرف. | الحد الأقصى 120 حرفًا. | تمييز العدد: «حرفًا» بعد 11–99 |
| ar/website.json | `errors.max.160` | الحد الأقصى 160 حرف. | الحد الأقصى 160 حرفًا. | تمييز العدد: «حرفًا» بعد 11–99 |
| ar/website.json | `errors.max.255` | الحد الأقصى 255 حرف. | الحد الأقصى 255 حرفًا. | تمييز العدد: «حرفًا» بعد 11–99 |

## Spanish

| File | Key | Before | After | Why |
|---|---|---|---|---|
| es/account.json | `makePrimary` | Hacer principal | Marcar como principal | Más natural que «Hacer principal» |
| es/account.json | `makePrimaryTitle` | ¿Hacer de este tu correo principal? | ¿Convertir este correo en el principal? | Calco «Hacer de este» |
| es/account.json | `removed` | Se eliminó {{email}}. | Se quitó {{email}}. | Coherente con «Quitar» (no es eliminar) |
| es/translations.json | `retry` | Reintentar | Intentar de nuevo | Glosario: «Intentar de nuevo» |
| es/signInGoogle.json | `nav` | Ajustes de inicio de sesión | Configuración de inicio de sesión | Glosario: «Ajustes» solo para ajustes de nómina |
| es/signInGoogle.json | `title` | Ajustes de inicio de sesión | Configuración de inicio de sesión | Glosario: «Ajustes» solo para ajustes de nómina |
| es/signInGoogle.json | `secretToo` | Introduce también el secreto del cliente. | Escribe también el secreto de cliente. | Coherencia con «Escribe» y «secreto de cliente» |
| es/sessionClasses.json | `add.minutesExtra` | Necesario para una sesión extra, de 15 a 240 minutos | Obligatorio para una sesión adicional, de 15 a 240 minutos | «extra» → «adicional» como en el resto |
| es/sessionClasses.json | `frozen` | Esta sesión tiene una sesión de recuperación, así que no puede cambiar. | Esta sesión ya se recuperó o se compensó, así que no se puede cambiar. | Faltaba «compensated»; «no puede cambiar» poco natural |
| es/gateways.json | `return.amount` | Importe | Monto | Coherencia: «Monto» en todo el archivo |
| es/gateways.json | `errors.notThisStep` | Este método de pago acepta esta moneda solo en pasos de 0,010 (como 5,120 o 5,130). Redondea el importe o añade la comisión de servicio. | Este método de pago acepta esta moneda solo en pasos de 0,010 (como 5,120 o 5,130). Redondea el monto o agrega la comisión por servicio. | «Monto», «Agregar» y «comisión por servicio» como en el resto |
| es/gateways.json | `errors.cannotTakeAmount` | Este método de pago no puede cobrar este importe. | Este método de pago no puede cobrar este monto. | Coherencia: «Monto» |
| es/gateways.json | `attention.reference_missing` | La factura ya no existe. | El concepto pagado ya no existe. | Error de sentido: no siempre es una factura |
| es/gateways.json | `attention.purpose_refused` | La factura no pudo recibir este pago. | No se pudo aplicar este pago. | Error de sentido: no siempre es una factura |
| es/website.json | `previewSite` | Ver vista previa del sitio | Vista previa del sitio | «Ver vista previa» redundante |
| es/website.json | `home.noIntroVideo` | Sin vídeo | Sin video | «video» como en el resto |
| es/website.json | `videos.noMatch` | Ningún vídeo coincide con este filtro. | Ningún video coincide con este filtro. | «video» como en el resto |
| es/website.json | `pages.deleteBody` | "{{title}}" se quitará de tu sitio para siempre. | «{{title}}» se eliminará de tu sitio para siempre. | Comillas «» y «eliminar» (es borrar) |
| es/website.json | `faqs.deleteBody` | "{{question}}" se eliminará para siempre. | «{{question}}» se eliminará para siempre. | Comillas «» |
| es/website.json | `ads.deleteBody` | "{{title}}" se eliminará para siempre. | «{{title}}» se eliminará para siempre. | Comillas «» |
| es/website.json | `articles.deleteBody` | "{{title}}" se eliminará para siempre. | «{{title}}» se eliminará para siempre. | Comillas «» |
| es/website.json | `articleCategories.deleteBody` | "{{name}}" se eliminará para siempre. | «{{name}}» se eliminará para siempre. | Comillas «» |
| es/website.json | `videos.deleteBody` | "{{title}}" se eliminará para siempre. | «{{title}}» se eliminará para siempre. | Comillas «» |
| es/website.json | `redirects.permanentHint` | Los navegadores recuerdan una redirección permanente hasta por una hora. | Los navegadores recuerdan una redirección permanente hasta por una hora, así que un cambio puede no llegar de inmediato a los visitantes. | Faltaba la segunda mitad |
| es/website.json | `articles.slugHintManual` | Añade una redirección desde la dirección antigua en Redirecciones. | Agrega una redirección desde la dirección antigua en Redirecciones. | Glosario: «Agregar» |
| es/website.json | `blocks.empty` | Todavía no hay bloques. Agrega uno abajo. | Todavía no hay secciones. Agrega una con los botones de abajo. | EN dice «sections» y faltaba «botones» |
| es/website.json | `blocks.add` | Agregar un bloque | Agregar una sección | Coherencia con «Secciones de la página» |
| es/website.json | `blocks.cardLabel` | Bloque {{n}}: {{type}} | Sección {{n}}: {{type}} | Coherencia con «Secciones de la página» |
| es/website.json | `blocks.urlInvalid` | Escribe una URL que empiece con http:// o https://. Para páginas de este sitio, usa la lista Lleva a. | Escribe una URL que empiece con http:// o https://. Para páginas de este sitio, usa la lista «El botón lleva a». | Nombre exacto del campo, entre comillas |
| es/website.json | `serverErrors.alreadyRedirected` | Esta ruta ya tiene una redirección; edítala en la lista en lugar de añadir otra. | Esta ruta ya tiene una redirección; edítala en la lista en lugar de agregar otra. | Glosario: «Agregar» |
| es/website.json | `serverErrors.youtube` | Pega un enlace de YouTube o el id del video. | Pega un enlace de YouTube o el ID del video. | «ID» como en videos.link |
