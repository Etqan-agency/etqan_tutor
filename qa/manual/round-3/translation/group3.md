# Translation review, group 3 (Agent 4)

Files: payroll, people, integrations, notifications, trials, catalogue, wallet, etqanBilling, archives, library, content, nav, timezones, features, toast (ar + es).
Follows `round-3/glossary.md`. Keys, `{{placeholders}}` and tags unchanged.

**Strings changed: 155** (135 Arabic, 20 Spanish). library and toast needed no changes.

## Tests updated to the new wording
- `src/features/payroll/PayslipPage.r3.test.tsx`: "بواسطة QA Admin" → "أصدره QA Admin"; "سُجّل الدفع بواسطة" → "سجّل الدفع".
- `src/features/payroll/WithdrawalsPage.test.tsx`: approve button "موافقة" → "قبول".
- `src/features/notifications/NotificationSettingsForm.test.tsx`: "أرسل هذا الإشعار: …" → "إرسال هذا الإشعار: …".
- `src/qa-round3-m11.test.tsx`: `people:picker.more` new wording.
- `src/locales/people-copy.test.ts`: "التي قاربت على الانتهاء" → "التي أوشكت على الانتهاء".

Kept on purpose: `wallet:family.topUpTitleOwn` "اشحن رصيدك" (learner-facing imperative, pinned by ETQAN-QA-1336 in `qa-round3-m15.test.tsx`).

## Test run (dashboard container, --maxWorkers=1)
- `src/locales/` : 18/20 pass. The 2 failures are outside group 3: `copy.test.ts` (`auth:newToEtqan`) and `locales.test.ts` Spanish-copy check (`finance.types.marketing` equals English). Both are other groups' files.
- PayslipPage.r3, WithdrawalsPage, NotificationSettingsForm, qa-round3-m06/m11/m15, FeaturesPage: 7 files, 162 tests pass.

## Changes

| File | Key | Before | After | Why |
|---|---|---|---|---|
| ar/payroll.json | `payslip.issuedWhen` | {{day}}، {{time}}، بواسطة {{name}} | {{day}}، {{time}}، أصدره {{name}} | Agentive "بواسطة" calque |
| ar/payroll.json | `payslip.paidBy` | سُجّل الدفع بواسطة | سجّل الدفع | Agentive "بواسطة" calque |
| ar/payroll.json | `list.noMatch` | لا توجد كشوف رواتب تطابق هذه التصفية. | لا توجد كشوف رواتب تطابق عوامل التصفية. | "هذه التصفية" reads oddly for plural filters |
| ar/payroll.json | `settings.excusedWeight` | أجر حصة اعتذر عنها الطالب (٪) | أجر حصة غاب عنها الطالب بعذر (٪) | Glossary: excused = غائب بعذر |
| ar/payroll.json | `settings.excusedHint` | نسبة الأجر عند اعتذار الطالب وحضور المعلم. | نسبة الأجر عند غياب الطالب بعذر وحضور المعلم. | Glossary: excused = غائب بعذر |
| ar/payroll.json | `settings.loadError` | تعذر تحميل قواعد الرواتب. | تعذّر تحميل قواعد الرواتب. | Missing shadda on تعذّر |
| ar/payroll.json | `bulk.body` | تُطبَّق الأسعار نفسها على كل معلم تختاره، بعملة راتبه. ويحل السعر الجديد محل سعر المعلم الحالي للمادة نفسها. | تُطبَّق الأسعار نفسها على كل معلم تختاره، بعملة راتبه. ويحل السعر الجديد محل سعر المعلم الحالي للدورة نفسها. | Glossary: course = دورة, not مادة |
| ar/payroll.json | `lines.excused` | الطالب معتذر | الطالب غائب بعذر | Glossary: avoid معتذر |
| ar/payroll.json | `lines.member` | حصة جماعية — مدفوعة في السطر الأول | حصة جماعية: تُدفع في السطر الأول | Rare em dash; verb reads more naturally |
| ar/payroll.json | `counts.student_excused` | اعتذار الطالب | غياب الطالب بعذر | Glossary: excused = غائب بعذر |
| ar/payroll.json | `balance.loadError` | تعذر تحميل الرصيد. | تعذّر تحميل الرصيد. | Missing shadda on تعذّر |
| ar/payroll.json | `withdrawals.status.approved` | تمت الموافقة | مقبول | Glossary approve = قبول; chip agrees with طلب like مرفوض/ملغى |
| ar/payroll.json | `withdrawals.loadError` | تعذر تحميل طلبات السحب. | تعذّر تحميل طلبات السحب. | Missing shadda on تعذّر |
| ar/payroll.json | `withdrawals.approve` | موافقة | قبول | Glossary: approve = قبول, not موافقة |
| ar/payroll.json | `withdrawals.approveTitle` | الموافقة على هذا الطلب | قبول هذا الطلب | Glossary: approve = قبول |
| ar/payroll.json | `withdrawals.approved` | تمت الموافقة على الطلب. | تم قبول الطلب. | Glossary: approve = قبول |
| ar/payroll.json | `withdrawals.approveTitleFor` | الموافقة على سحب {{amount}} للمعلم {{teacher}}؟ | قبول سحب {{amount}} للمعلم {{teacher}}؟ | Glossary: approve = قبول |
| ar/payroll.json | `withdrawals.noBalance` | لا يوجد رصيد لهذا المعلم للسحب منه. | ليس لدى هذا المعلم رصيد يمكن سحبه. | Literal word order |
| ar/payroll.json | `receipt.title` | أكّد أنك استلمت هذا الراتب | تأكيد استلام هذا الراتب | Dialog titles use the masdar |
| ar/payroll.json | `projections.loadError` | تعذر تحميل توقعات الرواتب. | تعذّر تحميل توقعات الرواتب. | Missing shadda on تعذّر |
| es/payroll.json | `list.lateFor` | Clases tardías de {{name}} ({{count}}): | Sesiones con retraso de {{name}} ({{count}}): | Glossary: sesión, not clase; "tardías" unnatural |
| es/payroll.json | `balance.explained` | Saldo = las nóminas pagadas a tu saldo, menos los retiros que se te pagaron. Disponible = el saldo menos las solicitudes aún abiertas. | Saldo = los recibos de pago abonados a tu saldo, menos los retiros que se te pagaron. Disponible = el saldo menos las solicitudes aún abiertas. | Glossary: payslip = recibo de pago, nómina = payroll |
| es/payroll.json | `balance.myPayslips` | Mis nóminas | Mis recibos de pago | Glossary: payslip = recibo de pago |
| es/payroll.json | `studentRates.noMatch` | Ninguna tarifa por alumno coincide con esta búsqueda. | Ninguna tarifa por estudiante coincide con esta búsqueda. | Glossary: estudiante, not alumno |
| es/payroll.json | `studentRates.chooseStudent` | Elige un alumno | Elige un estudiante | Glossary: estudiante, not alumno |
| ar/people.json | `field.payout_method` | طريقة الدفع | طريقة الاستلام | Glossary: payout = طريقة الاستلام (طريقة الدفع means the opposite) |
| ar/people.json | `field.payout_details` | تفاصيل الدفع | بيانات الاستلام | Matches payout method term |
| ar/people.json | `errors.payoutDetailsRequired` | أدخل بيانات الدفع لهذه الطريقة. | أدخل بيانات الاستلام لهذه الطريقة. | Matches payout method term |
| ar/people.json | `field.coursesCount` | {{count}} دورة | عدد الدورات: {{count}} | "{{count}} دورة" is wrong for 3–10; neutral form fits every count |
| es/people.json | `field.coursesCount` | {{count}} cursos | Cursos: {{count}} | "1 cursos" was wrong; neutral form fits every count |
| ar/people.json | `status.paused` | متوقف مؤقتًا | موقوف مؤقتًا | Glossary: person status = موقوف مؤقتًا |
| ar/people.json | `ageGroup.minor` | قاصر (أقل من 18) | قاصر (دون 18 عامًا) | More natural than "أقل من 18" |
| ar/people.json | `errors.genderRequired` | اختر ذكر أو أنثى. | اختر «ذكر» أو «أنثى». | Option names quoted; bare ذكر after اختر was ungrammatical |
| ar/people.json | `bulk.skipped` | تم تخطي من هم في عائلة أخرى: {{names}} | تم تخطّي من هم في عائلة أخرى: {{names}} | Missing shadda |
| ar/people.json | `families.columns.actions` | إجراءات | الإجراءات | Consistent with other Actions columns |
| ar/people.json | `families.retireBody` | ستتوقف العائلة «{{name}}» عن دفع الفواتير الجديدة لطلابها؛ يبقى الطلاب مرتبطين بها ويمكنك إعادة تفعيل العائلة لاحقًا. | ستتوقف العائلة «{{name}}» عن دفع الفواتير الجديدة لطلابها؛ يبقى الطلاب مرتبطين بها ويمكنك استعادة العائلة لاحقًا. | Restore = استعادة (matches the Restore button) |
| ar/people.json | `picker.more` | يظهر أول {{shown}} من {{count}} طالبًا. اكتب الاسم للوصول إلى البقية. | يظهر هنا {{shown}} من أصل {{count}} من الطلاب. اكتب الاسم للوصول إلى البقية. | "{{count}} طالبًا" is only right for 11–99 |
| es/people.json | `picker.find` | Buscar un alumno | Buscar un estudiante | Glossary: estudiante, not alumno |
| es/people.json | `picker.more` | Se muestran los primeros {{shown}} de {{count}} alumnos. Escribe un nombre para encontrar los demás. | Se muestran los primeros {{shown}} de {{count}} estudiantes. Escribe un nombre para encontrar los demás. | Glossary: estudiante, not alumno |
| es/people.json | `picker.none` | Ningún alumno coincide con esta búsqueda. | Ningún estudiante coincide con esta búsqueda. | Glossary: estudiante, not alumno |
| ar/integrations.json | `default.feature_off` | هذه الميزة متوقفة لأكاديميتك. | هذه الميزة غير مفعّلة لأكاديميتك. | Glossary: features are مفعّلة / غير مفعّلة |
| ar/integrations.json | `services.whatsapp.availableWhen` | سيتاح ربط رقم واتساب الخاص بك عند إطلاق رسائل واتساب. | سيتاح ربط رقمك في واتساب عند إطلاق رسائل واتساب. | "الخاص بك" calque |
| ar/integrations.json | `services.payments.availableWhen` | سيتاح حساب Stripe Connect الافتراضي من إتقان عند إطلاقه. تُضبط مفاتيح Stripe أو PayPal الخاصة بك في بوابات الدفع. | سيتاح حساب Stripe Connect الافتراضي من إتقان عند إطلاقه. تُضبط مفاتيحك في Stripe أو PayPal من بوابات الدفع. | "الخاص بك" calque |
| ar/integrations.json | `services.payments.ownFirst` | تُستخدم مفاتيح Stripe الخاصة بك في بوابات الدفع أولًا متى كانت مفعّلة. | تُستخدم مفاتيحك في Stripe المضبوطة في بوابات الدفع أولًا متى كانت مفعّلة. | "الخاص بك" calque |
| ar/integrations.json | `services.video.availableWhen` | سيتاح ربط حساب Zoom الخاص بك عند إطلاق اجتماعات Zoom. | سيتاح ربط حسابك في Zoom عند إطلاق اجتماعات Zoom. | "الخاص بك" calque |
| ar/integrations.json | `services.ai.body` | المسودات المكتوبة بالذكاء الاصطناعي وتقارير الذكاء الاصطناعي. | مسودات وتقارير يكتبها الذكاء الاصطناعي. | Repetitive literal phrasing |
| ar/integrations.json | `services.ai.availableWhen` | سيتاح ربط مفتاح Claude API الخاص بك عند إطلاق ميزات الذكاء الاصطناعي. | سيتاح ربط مفتاحك في Claude API عند إطلاق ميزات الذكاء الاصطناعي. | "الخاص بك" calque |
| ar/integrations.json | `services.ai.disconnectTitle` | فصل حساب Claude الخاص بك؟ | فصل حسابك في Claude؟ | "الخاص بك" calque |
| ar/integrations.json | `services.ai.disconnectBody` | ستعود مسودات الذكاء الاصطناعي إلى حساب إتقان الافتراضي إن كان متاحاً لأكاديميتك. | ستعود مسودات الذكاء الاصطناعي إلى حساب إتقان الافتراضي إن كان متاحًا لأكاديميتك. | Tanween on the letter before alif (glossary §2.12) |
| ar/integrations.json | `own.switchedOff` | حسابك الخاص متوقف، لذا يُستخدم حساب إتقان الافتراضي إن كان متاحًا. | حسابك الخاص غير مفعّل، لذا يُستخدم حساب إتقان الافتراضي إن كان متاحًا. | Glossary: on/off = مفعّل / غير مفعّل |
| ar/integrations.json | `actions.connect` | اربط حسابك الخاص | ربط حسابك الخاص | Buttons use the masdar, like the other buttons in the group |
| ar/integrations.json | `email.passwordKept` | محفوظة — اتركها فارغة للإبقاء عليها | محفوظة. اتركها فارغة للإبقاء عليها | Avoid em dash |
| ar/integrations.json | `email.enabled` | أرسل بريد الأكاديمية عبر هذا الحساب | إرسال بريد الأكاديمية عبر هذا الحساب | Switch label as masdar, not a command |
| ar/integrations.json | `zoom.secretKept` | محفوظ — اتركه فارغًا للإبقاء عليه | محفوظ. اتركه فارغًا للإبقاء عليه | Avoid em dash |
| ar/integrations.json | `zoom.enabled` | أنشئ اجتماعات الأكاديمية على حساب Zoom هذا | إنشاء اجتماعات الأكاديمية على حساب Zoom هذا | Switch label as masdar, not a command |
| ar/integrations.json | `connect.statusBody.pending` | يجب أن ينهي Stripe مراجعة بياناتك قبل أن تتمكن الأسر من الدفع. | يجب أن ينهي Stripe مراجعة بياناتك قبل أن تتمكن العائلات من الدفع. | Glossary: family = العائلات, not الأسر |
| ar/integrations.json | `connect.statusBody.active` | تدفع الأسر إلى حسابك في Stripe، وتُقتطع رسوم إتقان من كل دفعة. | تدفع العائلات إلى حسابك في Stripe، وتُقتطع رسوم إتقان من كل دفعة. | Glossary: family = العائلات, not الأسر |
| ar/integrations.json | `connect.notInCountry` | خدمة Stripe Connect غير متاحة في دولتك. يمكنك استخدام مفاتيح Stripe الخاصة بك أو PayPal في بوابات الدفع. | خدمة Stripe Connect غير متاحة في دولتك. ما زال بإمكانك استخدام مفاتيحك في Stripe أو PayPal من بوابات الدفع. | "الخاص بك" calque; "still" was lost |
| ar/integrations.json | `connect.otherMode` | تم الربط في وضع الاختبار — أعد الربط لاستقبال المدفوعات الحقيقية. | تم الربط في وضع الاختبار، أعد الربط لاستقبال المدفوعات الحقيقية. | Avoid em dash |
| ar/integrations.json | `connect.disconnectTitle` | قطع الاتصال بـ Stripe؟ | فصل حساب Stripe؟ | Same verb (فصل) as the other disconnect dialogs |
| ar/integrations.json | `connect.disconnectBody` | لن تتمكن الأسر من الدفع عبر Stripe Connect من إتقان. يبقى حسابك في Stripe كما هو. | لن تتمكن العائلات من الدفع عبر Stripe Connect من إتقان. يبقى حسابك في Stripe كما هو. | Glossary: family = العائلات, not الأسر |
| ar/integrations.json | `ai.hint` | استخدم مفتاح Claude API الخاص بك من Claude Console: تُكتب مسودات الذكاء الاصطناعي في أكاديميتك عندها على حسابك. | استخدم مفتاحك في Claude API من Claude Console، لتُكتب مسودات الذكاء الاصطناعي في أكاديميتك على حسابك. | "الخاص بك" calque; awkward word order |
| ar/integrations.json | `ai.keyKept` | محفوظ — اتركه فارغاً للإبقاء عليه | محفوظ. اتركه فارغًا للإبقاء عليه | Avoid em dash; tanween on the letter before alif |
| ar/integrations.json | `ai.enabled` | اكتب مسودات الذكاء الاصطناعي للأكاديمية بهذا الحساب | كتابة مسودات الذكاء الاصطناعي للأكاديمية بهذا الحساب | Switch label as masdar, not a command |
| ar/integrations.json | `errors.use_connect` | استخدم الاتصال بـ Stripe. مفاتيح Stripe أو PayPal الخاصة بك تُضاف في بوابات الدفع. | استخدم «الاتصال بـ Stripe». تُضاف مفاتيحك في Stripe أو PayPal من بوابات الدفع. | Quote the button name; "الخاص بك" calque |
| ar/integrations.json | `errors.connect_country` | خدمة Stripe Connect غير متاحة في دولتك. استخدم مفاتيح Stripe الخاصة بك أو PayPal في بوابات الدفع. | خدمة Stripe Connect غير متاحة في دولتك. استخدم مفاتيحك في Stripe أو PayPal من بوابات الدفع. | "الخاص بك" calque |
| ar/integrations.json | `whatsapp.hint` | استخدم رقم واتساب للأعمال الخاص بك (Cloud API): تصدر الإشعارات حينها من رقمك. أنشئ قالب خدمة واحدًا بثلاثة متغيرات بالضبط في نصه، معتمدًا بالعربية والإنجليزية. | استخدم رقمك في واتساب للأعمال (Cloud API) لتصدر الإشعارات من رقمك. أنشئ قالب خدمة واحدًا في نصه ثلاثة متغيرات بالضبط، ومعتمدًا بالعربية والإنجليزية. | "الخاص بك" calque; smoother order |
| ar/integrations.json | `whatsapp.tokenKept` | محفوظ — اتركه فارغًا للإبقاء عليه | محفوظ. اتركه فارغًا للإبقاء عليه | Avoid em dash |
| ar/integrations.json | `whatsapp.enabled` | أرسل إشعارات واتساب للأكاديمية عبر هذا الحساب | إرسال إشعارات واتساب للأكاديمية عبر هذا الحساب | Switch label as masdar, not a command |
| ar/notifications.json | `types.late` | الحصة لم تبدأ | تأخر بدء الحصة | Matches the masdar style of the other notice types |
| ar/notifications.json | `types.subscriptionLow` | حصص قليلة متبقية | قلّة الحصص المتبقية | Literal word order; masdar like the other types |
| ar/notifications.json | `types.upgradeRequested` | طلب رفع المستوى | طلب ترقية المستوى | Glossary: level upgrade = ترقية, not رفع المستوى |
| ar/notifications.json | `types.upgradeDecided` | قرار رفع المستوى | قرار ترقية المستوى | Glossary: level upgrade = ترقية, not رفع المستوى |
| ar/notifications.json | `settings.send` | أرسل هذا الإشعار | إرسال هذا الإشعار | Switch label as masdar, not a command |
| ar/notifications.json | `settings.sendType` | أرسل هذا الإشعار: {{type}} | إرسال هذا الإشعار: {{type}} | Switch label as masdar, not a command |
| ar/notifications.json | `settings.minutesBefore` | دقائق قبل البدء | عدد الدقائق قبل البدء | Clearer field label |
| ar/notifications.json | `settings.minutesAfter` | دقائق بعد البدء | عدد الدقائق بعد البدء | Clearer field label |
| ar/notifications.json | `settings.minutesAfterEnd` | دقائق بعد الانتهاء | عدد الدقائق بعد الانتهاء | Clearer field label |
| ar/notifications.json | `settings.minutesUnread` | دقائق بقاء الرسالة غير مقروءة | مدة بقاء الرسالة غير مقروءة (بالدقائق) | Literal "دقائق بقاء" was awkward |
| ar/notifications.json | `settings.sendWhatsApp` | أرسل على واتساب | إرسال عبر واتساب | Switch label as masdar, not a command |
| ar/notifications.json | `settings.sendWhatsAppType` | أرسل على واتساب: {{type}} | إرسال عبر واتساب: {{type}} | Switch label as masdar, not a command |
| ar/notifications.json | `templates.off` | متوقف | غير مفعّل | Glossary: on/off = مفعّل / غير مفعّل |
| ar/notifications.json | `templates.settingsLink` | تغيير التشغيل والتوقيت | تغيير التفعيل والتوقيت | "التشغيل" is a literal calque of on/off |
| ar/notifications.json | `preferences.hint.payments` | الفواتير والمدفوعات المتأخرة والاشتراكات التي قاربت على الانتهاء. | الفواتير والمدفوعات المتأخرة والاشتراكات التي أوشكت على الانتهاء. | "قاربت على" is ungrammatical (قارب is transitive) |
| ar/notifications.json | `preferences.notNotifiable` | لا يملك هذا الشخص بريدًا إلكترونيًا أو أن حسابه غير مفعّل، لذا لا تصله أي إشعارات. | ليس لدى هذا الشخص بريد إلكتروني أو أن حسابه غير مفعّل، لذا لا تصله أي إشعارات. | More natural than "لا يملك" |
| ar/notifications.json | `whatsapp.choice` | أرسل لي الإشعارات على واتساب | استلام الإشعارات على واتساب | Switch label as masdar, not "أرسل لي" |
| ar/notifications.json | `whatsapp.notReady` | لم تُعِدّ الأكاديمية واتساب بعد، لذا لا تُرسل الإشعارات عليه الآن. | لم تضبط أكاديميتك واتساب بعد، لذا لا تُرسل الإشعارات عبره حاليًا. | Smoother phrasing |
| es/notifications.json | `whatsapp.noPhone` | Añade un número de teléfono a tu perfil para recibir avisos por WhatsApp. | Agrega un número de teléfono a tu perfil para recibir avisos por WhatsApp. | Glossary: Agregar, not Añadir |
| ar/trials.json | `filters.anyHeardFrom` | كيف عرفوا عنا: الكل | كيف عرفوا بنا: الكل | "عرف عن" is a calque; "عرف بـ" is correct |
| ar/trials.json | `columns.paysTeacher` | مدفوعة للمعلم | يُدفع أجرها للمعلم | "مدفوعة للمعلم" read as the session was paid to the teacher |
| ar/trials.json | `columns.heardFrom` | كيف عرفوا عنا | كيف عرفوا بنا | "عرف عن" is a calque; "عرف بـ" is correct |
| ar/trials.json | `fields.heardFrom` | كيف عرفت عنا | كيف عرفت بنا | "عرف عن" is a calque; "عرف بـ" is correct |
| ar/trials.json | `schedule.minutesHint` | اتركه فارغًا لمدة الطلب. | اتركه فارغًا لاستخدام مدة الطلب. | Clearer meaning |
| ar/trials.json | `schedule.paysTeacher` | مدفوعة للمعلم | يُدفع أجرها للمعلم | "مدفوعة للمعلم" read as the session was paid to the teacher |
| ar/trials.json | `inquiry.notes` | استفسار من الموقع من {{name}} ({{contact}}): {{message}} | استفسار عبر الموقع من {{name}} ({{contact}}): {{message}} | Double "من" was clumsy |
| ar/catalogue.json | `errors.wholeNumber` | أدخل رقمًا صحيحًا. | أدخل عددًا صحيحًا. | Whole number = عدد صحيح (رقم صحيح reads as "valid number") |
| ar/catalogue.json | `errors.atLeast0` | على الأقل 0. | 0 على الأقل. | Natural word order |
| ar/catalogue.json | `errors.atLeast1` | على الأقل 1. | 1 على الأقل. | Natural word order |
| ar/catalogue.json | `errors.atLeast15` | على الأقل 15. | 15 على الأقل. | Natural word order |
| ar/catalogue.json | `errors.atMost14` | على الأكثر 14. | 14 على الأكثر. | Natural word order |
| ar/catalogue.json | `errors.atMost240` | على الأكثر 240. | 240 على الأكثر. | Natural word order |
| ar/catalogue.json | `errors.atMost365` | على الأكثر 365. | 365 على الأكثر. | Natural word order |
| ar/catalogue.json | `courses.teachersCount` | {{count}} معلم | عدد المعلمين: {{count}} | "{{count}} معلم" is wrong for 3–10; neutral form fits every count |
| es/catalogue.json | `courses.teachersCount` | {{count}} profesores | Profesores: {{count}} | "1 profesores" was wrong; neutral form fits every count |
| ar/catalogue.json | `packages.sessionsPerWeek` | الحصص أسبوعيًا | عدد الحصص في الأسبوع | Clearer field label |
| es/catalogue.json | `packages.freezeDays` | Días de congelamiento permitidos | Días de pausa permitidos | Glossary: pausa, not congelamiento |
| ar/catalogue.json | `countryPrices.remove` | حذف الصف {{number}} | إزالة الصف {{number}} | Remove (unlink) = إزالة |
| ar/catalogue.json | `price.loadError` | تعذّر تحميل السعر لهذا الطالب. | تعذّر تحميل سعر هذا الطالب. | Smoother phrasing |
| ar/wallet.json | `card.body` | المال الذي يحتفظ به الطالب لدى الأكاديمية، رصيد لكل عملة. | المبلغ المحفوظ للطالب لدى الأكاديمية، برصيد مستقل لكل عملة. | Literal phrasing |
| ar/wallet.json | `card.none` | لا رصيد بعد. | لا يوجد رصيد بعد. | Empty-state pattern "لا يوجد … بعد" |
| ar/wallet.json | `statement.empty` | لا عمليات بعد. | لا توجد عمليات بعد. | Empty-state pattern "لا توجد … بعد" |
| ar/wallet.json | `statement.columns.balance` | الرصيد بعده | الرصيد بعد العملية | "بعده" was unclear |
| ar/wallet.json | `statement.columns.by` | بواسطة | المنفّذ | Avoid agentive "بواسطة" |
| ar/wallet.json | `reverse.body` | يُخصم مبلغه من الرصيد ويُسجَّل الشحن مستردًّا. سلّم المبلغ للأسرة بنفسك. | يُخصم مبلغه من الرصيد ويُسجَّل الشحن مستردًّا. سلّم المبلغ للعائلة بنفسك. | Glossary: family = العائلة, not الأسرة |
| ar/wallet.json | `move.body` | لن يُحتسب مبلغ {{amount}} ضمن الفاتورة ويُضاف إلى رصيد الطالب. لا يمكن ردّه نقدًا بعد ذلك. | لن يُحتسب مبلغ {{amount}} ضمن الفاتورة، بل يُضاف إلى رصيد الطالب. ولا يمكن ردّه نقدًا بعد ذلك. | "ويُضاف" after a negation read as "won't be added" |
| ar/wallet.json | `move.bodyFee` | لن يُحتسب مبلغ {{amount}} ضمن الفاتورة ويُضاف إلى رصيد الطالب. لا تُضاف الرسوم ({{fee}}) إلى الرصيد وتبقى إيرادًا. لا يمكن ردّه نقدًا بعد ذلك. | لن يُحتسب مبلغ {{amount}} ضمن الفاتورة، بل يُضاف إلى رصيد الطالب. ولا تُضاف الرسوم ({{fee}}) إلى الرصيد بل تبقى إيرادًا. ولا يمكن ردّه نقدًا بعد ذلك. | "ويُضاف" after a negation read as "won't be added" |
| ar/wallet.json | `family.none` | لا طلاب لعرضهم. | لا يوجد طلاب لعرضهم. | Empty-state pattern |
| ar/catalogue.json | `packages.total_zero` | {{count}} حصة إجمالًا | لا حصص | Plural rule: zero = لا حصص |
| ar/catalogue.json | `packages.totalShort_zero` | {{count}} حصة | لا حصص | Plural rule: zero = لا حصص |
| ar/etqanBilling.json | `units.conversation` | محادثات WhatsApp | محادثات واتساب | Glossary: WhatsApp = واتساب in Arabic text |
| ar/etqanBilling.json | `usage.none` | لا استخدام لحسابات إتقان الافتراضية هذا الشهر بعد. | لم تُستخدم حسابات إتقان الافتراضية هذا الشهر بعد. | "لا استخدام لـ" is a literal calque |
| ar/etqanBilling.json | `usage.summaryFree` | المستخدَم: {{quantity}} · مجاني حاليًا، فلم تحدّد إتقان سعرًا لهذه الخدمة بعد. | المستخدَم: {{quantity}} · مجاني حاليًا، إذ لم تحدّد إتقان سعرًا لهذه الخدمة بعد. | Wrong connective (فـ) for a reason clause |
| ar/etqanBilling.json | `invoices.noneTitle` | لا فواتير بعد | لا توجد فواتير بعد | Empty-state pattern "لا توجد … بعد" |
| ar/etqanBilling.json | `banner.overdue` | لديك فاتورة من إتقان متأخرة السداد. ادفعها لتواصل استخدام حسابات إتقان الافتراضية. | لديك فاتورة متأخرة من إتقان. ادفعها لتواصل استخدام حسابات إتقان الافتراضية. | Glossary: avoid سداد; overdue = متأخرة |
| es/etqanBilling.json | `invoices.noneBody` | Etqan factura el día 1 de cada mes el mes anterior, y cada factura aparece aquí. | Etqan emite el día 1 de cada mes la factura del mes anterior, y cada factura aparece aquí. | Literal and ungrammatical ("factura … el mes anterior") |
| ar/archives.json | `subscriptions.confirmBody` | يخرج الاشتراك وحصصه من قائمة الاشتراكات، ويبقى محسوبًا في الفواتير والرواتب والتقارير. يمكنك استرجاعه من الأرشيف. | يخرج الاشتراك وحصصه من قائمة الاشتراكات، ويبقى محسوبًا في الفواتير والرواتب والتقارير. يمكنك استعادته من الأرشيف. | Glossary: restore = استعادة, never استرجاع |
| ar/archives.json | `subscriptions.banner` | أُرشف في {{date}} بواسطة {{name}}. | أرشفه {{name}} في {{date}}. | Avoid agentive "بواسطة" |
| ar/archives.json | `subscriptions.restore` | استرجاع | استعادة | Glossary: restore = استعادة, never استرجاع |
| ar/archives.json | `subscriptions.restored` | استُرجع الاشتراك. | تمت استعادة الاشتراك. | Glossary: restore = استعادة |
| ar/archives.json | `subscriptions.restoredCount` | استُرجع {{done}} من {{total}}. | تمت استعادة {{done}} من {{total}}. | Glossary: restore = استعادة |
| ar/archives.json | `subscriptions.restoredSome` | استُرجع {{done}} من {{total}}. {{reason}} | تمت استعادة {{done}} من {{total}}. {{reason}} | Glossary: restore = استعادة |
| ar/archives.json | `subscriptions.deleteBody` | يُحذف الاشتراك وحصصه نهائيًا. غير ممكن بعد تسجيل حضور أي حصة أو إكمالها أو إلغائها. | يُحذف الاشتراك وحصصه نهائيًا. ولا يمكن ذلك إذا سُجّل حضور أي حصة أو اكتملت أو أُلغيت. | "غير ممكن بعد…" was a fragment |
| ar/archives.json | `sessions.restore` | استرجاع | استعادة | Glossary: restore = استعادة, never استرجاع |
| ar/archives.json | `sessions.restored` | استُرجعت الحصة. | تمت استعادة الحصة. | Glossary: restore = استعادة |
| es/archives.json | `simple.present` | Alumno presente | Estudiante presente | Glossary: estudiante, not alumno |
| es/archives.json | `simple.absent` | Alumno ausente | Estudiante ausente | Glossary: estudiante, not alumno |
| es/archives.json | `simple.presentFor` | Alumno presente: {{name}} | Estudiante presente: {{name}} | Glossary: estudiante, not alumno |
| es/archives.json | `simple.absentFor` | Alumno ausente: {{name}} | Estudiante ausente: {{name}} | Glossary: estudiante, not alumno |
| ar/content.json | `dialogSubtitle` | مادة لدورة «{{course}}». | للدورة «{{course}}». | "مادة لدورة" was redundant |
| ar/content.json | `active` | مفعّل | مفعّلة | Agrees with مادة (feminine) |
| ar/content.json | `inactive` | غير مفعّل | غير مفعّلة | Agrees with مادة (feminine) |
| ar/content.json | `moveUp` | تحريك لأعلى | نقل لأعلى | Same verb as other move buttons (نقل) |
| ar/content.json | `moveDown` | تحريك لأسفل | نقل لأسفل | Same verb as other move buttons (نقل) |
| ar/content.json | `deleteConfirm` | هل تريد حذف هذه المادة؟ سيُحذف ملفها أيضًا. | حذف هذه المادة؟ سيُحذف ملفها أيضًا. | Confirm title is a masdar question, not "هل تريد" |
| ar/content.json | `deleteConfirmLink` | هل تريد حذف هذه المادة؟ | حذف هذه المادة؟ | Confirm title is a masdar question, not "هل تريد" |
| ar/nav.json | `openMenu` | افتح القائمة | فتح القائمة | Button labels use the masdar |
| ar/nav.json | `closeMenu` | أغلق القائمة | إغلاق القائمة | Button labels use the masdar |
| ar/nav.json | `parent.recorded` | الدورات المسجلة لأبنائي | الدورات المسجّلة لأبنائي | Glossary spelling مسجّلة |
| ar/nav.json | `parent.rate` | قيّم حصص أبنائي | تقييم حصص أبنائي | Glossary: menu labels are nouns, not imperative + "my" |
| es/nav.json | `payrollProjections` | Previsión de salarios | Proyecciones salariales | Glossary: projections = proyecciones |
| es/nav.json | `parent.rate` | Valora las clases de tus hijos | Valorar las sesiones de mis hijos | Glossary: sesión; same person as the other parent menu items |
| ar/timezones.json | `city.UTC` | التوقيت العالمي (UTC) | التوقيت العالمي المنسَّق (UTC) | Full name of UTC |
| ar/features.json | `heldBy` | متوقفة: تحتاج {{names}} | معلّقة: تحتاج إلى {{names}} | "Held off" is pending, not "off"; تحتاج إلى |
| ar/features.json | `state.off` | متوقفة | غير مفعّلة | Glossary: features are مفعّلة / غير مفعّلة |
| es/features.json | `groups.money` | Dinero | Finanzas | "Dinero" is too literal for a settings group |
