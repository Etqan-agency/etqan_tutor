# Translation review, group 2 (Agent 4)

Date: 2026-11-01. Files: scheduling, recorded, errors, curriculum, vouchers, access, homework, quickLogin,
academySettings, sessionTimes, systemStatus, signIn, availability, home (`dashboard/src/locales/{ar,es}`).
Rules: `round-3/glossary.md`. English unchanged. Keys and placeholders unchanged.

**177 strings changed** (153 Arabic, 24 Spanish).

## Changes

| Lang | File | Key | Before | After | Why |
|---|---|---|---|---|---|
| ar | home | `useSidebar` | تجد صفحاتك في القائمة الجانبية، اختر منها ما تريد للبدء. | صفحاتك في القائمة الجانبية. اختر إحداها لتبدأ. | run-on comma; smoother |
| ar | availability | `subtitle` | فترات أسبوعية بتوقيت الأكاديمية. الجدولة خارجها مسموحة مع تنبيه. | فترات أسبوعية بتوقيت الأكاديمية. يمكنك الجدولة خارجها، مع ظهور تنبيه. | clunky literal phrasing |
| ar | availability | `remove` | احذف الفترة من {{start}} إلى {{end}} يوم {{day}} | إزالة الفترة من {{start}} إلى {{end}} يوم {{day}} | button label: masdar; Remove = إزالة |
| ar | availability | `outside` | خارج المواعيد المتاحة لـ {{teacher}} | خارج مواعيد {{teacher}} المتاحة | awkward لـ construction |
| ar | availability | `outsideSession` | هذا خارج المواعيد المتاحة لـ {{teacher}}. | هذا خارج مواعيد {{teacher}} المتاحة. | awkward لـ construction |
| ar | availability | `errors.endAfterStart` | اجعل نهاية الفترة بعد بدايتها. | يجب أن تنتهي الفترة بعد بدايتها. | literal calque |
| ar | signIn | `throttled` | محاولات كثيرة، حاول لاحقًا. | محاولات كثيرة جدًا. حاول مرة أخرى لاحقًا. | run-on; clearer |
| ar | signIn | `useRecovery` | استخدم رمز استرداد | استخدام رمز استرداد | link/button: masdar |
| ar | signIn | `useAuthenticator` | استخدم رمز تطبيق المصادقة | استخدام رمز تطبيق المصادقة | link/button: masdar |
| ar | signIn | `mfaExpired` | انتهت مهلة تسجيل الدخول، سجّل الدخول من جديد. | انتهت مهلة تسجيل الدخول. سجّل الدخول من جديد. | run-on comma |
| ar | signIn | `mfaLocked` | رموز خاطئة كثيرة، سجّل الدخول من جديد. | أدخلت رموزًا خاطئة عدة مرات. سجّل الدخول من جديد. | telegraphic phrasing |
| ar | systemStatus | `runNow` | طابق الاشتراكات الآن | مطابقة الاشتراكات الآن | button: masdar, not imperative |
| ar | systemStatus | `runHelp` | يطبّق الإيقافات المؤقتة، وينهي الاشتراكات التي حان موعد انتهائها، وينشئ الحصص القادمة، تمامًا كما تفعل المهمة التي تعمل كل ساعة. | يطبّق التجميد، وينهي الاشتراكات التي حان موعد انتهائها، وينشئ الحصص القادمة، كما تفعل المهمة التي تعمل كل ساعة. | glossary: pause = تجميد |
| ar | systemStatus | `runOpen` | هناك تشغيل قيد التنفيذ بالفعل. | هناك عملية تشغيل جارية بالفعل. | smoother |
| ar | systemStatus | `count.expired` | اشتراكات انتهت: {{count}} | اشتراكات منتهية: {{count}} | label style |
| ar | systemStatus | `count.paused` | اشتراكات أُوقفت مؤقتًا: {{count}} | اشتراكات مجمَّدة: {{count}} | glossary: paused = مجمَّد |
| ar | systemStatus | `count.resumed` | اشتراكات استُؤنفت: {{count}} | اشتراكات مستأنفة: {{count}} | label style |
| ar | systemStatus | `retry` | أعد المحاولة | حاول مرة أخرى | glossary: Try again |
| ar | systemStatus | `failure.suspended` | الأكاديمية موقوفة، لذلك لم يتم التشغيل. | لم يُنفَّذ التشغيل لأن الأكاديمية موقوفة. | natural order; no لم يتم |
| ar | sessionTimes | `times.inAt` | دخلت {{time}} | الدخول {{time}} | دخلت read as 1st/3rd person; shown to office too |
| ar | sessionTimes | `times.outAt` | خرجت {{time}} | الخروج {{time}} | same |
| ar | sessionTimes | `postpone.closedAt` | أُغلق التأجيل عند {{time}} | انتهت مهلة التأجيل الساعة {{time}} | literal 'closed' |
| es | sessionTimes | `times.lockedPaid` | Las horas no cambian en una sesión ya pagada en una nómina. | Las horas no se pueden cambiar en una sesión ya pagada en un recibo de pago. | glossary: payslip = recibo de pago |
| ar | academySettings | `schedulingHint` | تُنشأ الحصص لهذا العدد من الأيام القادمة. بعد تاريخ انتهائه يستمر الاشتراك في توليد الحصص طوال أيام المهلة، ثم ينتهي. | تُنشأ الحصص مسبقًا لهذا العدد من الأيام. وبعد تاريخ انتهاء الاشتراك، يستمر في توليد الحصص طوال أيام المهلة، ثم ينتهي. | pronoun before its noun; unclear |
| ar | academySettings | `autoInvoice` | أصدر فاتورة لكل اشتراك جديد أو مجدَّد | إصدار فاتورة لكل اشتراك جديد أو مجدَّد | toggle label: masdar |
| ar | academySettings | `dueDays` | مهلة سداد الفاتورة (بالأيام) | مهلة دفع الفاتورة (بالأيام) | glossary: avoid سداد |
| ar | academySettings | `invoicesHint` | تكون الفاتورة بسعر الاشتراك وتُصدر باسم أول وليّ أمر للطالب. الاشتراك المجاني لا فاتورة له. | تُصدر الفاتورة بسعر الاشتراك باسم أول وليّ أمر للطالب، ولا تُصدر فاتورة للاشتراك المجاني. | awkward 'لا فاتورة له' |
| ar | academySettings | `supervisionHint` | يمكن بعدها تعيين مشرفين على الاشتراكات والحصص، ليفتحوا حصصهم ويسجّلوا حضورهم. | عند تفعيله يمكنك تعيين مشرفين على الاشتراكات والحصص، ويمكنهم فتح حصصهم وتسجيل حضورهم. | clearer subject |
| es | academySettings | `dueDays` | Las facturas vencen a los (días) | Días para el vencimiento de las facturas | broken phrase 'vencen a los (días)' |
| es | academySettings | `invoicesHint` | La factura es por el precio de la suscripción y se cobra al primer tutor legal del estudiante. Una suscripción gratuita no genera factura. | La factura es por el precio de la suscripción y se emite a nombre del primer padre o madre del estudiante. Una suscripción gratuita no genera factura. | glossary: guardian = padre o madre |
| ar | quickLogin | `bulkDone` | تم إرسال {{sent}} وتخطي {{skipped}}. | تم إرسال {{sent}}، وتخطّي {{skipped}}. | punctuation, shadda |
| ar | quickLogin | `error` | حدث خطأ. حاول مرة أخرى. | حدث خطأ ما. حاول مرة أخرى. | glossary generic fallback |
| ar | quickLogin | `skipped.not_found` | لم يتم العثور على هذا الشخص. | لم يُعثر على هذا الشخص. | avoid لم يتم |
| ar | quickLogin | `skipped.no_login` | هذا الشخص ليس لديه تسجيل دخول. | ليس لهذا الشخص حساب لتسجيل الدخول. | literal 'has no sign-in' |
| ar | quickLogin | `skipped.recent` | أُرسل رابط منذ لحظات. حاول بعد بضع دقائق. | أُرسل رابط منذ لحظات. حاول مرة أخرى بعد بضع دقائق. | glossary: try again |
| ar | quickLogin | `pageHint` | اضغط الزر لتسجيل الدخول. | اضغط على الزر لتسجيل الدخول. | missing preposition |
| ar | quickLogin | `log.empty` | لا شيء مسجل بعد | لا توجد سجلات بعد | glossary empty-state pattern |
| ar | quickLogin | `log.actor` | بواسطة | المنفّذ | avoid agentive بواسطة |
| ar | quickLogin | `log.kind.return` | العودة إلى الحساب | العودة إلى حسابه | EN 'own account' |
| ar | quickLogin | `noToken` | لم يعد رابط الدخول في هذه الصفحة. افتح الرابط من بريدك الإلكتروني مرة أخرى، أو سجّل الدخول بكلمة المرور. | لم تعد هذه الصفحة تحتوي على رابط الدخول. افتح الرابط من بريدك الإلكتروني مرة أخرى، أو سجّل الدخول بكلمة المرور. | garbled first sentence |
| es | quickLogin | `banner` | Estás navegando como {{name}}, con la sesión de {{actor}}. | Estás navegando como {{name}}; {{actor}} inició esta sesión. | 'con la sesión de' misread |
| ar | errors | `conflict` | غيّر شخص آخر هذا. أعد التحميل وحاول مرة أخرى. | عدّل شخص آخر هذه البيانات. أعد التحميل وحاول مرة أخرى. | literal 'changed this' |
| ar | errors | `scheduling.pause_overlaps` | يتداخل هذا الإيقاف مع إيقاف آخر. | تتداخل فترة التجميد هذه مع فترة تجميد أخرى. | glossary: pause = تجميد |
| ar | errors | `scheduling.pause_not_current` | لا يمكن إنهاء إلا الإيقاف الجاري اليوم. | لا يمكن إنهاء التجميد مبكرًا إلا إذا كان ساريًا اليوم. | glossary: تجميد; clearer |
| ar | errors | `scheduling.pause_started` | لا يمكن حذف إلا إيقاف لم يبدأ بعد. | لا يمكن حذف التجميد إلا إذا لم يبدأ بعد. | glossary: تجميد |
| ar | errors | `scheduling.archived` | هذا مؤرشف. استرجعه أولًا. | هذا العنصر مؤرشف. استعده أولًا. | glossary: Restore = استعادة |
| ar | errors | `scheduling.schedule_deleted` | هذا الجدول محذوف. استرجعه أولًا. | هذا الجدول محذوف. استعده أولًا. | glossary: Restore = استعادة |
| ar | errors | `scheduling.session_marked` | سُجِّل الحضور على هذه الحصة. | سُجّل الحضور في هذه الحصة بالفعل. | preposition; match sibling |
| ar | errors | `scheduling.trial_scheduled` | لهذه الحصة التجريبية حصة بالفعل. عدّل تلك الحصة أو ألغها أولًا. | لطلب الحصة التجريبية هذا حصة مجدولة بالفعل. عدّلها أو ألغِها أولًا. | 'trial has a session' read oddly |
| ar | errors | `scheduling.nothing_to_renew` | لا شيء في هذه الحزمة يمكن تجديده. | لا يوجد في هذه الحزمة ما يمكن تجديده. | word order |
| ar | errors | `billing.already_refunded` | هذه الدفعة مستردة مسبقًا. | استُردّت هذه الدفعة من قبل. | more natural |
| ar | errors | `wallet.insufficient_balance` | الرصيد لا يغطي هذا. | الرصيد لا يكفي لهذا المبلغ. | literal 'cover' |
| ar | errors | `wallet.nothing_due` | لا شيء مستحق على هذه الفاتورة. | لا يوجد مبلغ مستحق على هذه الفاتورة. | match billing.nothing_due |
| ar | errors | `wallet.topup_paid` | هذا الشحن مدفوع مسبقًا. | دُفع هذا الشحن من قبل. | more natural |
| ar | errors | `vouchers.wrong_kind` | يمكن تطبيق كود الخصم فقط على الفاتورة. | لا يُطبَّق على الفاتورة إلا كود خصم. | misplaced فقط changed meaning |
| ar | errors | `payroll.rate_exists` | هذا الأجر موجود بالفعل. عدّله بدلًا من ذلك. | هذا السعر موجود بالفعل. عدّله بدلًا من ذلك. | glossary: rate = سعر |
| ar | errors | `payroll.mixed_currencies` | هؤلاء المعلمون يتقاضون بعملات مختلفة. اختر معلمين بعملة واحدة. | يتقاضى هؤلاء المعلمون رواتبهم بعملات مختلفة. اختر معلمين بالعملة نفسها. | incomplete verb; natural order |
| ar | errors | `payroll.already_acknowledged` | تم تأكيد استلام هذا الراتب من قبل. | أُكّد استلام كشف الراتب هذا من قبل. | payslip = كشف راتب |
| ar | errors | `notifications.bad_placeholder` | استخدم المتغيرات المعروضة فقط. اكتب القوس مرتين لإظهاره. | استخدم المتغيرات المعروضة فقط. اكتب القوس المعقوف مرتين لإظهاره. | brace = قوس معقوف |
| ar | errors | `chat.recipient_unavailable` | لا يمكن لهذا الشخص استقبال الرسائل | لا يمكن لهذا الشخص استقبال الرسائل. | missing full stop |
| ar | errors | `server.fileTypeNotAllowed` | نوع هذا الملف غير مسموح. | نوع هذا الملف غير مسموح به. | grammar |
| ar | errors | `server.postponeTerm` | اختر يومًا داخل مدة الاشتراك وخارج فترات إيقافه. | اختر يومًا داخل مدة الاشتراك وخارج فترات تجميده. | glossary: pause = تجميد |
| ar | errors | `server.fileContentMismatch` | محتوى الملف لا يطابق نوعه؛ اختر ملفًا صحيحًا. | محتوى الملف لا يطابق نوعه؛ اختر ملفًا حقيقيًا من هذا النوع. | meaning lost |
| es | errors | `catalogue.in_use` | Tiene suscripciones, así que no se puede eliminar. Desactívalo en su lugar. | Lo usan suscripciones o códigos del sistema, así que no se puede eliminar. Desactívalo en su lugar. | dropped 'system codes' |
| es | errors | `scheduling.freeze_days_exceeded` | Eso supera los días de congelamiento que quedan. | Eso supera los días de pausa que quedan. | glossary: pausa, not congelamiento |
| es | errors | `scheduling.already_compensated` | Esta sesión ya tiene una sesión de recuperación. | Esta sesión ya se recuperó o se compensó. | meaning: made up or compensated |
| es | errors | `scheduling.has_compensation` | Esta sesión tiene una sesión de recuperación, así que no se puede cambiar ni eliminar. | Esta sesión ya se recuperó o se compensó, así que no se puede cambiar ni eliminar. | same |
| ar | access | `roles.subtitle` | ما يتيحه كل دور لأعضائه من اطلاع وعمل. | ما يمكن لأعضاء كل دور رؤيته وفعله. | stiff phrasing |
| ar | access | `roles.tabs.widgets` | الأدوات | عناصر لوحة التحكم | الأدوات = tools, wrong concept |
| ar | access | `roles.retiredDone` | أُوقف الدور. يبقى لأعضائه لكنه لا يمنح شيئًا. | أُوقف الدور. يبقى مع أعضائه، لكنه لم يعد يمنحهم أي صلاحية. | clearer |
| ar | access | `roles.verbHint` | «عرض» يفتح سجلًا واحدًا من رابط إليه، و«عرض الكل» يفتح القائمة وعنصرها في القائمة الجانبية. اختر الاثنين ليتصفح الأعضاء السجلات. | «عرض» يفتح سجلًا واحدًا من رابط إليه، و«عرض الكل» يفتح صفحة القائمة ويُظهر رابطها في القائمة الجانبية. حدّد الخيارين ليتمكن الأعضاء من تصفح السجلات. | repeated القائمة; clearer |
| ar | access | `roles.errors.unheldList` | صلاحيات لا تملكها: {{codes}}. | لا يمكنك منح صلاحيات لا تملكها: {{codes}}. | fragment |
| ar | access | `staff.addBody` | تصله دعوة بالبريد الإلكتروني لتعيين كلمة المرور. | ستصله دعوة بالبريد الإلكتروني ليعيّن كلمة المرور. | natural |
| ar | access | `staff.editBody` | اسمه وبريده وأدواره وإمكانية دخوله. | اسمه وبريده الإلكتروني وأدواره، وهل يمكنه تسجيل الدخول. | literal 'إمكانية دخوله' |
| es | access | `roles.errors.addUnheld` | Solo puedes añadir permisos que tú mismo tienes. | Solo puedes agregar permisos que tú mismo tienes. | glossary: agregar |
| es | access | `roles.errors.unheldList` | No puedes concederlos: {{codes}}. | No puedes conceder estos permisos: {{codes}}. | clearer |
| es | access | `staff.addBody` | Recibirán una invitación por correo para crear su contraseña. | Recibirá una invitación por correo para crear su contraseña. | singular person |
| ar | homework | `dialog.markComplete` | تحديد كمكتمل | إكمال الواجب | calque 'تحديد كمكتمل' |
| ar | homework | `dialog.answeredBy` | أجاب: {{name}} | أجاب عنه {{name}} | fragment with colon |
| ar | homework | `dialog.completeLocked` | هذا الواجب مكتمل ولا يمكن الإجابة عليه بعد الآن. | هذا الواجب مكتمل ولا يمكن الإجابة عنه بعد الآن. | preposition (عن) |
| ar | homework | `toast.set` | تم تكليف الواجب. | تم التكليف بالواجب. | glossary: تكليف بواجب |
| ar | homework | `toast.completed` | تم تحديد الواجب كمكتمل. | تم إكمال الواجب. | calque 'تحديد كمكتمل' |
| ar | homework | `empty.filtered` | لا توجد واجبات تطابق هذه المرشحات. | لا توجد واجبات تطابق عوامل التصفية هذه. | consistent filter term |
| ar | homework | `errors.homework_answered` | تمت الإجابة عن هذا الواجب: لا يمكن حذفه الآن إلا من المكتب. | تمت الإجابة عن هذا الواجب: لا يمكن الآن حذفه إلا من الإدارة. | 'المكتب' literal 'office' |
| ar | vouchers | `list.copy` | انسخ {{code}} | نسخ {{code}} | button: masdar |
| ar | vouchers | `generate.validDays` | مدة الصلاحية (أيام) | مدة الصلاحية (بالأيام) | consistent unit label |
| ar | vouchers | `generate.sessions` | في هذه الباقة {{count}} حصة. | عدد حصص هذه الباقة: {{count}}. | fixed noun wrong for most counts |
| ar | vouchers | `redeem.action` | استخدام لطالب | استخدامه لطالب | missing object |
| ar | vouchers | `apply.action` | استخدام كود | تطبيق كود | match apply.save تطبيق |
| ar | vouchers | `apply.title` | استخدام كود خصم | تطبيق كود خصم | match apply.save تطبيق |
| ar | vouchers | `family.titles.playlist` | رمز دورة مسجلة | كود دورة مسجلة | glossary: redeemable = كود |
| ar | vouchers | `family.noStudents` | لا يوجد طالب نشط لبدء هذا الاشتراك له. | لا يوجد طالب نشط يمكن بدء هذا الاشتراك له. | awkward له |
| ar | vouchers | `family.noRenewable` | لا يمكن تجديد أي من اشتراكاتك بهذا الكود. فهو يجدّد اشتراكًا في {{course}} نشطًا أو موقوفًا أو منتهيًا ولم يُجدَّد بعد. | لا يمكن تجديد أي من اشتراكاتك بهذا الكود. فهو يجدّد اشتراكًا في {{course}} نشطًا أو مجمَّدًا أو منتهيًا ولم يُجدَّد بعد. | glossary: paused = مجمَّد |
| ar | vouchers | `family.discountHint` | افتح الفاتورة التي تريد تخفيضها واستخدم الكود فيها. | افتح الفاتورة التي تريد الخصم منها واستخدم الكود فيها. | glossary: avoid تخفيض |
| ar | vouchers | `family.openCourse` | افتح الدورة | فتح الدورة | button: masdar |
| ar | vouchers | `family.renewed` | جُدّد الاشتراك، ودفع الكود فاتورته. | جُدّد الاشتراك، ودُفعت فاتورته بالكود. | literal 'the code paid' |
| ar | vouchers | `family.another` | أدخل كودًا آخر | إدخال كود آخر | button: masdar |
| ar | curriculum | `levels.nameEn` | الاسم (الإنجليزية) | الاسم (بالإنجليزية) | match other forms |
| ar | curriculum | `levels.nameAr` | الاسم (العربية) | الاسم (بالعربية) | match other forms |
| ar | curriculum | `levels.topicCount` | {{count}} موضوعات | الموضوعات: {{count}} | fixed plural wrong for 11+ |
| ar | curriculum | `quran.empty` | لا توجد سور بعد. زامن لتحميل السور الـ114. | لا توجد سور بعد. استخدم «مزامنة السور» لتحميل السور الـ114. | 'زامن' awkward |
| ar | curriculum | `progress.noTopics` | لا موضوعات في هذا المستوى بعد. | لا توجد موضوعات في هذا المستوى بعد. | glossary empty-state pattern |
| ar | curriculum | `progress.open` | فتح التقدّم | عرض التقدّم | 'فتح التقدم' literal |
| ar | curriculum | `upgrades.askedBy` | طلبه | صاحب الطلب | column header: noun |
| ar | curriculum | `errors.level_in_use` | لدى طلاب سجلات في هذا المستوى: عطّله بدلًا من حذفه. | لبعض الطلاب سجلات في هذا المستوى: عطّله بدلًا من حذفه. | indefinite subject awkward |
| ar | recorded | `form.basic` | أساسي | المعلومات الأساسية | section header |
| ar | recorded | `form.discountTooHigh` | لا يمكن أن يزيد الخصم عن السعر. | لا يمكن أن يزيد الخصم على السعر. | preposition |
| ar | recorded | `my.emptyChild` | لا يوجد اشتراك في أي دورة مسجلة باسم {{name}} بعد. | {{name}} غير مشترك في أي دورة مسجلة بعد. | convoluted |
| ar | recorded | `my.markWatched` | تحديد كمشاهَد | وضع علامة «تمت المشاهدة» | calque 'تحديد كمشاهَد' |
| ar | recorded | `my.readOnly` | أنت تشاهد دورة ابنك. | أنت تتصفح دورة ابنك. | تشاهد = watch (video) |
| ar | recorded | `store.open` | افتح الدورة | فتح الدورة | button: masdar |
| ar | recorded | `store.lessons_zero` | {{count}} درس | لا دروس | glossary zero form |
| ar | recorded | `discussion.add` | أضف تعليقًا | إضافة تعليق | field label: masdar |
| ar | recorded | `discussion.deleteThreadConfirm` | حذف هذا التعليق؟ سيتم حذف ردود الأكاديمية عليه أيضًا. لا يمكن التراجع عن ذلك. | حذف هذا التعليق؟ ستُحذف ردود الأكاديمية عليه أيضًا. لا يمكن التراجع عن ذلك. | glossary: no سيتم |
| ar | recorded | `review.stars_zero` | {{count}} نجمة | لا نجوم | glossary zero form |
| ar | recorded | `review.saved` | شكرًا لك. أُرسل تقييمك للموافقة. | شكرًا لك. أُرسل تقييمك إلى الأكاديمية للمراجعة. | literal |
| ar | recorded | `comments.deleteConfirm` | هل تحذف هذا التعليق وردوده؟ | حذف هذا التعليق وردوده؟ | glossary confirm style |
| ar | recorded | `rating.count_zero` | {{count}} تقييم | لا تقييمات | glossary zero form |
| ar | recorded | `return.open` | افتح دوراتي المسجلة | فتح دوراتي المسجلة | button: masdar |
| ar | recorded | `errors.certificates_off` | الشهادات متوقفة في هذه الأكاديمية. | ميزة الشهادات غير مفعّلة في هذه الأكاديمية. | glossary: features مفعّلة |
| ar | recorded | `errors.price_changed` | تغيّر السعر. اشترِ مرة أخرى. | تغيّر السعر. حاول الشراء مرة أخرى. | 'اشترِ مرة أخرى' reads as 'buy again' |
| ar | recorded | `errors.free` | هذه الدورة مجانية: اشترك بدلًا من ذلك. | هذه الدورة مجانية: سجّل فيها مجانًا بدلًا من ذلك. | clearer |
| ar | scheduling | `status.paused` | موقوف مؤقتًا | مجمَّد | glossary: subscription status مجمَّد |
| ar | scheduling | `bulk.outcome.unarchive` | استُرجعت: {{done}} · تعذّر استرجاعها: {{skipped}} | استُعيدت: {{done}} · تعذّرت استعادتها: {{skipped}} | glossary: Restore = استعادة |
| ar | scheduling | `bulk.archiveBody_zero` | ستختفي الحصص المحددة من القائمة، ويمكن استرجاعها من الأرشيف. | ستختفي الحصص المحددة من القائمة، ويمكن استعادتها من الأرشيف. | glossary: استعادة |
| ar | scheduling | `bulk.archiveBody_one` | ستختفي الحصة المحددة من القائمة، ويمكن استرجاعها من الأرشيف. | ستختفي الحصة المحددة من القائمة، ويمكن استعادتها من الأرشيف. | glossary: استعادة |
| ar | scheduling | `bulk.archiveBody_two` | ستختفي الحصتان المحددتان من القائمة، ويمكن استرجاعهما من الأرشيف. | ستختفي الحصتان المحددتان من القائمة، ويمكن استعادتهما من الأرشيف. | glossary: استعادة |
| ar | scheduling | `bulk.archiveBody_few` | ستختفي {{count}} حصص محددة من القائمة، ويمكن استرجاعها من الأرشيف. | ستختفي {{count}} حصص محددة من القائمة، ويمكن استعادتها من الأرشيف. | glossary: استعادة |
| ar | scheduling | `bulk.archiveBody_many` | ستختفي {{count}} حصة محددة من القائمة، ويمكن استرجاعها من الأرشيف. | ستختفي {{count}} حصة محددة من القائمة، ويمكن استعادتها من الأرشيف. | glossary: استعادة |
| ar | scheduling | `bulk.archiveBody_other` | ستختفي {{count}} حصة محددة من القائمة، ويمكن استرجاعها من الأرشيف. | ستختفي {{count}} حصة محددة من القائمة، ويمكن استعادتها من الأرشيف. | glossary: استعادة |
| ar | scheduling | `bulk.unarchiveTitle` | استرجاع الحصص المحددة؟ | استعادة الحصص المحددة؟ | glossary: استعادة |
| ar | scheduling | `renew.early` | يبدأ التجديد ({{day}}) قبل نهاية الفترة الحالية ({{end}}): تُحذف حصص الفترة الحالية من هذا اليوم، ويُكمل التجديد بحصصه. | يبدأ التجديد ({{day}}) قبل نهاية المدة الحالية ({{end}}): تُحذف حصص المدة الحالية بدءًا من ذلك اليوم، ويستمر التجديد بحصصه. | glossary: term = مدة |
| ar | scheduling | `renew.body` | مدة جديدة بأرقام الباقة الحالية والمواعيد الأسبوعية نفسها. | مدة جديدة تبدأ فيها أرقام الباقة من الصفر، بالمواعيد الأسبوعية نفسها. | mistranslated: said 'current' numbers |
| ar | scheduling | `renew.carries_zero` | ستُرحَّل {{count}} حصة إضافية من هذه المدة إلى التجديد وتُخصم منه. | لن تُرحَّل أي حصة إضافية من هذه المدة إلى التجديد. | glossary zero form |
| ar | scheduling | `inGraceUntil` | في المهلة حتى {{date}} | ضمن مهلة التجديد حتى {{date}} | unclear 'في المهلة' |
| ar | scheduling | `summary.scheduledLeft_zero` | لا حصة منها مجدولة في هذه الفترة الآن. | لا توجد منها حصص مجدولة في هذه الفترة الآن. | awkward |
| ar | scheduling | `slots.removeGroup` | حذف هذه المواعيد | إزالة هذه المواعيد | glossary: Remove = إزالة |
| ar | scheduling | `slots.fewerThanPackage` | الباقة {{perWeek}} حصص أسبوعيًا، واخترت {{chosen}}. المواعيد الأقل لا تتسع لكل حصصها قبل تاريخ الانتهاء. أضف مواعيد الآن أو لاحقًا. | عدد حصص الباقة في الأسبوع {{perWeek}}، واخترت {{chosen}}. لا تتسع المواعيد الأقل لكل حصصها قبل تاريخ الانتهاء. أضف مواعيد الآن أو لاحقًا. | fixed plural wrong for 1, 2, 11+ |
| ar | scheduling | `slots.editBody` | الأوقات بتوقيت الأكاديمية. لا يتغير اليوم من هنا: لنقل الموعد إلى يوم آخر أضف موعدًا جديدًا وأوقف هذا. تغيير الوقت يستبدل حصصه التي لم يُسجَّل فيها شيء بعد. | الأوقات بتوقيت الأكاديمية. لا يمكن تغيير اليوم من هنا: لنقل الموعد إلى يوم آخر، أضف موعدًا جديدًا وأوقف هذا الموعد. تغيير الوقت يستبدل حصصه التي لم يُسجَّل فيها شيء بعد. | 'لا يتغير اليوم' literal |
| ar | scheduling | `errors.minutesRange` | من 15 إلى 240 دقيقة. | أدخل من 15 إلى 240 دقيقة. | fragment, no verb |
| ar | scheduling | `errors.pauseOrder` | اجعل نهاية الإيقاف في يوم بدايته أو بعده. | اجعل نهاية التجميد في يوم بدايته أو بعده. | glossary: pause = تجميد |
| ar | scheduling | `pauses.left_zero` | متبقٍ {{left}} من {{count}} يوم تجميد | لا توجد أيام تجميد | glossary: fraction-style counts |
| ar | scheduling | `pauses.left_one` | متبقٍ {{left}} من يوم تجميد واحد | المتبقي {{left}} من يوم التجميد | glossary: fraction-style counts |
| ar | scheduling | `pauses.left_two` | متبقٍ {{left}} من يومَي تجميد | المتبقي {{left}} من يومَي التجميد | glossary: fraction-style counts |
| ar | scheduling | `pauses.left_few` | متبقٍ {{left}} من {{count}} أيام تجميد | المتبقي {{left}} من أيام التجميد ({{count}}) | glossary: fraction-style counts |
| ar | scheduling | `pauses.left_many` | متبقٍ {{left}} من {{count}} يومًا للتجميد | المتبقي {{left}} من أيام التجميد ({{count}}) | glossary: fraction-style counts |
| ar | scheduling | `pauses.left_other` | متبقٍ {{left}} من {{count}} يوم تجميد | المتبقي {{left}} من أيام التجميد ({{count}}) | glossary: fraction-style counts |
| ar | scheduling | `pauses.endBody` | ينتهي التجميد بالأمس، فتُستردّ أيام التجميد غير المستخدمة ويتقدّم تاريخ الانتهاء. التجميد الذي بدأ اليوم يُحذف. | يُعدّ التجميد منتهيًا بالأمس، فتُستردّ أيام التجميد غير المستخدمة ويتقدّم تاريخ الانتهاء. أما التجميد الذي بدأ اليوم فيُحذف. | 'ينتهي بالأمس' tense clash |
| ar | scheduling | `pauses.renewedWarning` | لهذا الاشتراك تجديد يليه. التجميد يؤخّر نهاية هذه الفترة إلى ما بعد بداية التجديد، فتتداخل الفترتان. | لهذا الاشتراك تجديد يليه. التجميد يؤخّر نهاية هذه المدة إلى ما بعد بداية التجديد، فتتداخل المدتان. | glossary: term = مدة |
| ar | scheduling | `session.startAsHost` | ابدأ كمضيف | البدء كمضيف | button: masdar |
| ar | scheduling | `session.restored` | استُرجعت الحصة. | استُعيدت الحصة. | glossary: استعادة |
| ar | scheduling | `generate.title` | إنشاء الحصص لفترة | إنشاء الحصص | EN 'Generate sessions' |
| ar | scheduling | `generate.summary` | أُنشئ {{created}}. موجود مسبقًا {{existing}}. موقوف {{paused}}. خارج المدة {{outside}}. | أُنشئت: {{created}} · موجودة مسبقًا: {{existing}} · مجمَّدة: {{paused}} · خارج المدة: {{outside}} | agreement with حصص; glossary مجمَّد |
| ar | scheduling | `generate.conflicts` | {{count}} تعارضات في المواعيد: | تعارضات في المواعيد ({{count}}): | fixed plural wrong for 11+ |
| ar | scheduling | `mine.emptyWhen.today` | لا حصص اليوم. | لا توجد حصص اليوم. | glossary empty-state pattern |
| ar | scheduling | `mine.emptyWhen.week` | لا حصص هذا الأسبوع. | لا توجد حصص هذا الأسبوع. | glossary empty-state pattern |
| ar | scheduling | `mine.emptyWhen.past` | لا حصص سابقة بعد. | لا توجد حصص سابقة بعد. | glossary empty-state pattern |
| ar | scheduling | `mine.tabs.label` | أي الحصص | الحصص المعروضة | 'أي الحصص' literal |
| ar | scheduling | `staffHome.supervisionHint` | اليوم والقادمة | حصص اليوم والحصص القادمة | fragment |
| ar | scheduling | `supervision.mine.subtitle` | حصصك اليوم والحصص القادمة. افتح الحصة قبل بدئها بعشر دقائق. | حصصك اليوم والحصص القادمة. يمكنك فتح الحصة بدءًا من 10 دقائق قبل موعدها. | meaning: 'from' 10 min before |
| ar | scheduling | `supervision.mine.empty` | لا حصص للإشراف عليها. | لا توجد حصص للإشراف عليها. | glossary empty-state pattern |
| ar | scheduling | `supervision.mine.off` | نظام الإشراف العام متوقف في هذه الأكاديمية. | نظام الإشراف العام غير مفعّل في هذه الأكاديمية. | glossary: مفعّل |
| ar | scheduling | `supervision.mine.noLink` | لا رابط اجتماع لهذه الحصة. | ليس لهذه الحصة رابط لقاء. | consistent with رابط اللقاء |
| ar | scheduling | `supervision.mine.join` | الانضمام إلى الاجتماع | الانضمام إلى اللقاء | consistent with رابط اللقاء |
| es | scheduling | `renew.early` | La renovación empieza ({{day}}) antes de que termine el período actual ({{end}}): se quitan las clases del período actual desde ese día y la renovación sigue con las suyas. | La renovación empieza ({{day}}) antes de que termine el periodo actual ({{end}}): se quitan las sesiones del periodo actual desde ese día y la renovación sigue con las suyas. | glossary: sesión, not clase |
| es | scheduling | `slots.stopBody` | Se quitan sus próximas clases que nadie ha marcado; las marcadas se quedan. Puedes reanudar el horario más adelante. | Se quitan sus próximas sesiones que nadie ha marcado; las marcadas se quedan. Puedes reanudar el horario más adelante. | glossary: sesión |
| es | scheduling | `slots.deleteBody` | El horario se elimina definitivamente. No tiene clases, así que nada más cambia. | El horario se elimina definitivamente. No tiene sesiones, así que nada más cambia. | glossary: sesión |
| es | scheduling | `slots.fewerThanPackage` | El paquete es de {{perWeek}} sesiones por semana; elegiste {{chosen}}. Con menos horarios no caben todas sus sesiones antes de la fecha de fin. Añade horarios ahora o más tarde. | El paquete es de {{perWeek}} sesiones por semana; elegiste {{chosen}}. Con menos horarios no caben todas sus sesiones antes de la fecha de fin. Agrega horarios ahora o más tarde. | glossary: agregar |
| es | scheduling | `slots.editBody` | Los horarios son los de la academia. El día no se cambia aquí: para pasar el horario a otro día, añade uno nuevo y detén este. Una hora nueva reemplaza sus sesiones que nadie ha marcado todavía. | Los horarios son los de la academia. El día no se cambia aquí: para pasar el horario a otro día, agrega uno nuevo y detén este. Una hora nueva reemplaza sus sesiones que nadie ha marcado todavía. | glossary: agregar |
| es | scheduling | `pauses.left_one` | Queda {{left}} de {{count}} día de congelamiento | Queda {{left}} de {{count}} día de pausa | glossary: pausa |
| es | scheduling | `pauses.left_other` | Quedan {{left}} de {{count}} días de congelamiento | Quedan {{left}} de {{count}} días de pausa | glossary: pausa |
| es | scheduling | `pauses.endBody` | La pausa termina ayer: se devuelven los días de congelamiento no usados y la fecha de fin se adelanta. Una pausa que empezó hoy se elimina. | La pausa termina ayer: se devuelven los días de pausa no usados y la fecha de fin se adelanta. Una pausa que empezó hoy se elimina. | glossary: pausa |
| es | scheduling | `pauses.deleteBody` | La pausa se elimina definitivamente y se devuelven sus días de congelamiento. | La pausa se elimina definitivamente y se devuelven sus días de pausa. | glossary: pausa |
| es | scheduling | `attendance.clearStudentBody` | La asistencia del alumno vuelve a «Sin marcar»: la clase se devuelve a la suscripción y la sesión se reabre. | La asistencia del estudiante vuelve a «Sin marcar»: la sesión se devuelve a la suscripción y se reabre. | glossary: estudiante, sesión |
| es | scheduling | `sessions.atDisposalHint` | Apartada por la administración: no cuenta para el estudiante ni se paga salvo que la administración lo decida. Consulta a la oficina. | Apartada por la administración: no cuenta para el estudiante ni se paga salvo que la administración lo decida. Consulta a la administración. | 'oficina' literal |
| es | scheduling | `mine.opensHint` | El registro de entrada se abre 15 minutos antes de la clase; la asistencia, a la hora de inicio. | El registro de entrada se abre 15 minutos antes de que empiece la sesión; la asistencia, a la hora de inicio. | glossary: sesión |
| es | scheduling | `family.postponedFrom` | Aplazada desde {{from}} | Pospuesta desde {{from}} | glossary: pospuesta, not aplazada |

## Tests updated to the new wording

- `features/academy/AcademySettingsForm.test.tsx`: autoInvoice and dueDays labels.
- `locales/m12-settings-wording.test.ts`: dueDays (ETQAN-QA-1374) now «مهلة دفع الفاتورة (بالأيام)», since the glossary bans سداد.
- `lib/field-error.test.ts`: fileTypeNotAllowed.
- `features/access/RoleEditor.test.tsx`: unheldList and the verbHint regex.
- `features/vouchers/OfficeRedeemDialog.test.tsx`: «استخدامه لطالب».
- `features/vouchers/ApplyCode.test.tsx`: «تطبيق كود».
- `features/curriculum/StudentLevelsList.test.tsx`: «عرض التقدّم».
- `features/scheduling/countCopy.test.ts`: pauses.left, plus pausedDays, which already said «تجميد» before this pass but the test still expected «إيقاف».

## Left as they are (pinned by round-3 decisions or shared with files outside group 2)

- `homework.child`, `scheduling.family.child`, `recorded.my.childPicker`, `curriculum.progress.childPicker` «الابن/الابنة»: the glossary bans slash forms, but ETQAN-QA-1335 and the m15 test keep it the same as `certificates.child` and `reviews.child`, which are outside group 2. **Proposal:** change all 6 to «الابن» together and update `qa-round3-m15.test.tsx`.
- `signIn.invalidCode`: must equal `twoFactor.invalidCode` (ETQAN-QA-901). To swap «،» for «.», change both together.
- `homework.subtitle` (QA-267), `homework.dialog.assignedOn` (QA-1506), `homework.dialog.deleteConfirm*` (QA-1518, a body under the homework title, so it isn't a «هل أنت متأكد» title), `quickLogin.banner` AR (QA-931), `scheduling.generate.body` «كحد أقصى» (QA-1127): pinned on purpose and acceptable Arabic.

## Tests run (dashboard container, `--maxWorkers=1`)

- `locales.test.ts`, the m02/m03/m05/m06/m11/m15 and m08 r3 files, `qa-round2-a2`, `m12-settings-wording`, `countCopy`, `field-error`, `qa-round3-m07`, LoginForm, AcademySettingsForm, RoleEditor, OfficeRedeemDialog, ApplyCode, StudentLevelsList: everything that touches group-2 strings passes.
- Failures that already existed and come from files outside group 2 (not touched here):
  - `qa-round2-a2` ETQAN-QA-261 (es sessionClasses «Normales»);
  - `qa-round3-m02` QA-904 (twoFactor.download «.txt»);
  - `qa-round3-m05` QA-1422 (content.dialogSubtitle);
  - `qa-round3-m07` QA-1106 (sessionActivity.revert.body).
