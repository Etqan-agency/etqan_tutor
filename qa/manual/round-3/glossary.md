# Round 3 translation glossary (Arabic + Spanish)

Owner: Agent 4 (translation review), created 2026-11-01. Agent 3 follows this when rewriting copy.
Source: every `dashboard/src/locales/{ar,en,es}/*.json` (5,596 keys) plus `marketing/src/lib/i18n.ts`.
Rule used: **keep the term the UI already uses most**, unless it is wrong or unnatural. Counts in
brackets are how often the Arabic form appears today.

Bug IDs for translation findings: 1700–1799.

---

## 1. Canonical terms

### Teaching and scheduling
| Concept (EN) | Arabic: use | Arabic: avoid | Spanish: use | Notes |
|---|---|---|---|---|
| Session (live class) | حصة / الحصص (340) | جلسة، درس، محاضرة | sesión | `auth:studentEmpty` says "جلسات مجدولة": change it to حصص. |
| Consultation session | الجلسة (consultations only) | حصة | sesión | جلسة is used only inside the paid one-to-one consultation flow. |
| Lesson (recorded course unit) | درس / دروس | حصة | lección | Only for recorded-course content. For live lessons, use حصة: `registration:steps.preferences` "تفضيلات الدروس" should be "تفضيلات الحصص". |
| Trial session | حصة تجريبية | جلسة تجريبية | clase de prueba | |
| Make-up session | حصة تعويضية؛ to make up: تعويض | حصة بديلة | sesión de recuperación | |
| Postpone / postponed | تأجيل / مؤجَّلة | إعادة جدولة (for sessions) | posponer / pospuesta | ES: replace "Aplazada" in `scheduling:family.postponedFrom`. |
| Reschedule (consultations) | إعادة جدولة | | reprogramar | |
| Cancel / cancelled | إلغاء / ملغاة (f) ، ملغى (m) | | cancelar / cancelada | The status word agrees with its noun (see §3). |
| Attendance | الحضور؛ take attendance: تسجيل الحضور | التحضير | asistencia | |
| Present / absent / excused / late | حاضر / غائب / غائب بعذر / متأخر | غياب (as a status)، معتذر | presente / ausente / falta justificada / tarde | Fix `consultations:session.absent` "غياب" and `studentReports:…excused` "معتذر". |
| Schedule / scheduling | الجدول / الجدولة | | horario / programación | |
| Weekly slot | موعد أسبوعي / المواعيد الأسبوعية | فتحة، خانة | horario semanal | |
| Time zone | المنطقة الزمنية | التوقيت | zona horaria | |
| Course (live) | دورة / الدورات | كورس، مقرر، مادة | curso | |
| Recorded course | دورة مسجّلة | كورس مسجل | curso grabado | |
| Level / sub-level | مستوى / مستوى فرعي | مرحلة، درجة | nivel / subnivel | |
| Level upgrade | ترقية المستوى؛ request: طلب ترقية | رفع المستوى | subida de nivel | Change "قرار رفع المستوى" and "طلب رفع المستوى" to ترقية, to match the nav "طلبات الترقية". |
| Study group | مجموعة دراسية / المجموعة | فصل، كلاس | grupo de estudio | |
| Group session | حصة جماعية | | sesión grupal | |
| Homework | الواجب / الواجبات؛ to set: تكليف بواجب | فرض، مهمة | tarea | |
| Session report | تقرير الحصة؛ missing: تقارير ناقصة | | informe | |
| Certificate | شهادة | | certificado | |
| Curriculum | المنهج | | plan de estudios | |

### Subscriptions and billing
| Concept (EN) | Arabic: use | Arabic: avoid | Spanish: use | Notes |
|---|---|---|---|---|
| Subscription | اشتراك / الاشتراكات | عضوية | suscripción | |
| Term (one subscription period) | مدة الاشتراك؛ previous term: المدة السابقة | فترة (for a term) | periodo | فترة is for generic ranges and pauses. Fix `bundles:members.earlier` "فترة سابقة" to "مدة سابقة". |
| Renew / renewal | تجديد | | renovar / renovación | |
| Pause (subscription, bundle) | تجميد؛ state: مجمَّد؛ freeze days: أيام التجميد | إيقاف مؤقت (for subscriptions) | pausa; freeze days: días de pausa | The action is already تجميد, but the status says "موقوف مؤقتًا": make the subscription status مجمَّد. For a person's account, keep "موقوف مؤقتًا" (fix `people:status.paused` "متوقف مؤقتًا"). ES: don't mix pausa and congelamiento. |
| Resume | استئناف | | reanudar | |
| Package (catalogue plan) | باقة / الباقات | حزمة، خطة | paquete | |
| Bundle (group of subscriptions) | حزمة / الحزم | باقة | lote / paquete grupal | **Different concept from a package.** Never swap the two. |
| Invoice | فاتورة / فواتير | | factura | |
| Issued / due date / overdue | صادرة / تاريخ الاستحقاق / متأخرة | مستحقة متأخرة | emitida / vencimiento / vencida | |
| Paid / unpaid / draft | مدفوعة / غير مدفوعة / مسودة | | pagada / sin pagar / borrador | |
| Balance due (on an invoice) | المتبقي | الرصيد | saldo pendiente | |
| Payment (a record) / paying | دفعة / الدفع | سداد | pago | |
| Online payment | الدفع الإلكتروني / إلكترونيًا | أونلاين | pago en línea | |
| Payment gateway | بوابة الدفع | | pasarela de pago | |
| Refund / refunded | استرداد / مستردّة | إرجاع المال | reembolso / reembolsado | |
| Receipt | إيصال | وصل | recibo | |
| Discount | خصم | تخفيض | descuento | |
| Voucher / discount code | كود خصم (anything a family redeems: كود) | كوبون، قسيمة | código de descuento | See the code rule below. |
| Verification / sign-in code, currency code | رمز | كود | código | Rule: a code the family **redeems** is كود. A code for **security or a standard** is رمز. Fix `registration` waiting-list codes "إضافة رمز" to كود. |
| Wallet / balance | الرصيد (82) | محفظة | saldo | The UI has no "wallet" word, only رصيد. |
| Top up | شحن الرصيد؛ button: شحن | تعبئة | recargar / recarga | |
| Currency | العملة | | moneda | |
| Family (billing unit) | العائلة / العائلات | الأسرة | familia | Fix "للأسرة" (`wallet:reverse.body`) and "أسر جديدة" (`website:setup.steps.courses.tip`). |
| Family subscription (type) | عائلي | | familiar | |
| Terms and conditions | الشروط والأحكام | | términos y condiciones | |

### Payroll
| Concept (EN) | Arabic: use | Arabic: avoid | Spanish: use | Notes |
|---|---|---|---|---|
| Payroll | الرواتب | كشف الأجور | nómina | |
| Payslip | كشف راتب / كشوف الرواتب | قسيمة راتب | recibo de pago | ES: "nómina" means payroll, not a payslip. Fix `sessionTimes:times.lockedPaid` "en una nómina" and `payroll:balance.explained` "las nóminas pagadas". |
| Pay rates | الأسعار (in the payroll menu); in full: أسعار المعلمين | الأجور | tarifas | |
| Adjustment / bonus / deduction | تسوية / مكافأة / خصم | | ajuste / bonificación / deducción | |
| Withdrawal (request) | طلب سحب / طلبات السحب | | retiro / solicitud de retiro | |
| Payout method | طريقة الاستلام | طريقة الدفع | método de cobro | Fix `people:field.payout_method` "طريقة الدفع". It reads as "how to pay", the opposite meaning. |
| Projections | توقعات الرواتب | | proyecciones | |

### People and access
| Concept (EN) | Arabic: use | Arabic: avoid | Spanish: use | Notes |
|---|---|---|---|---|
| Student | الطالب / الطلاب | التلميذ | estudiante | ES: replace "alumno" (in `archives:simple.*` and `payroll:studentRates.noMatch`). |
| Teacher | المعلم / المعلمون؛ female: المعلمة | المدرّس، الأستاذ | profesor / profesora | No shadda: write معلم, not معلّم (shadda is fine in `registration`'s gender choice). |
| Parent / guardian | وليّ الأمر / أولياء الأمور | الوالد، الأهل | padre o madre; legal guardian: tutor legal | |
| Children (of a parent) | الأبناء / أبنائي | الأطفال (in nav) | hijos | |
| Staff / staff member | الموظفون / موظف | الطاقم، الفريق | personal / miembro del personal | |
| Admin | المدير / المديرون | المسؤول، الأدمن | administrador | |
| Owner | المالك | صاحب الأكاديمية | propietario | |
| Supervisor / supervision | المشرف / الإشراف | المراقب | supervisor / supervisión | |
| Role / permissions | الدور / الصلاحيات | | rol / permisos | |
| Tag | وسم / الوسوم | علامة، تاغ | etiqueta | |
| Academy | الأكاديمية | المعهد، المركز | academia | |
| Brand | إتقان (always in Arabic text) | Etqan | Etqan | |

### App and account
| Concept (EN) | Arabic: use | Spanish: use |
|---|---|---|
| Settings | الإعدادات | Configuración ("Ajustes" means payroll adjustments only) |
| Features (switches) | الميزات؛ on/off: مفعّلة / غير مفعّلة | funciones; activada / desactivada |
| Integrations | التكاملات | integraciones |
| Dashboard | لوحة التحكم | panel |
| Sign in / sign out | تسجيل الدخول / تسجيل الخروج | iniciar sesión / cerrar sesión |
| Account / profile | الحساب / الملف الشخصي | cuenta / perfil |
| Email / password | البريد الإلكتروني / كلمة المرور | correo / contraseña |
| Notifications | الإشعارات | notificaciones |
| Broadcast | رسالة جماعية / الرسائل الجماعية | difusión |
| Chat | المحادثات | chat |
| Inquiry | استفسار | consulta (in the inquiries context) |
| Registration / waiting list | التسجيل / قائمة الانتظار | registro / lista de espera |
| Archive (action / place / state) | أرشفة / الأرشيف / مؤرشف | archivar / archivo / archivado |
| Library / content | المكتبة / المحتوى | biblioteca / contenido |
| WhatsApp | واتساب | WhatsApp |
| Megabyte (MB) | ميجابايت (never ميغابايت; ETQAN-QA-1701) | MB |
| Maintenance (site status) | قيد الصيانة (not تحت الصيانة; ETQAN-QA-1702) | en mantenimiento |
| Hero carousel / slideshow | شرائح الغلاف؛ عرض شرائح (not عرض متحرك; ETQAN-QA-1703) | carrusel |
| Too many attempts | محاولات كثيرة. حاول مرة أخرى لاحقًا. (no جدًا; ETQAN-QA-1704) | Demasiados intentos |

### Standard button verbs
| EN | Arabic | Spanish |
|---|---|---|
| Save | حفظ | Guardar |
| Delete (permanent) / Remove (unlink) | حذف / إزالة | Eliminar / Quitar |
| Edit | تعديل | Editar |
| Add / Create | إضافة / إنشاء | Agregar / Crear |
| Cancel | إلغاء | Cancelar |
| Close | إغلاق | Cerrar |
| Restore | استعادة. Never استرجاع (fix in `archives:*.restore` and `schedules:bulk.restore`). | Restaurar |
| Approve / Reject (requests) | قبول / رفض. Fix "موافقة" (`payroll:withdrawals.approve`, `registration:admin.approve`) and "اعتماد" (`consultations:reviews.approve`). | Aprobar / Rechazar |
| Confirm | تأكيد | Confirmar |
| Back (button) / Back to X (link) | رجوع / العودة إلى X. Fix `registration:back` "السابق": that word is for "Previous" in paging. | Atrás / Volver a X |
| Next / Previous | التالي / السابق | Siguiente / Anterior |
| Send | إرسال | Enviar |
| Try again | حاول مرة أخرى. Not أعد المحاولة. | Intentar de nuevo |
| Download / Print / Copy | تنزيل / طباعة / نسخ | Descargar / Imprimir / Copiar |
| Done | تم | Listo |

---

## 2. Tone and grammar rules

1. **Buttons, menu items, tabs and dialog titles use the verbal noun (masdar):** حفظ، حذف الباقة،
   إضافة طالب، تجديد الاشتراك. This is what the UI already does, and it matches native Arabic
   software.
   - **The exception is the imperative.** Use it in sentences that tell the user what to do (اختر
     دورة، أدخل رقمًا صحيحًا) and in learner- or visitor-facing calls to action (احجز استشارة، اشحن
     رصيدك، اشترِ الدورة).
   - **Keep one style within a button group.** Don't put "احفظ" next to "إلغاء".
2. **Address the user in the second person singular, masculine generic** (يمكنك، اخترت، حسابك).
   - Never use slash or bracket gender forms such as (ة) or /ي, and never حضرتك.
   - Avoid "يرجى", "الرجاء" and "من فضلك". A direct imperative is polite enough: "انتظر لحظة ثم حاول مرة
     أخرى." Today "يرجى" appears in `account:throttled`, `account:genericError`,
     `auth:resendThrottled`, `auth:resetLinkInvalid`, `consultations:dialog.pickTeacherFirst`, and in
     marketing `contactMethodRequired` and `unavailableBody`.
3. **Menu labels are nouns, not commands, and keep one grammatical person.** Bad: "قيّم حصص أبنائي"
   (`nav:parent.rate`), which joins an imperative to "my". Good: "تقييم حصص أبنائي". Likewise
   "قيّم حصصك" becomes "تقييم الحصص".
4. **Success toasts** use "تم + masdar + noun." (dominant, 168 strings): "تم حفظ الوسم."
   - The passive "حُفظ التقرير." (24 strings) is acceptable. Don't rewrite it only for this reason,
     but new strings use تم.
   - Never add "بنجاح" (fix `gateways:return.paid`: "تم الدفع، شكرًا لك.").
5. **Error messages** use "تعذّر + masdar …" (with shadda: 110 strings use it, 6 omit it).
   - Explain the reason and the way out: "لا يمكن تعويض إلا حصة لم تُحتسب من الباقة."
   - Avoid "فشل" in sentences. It is fine as a status chip.
   - Avoid "حدث خطأ". The only exception is the single generic fallback: "حدث خطأ ما. حاول مرة أخرى."
6. **Empty states** use "لا توجد/لا يوجد + noun + بعد." and agree with the noun: لا توجد حصص بعد، لا يوجد
   موظفون بعد.
7. **Confirm dialogs** are a masdar question title plus a consequence body.
   - Title: "حذف الباقة «{{name}}»؟"
   - Body: "لا يمكن التراجع عن ذلك."
   - Never "هل أنت متأكد أنك تريد…".
8. **Future and passive forms** use the internal passive (سيُحذف، تُلغى، سيُجمَّد) rather than
   "سيتم + masdar". Fix `recorded:discussion.deleteThreadConfirm` and `website:redirects.deleteBody`.
9. **Status chips agree in gender with the noun they describe:**
   - الحصة: ملغاة، مؤجلة، مكتملة.
   - الفاتورة: مدفوعة، متأخرة.
   - الدفعة: مستردّة.
   - الاشتراك: ملغى، نشط، منتهٍ، مجمَّد.
   - Some keys are reused for nouns of both genders. If one key serves both, split it, or use a
     masdar such as "إلغاء".
10. **Numbers with nouns follow the plural rules.** Every `_zero/_one/_two/_few/_many/_other` set
    must be complete (52 of 54 sets already are).
    - zero: "لا حصص" or "لم …"
    - one: "حصة واحدة" (no {{count}})
    - two: the dual "حصتان" / "معلمَين" (no {{count}})
    - few (3–10): "{{count}} حصص"
    - many (11–99): the accusative singular "{{count}} طالبًا"
    - other (100+ and decimals): "{{count}} طالب"
    - Agreeing adjectives follow the same case: "{{count}} طلاب نشطين"، "{{count}} طالبًا نشطًا".
11. **Punctuation:**
    - Use Arabic ، ؟ ؛ and «» quotes. Don't use ASCII , ? ; or "".
    - No space before a colon.
    - Use the ellipsis "…".
    - Use the arrow ← for paths in RTL text: "الإعدادات ← الميزات".
    - Keep the em dash "—" rare. Prefer "،" or ":".
    - Numbers use Western digits (0–9), as the UI does today. Don't mix in ٠–٩.
12. **Tanween on alif:** put the fatḥatān on the letter before the alif: أولًا، قريبًا، مثلًا، لاحقًا،
    مؤقتًا، متاحًا (413 strings already do).
    - Fix the "ـاً" spellings in `ai:instructionsHint`, `ai:errors.timeout`, `ai:errors.throttled`,
      `consultations:dialog.pickTeacherFirst` and `integrations:services.ai.disconnectBody`.
    - Also fix the marketing strings `sent`, `unavailableTitle`, `unavailableBody` and
      `maintenanceBody`.
13. **English in Arabic strings** is allowed only for:
    - brand and product names (Stripe, PayPal, Zoom, Google, iPhone, Safari, Jitsi, Meta);
    - file formats (PNG, PDF);
    - protocols (SSL/TLS);
    - sample values (EGP, https://).

    Wrap Latin runs in ⁦…⁩ isolates where they sit inside Arabic. Everything else is translated.

---

## 3. Patterns to avoid (found in the files)

| Pattern | Example today | Write instead |
|---|---|---|
| Untranslated jargon | `gateways:errors.webhook_secret_required` "أدخل سر توقيع الـ webhook عند تغيير الوضع." | "أدخل مفتاح توقيع الإشعارات عند تغيير الوضع." (use the same term as `gateways:settings.webhookSecret`) |
| "الخاص بك" calque (13) | `account:makePrimaryBody` "عنوان تسجيل الدخول الخاص بك"; `gateways:settings.subtitle` "حساب Stripe أو PayPal الخاص بك" | "عنوانك لتسجيل الدخول"; "حسابك في Stripe أو PayPal" |
| Agentive "بواسطة / من قبل" (meaning "by") | "أُنشئ بواسطة المعلم" | "أنشأه المعلم". Note: "من قبل" meaning "already" is fine: "استُخدم هذا الكود من قبل". |
| "سيتم + masdar" | "سيتم حذف ردود الأكاديمية عليه أيضًا." | "ستُحذف ردود الأكاديمية عليه أيضًا." |
| "بنجاح" filler | "تم الدفع بنجاح، شكرًا لك." | "تم الدفع، شكرًا لك." |
| Awkward fraction-style counts | `scheduling:pauses.left_one` "متبقٍ {{left}} من يوم تجميد واحد" | "بقي {{left}} من يوم التجميد" or "المتبقي {{left}} من أيام التجميد ({{count}})" |
| Mixed person in a label | `nav:parent.rate` "قيّم حصص أبنائي" | "تقييم حصص أبنائي" |
| Wrong concept word | `auth:studentEmpty` "لا توجد جلسات مجدولة بعد."; `registration:steps.preferences` "تفضيلات الدروس" | "لا توجد حصص مجدولة بعد."; "تفضيلات الحصص" |
| Two words for one concept | Restore: استعادة / استرجاع. Approve: قبول / موافقة / اعتماد. Payout: طريقة الاستلام / طريقة الدفع. Excused: غائب بعذر / معتذر. Absent: غائب / غياب. Family: العائلة / الأسرة. Upgrade: ترقية / رفع المستوى. Term: مدة / فترة. Paused: مجمَّد (action تجميد) / موقوف مؤقتًا. | Use the §1 term. |
| Fixed number with a plural noun (marketing) | `consultMinutes` "{n} دقيقة" (wrong for 3–10); `packageLine` "{n} حصص في الأسبوع" (wrong for 1, 2 and 11+) | Use the existing plural helpers in `i18n.ts` (lines 276–317) for minutes and sessions. |
| Missing shadda / spelling drift | marketing `failed` "تعذر الإرسال" | "تعذّر الإرسال. حاول مرة أخرى." |
| Run-on with a comma where a full stop belongs | marketing `sent` "تم استلام رسالتك، سنتواصل معك قريباً." | "استلمنا رسالتك، وسنتواصل معك قريبًا." (add و) |
| "هل أنت متأكد" in confirms | (none found: keep it that way) | Masdar question title |

## 4. Spanish quick rules
- Use **tú** throughout (puedes, tu cuenta), never usted.
- Buttons use the **infinitive**: Guardar, Eliminar, Agregar (not Añadir), Editar.
- Toasts use the **participle**: "Etiqueta guardada."
- Errors: "No se pudo cargar …".
- Core terms:
  - sesión (not clase, except "clase de prueba");
  - estudiante (not alumno);
  - profesor;
  - suscripción;
  - paquete;
  - factura;
  - recibo de pago (payslip) vs. nómina (payroll);
  - saldo / recarga;
  - pausa (not congelamiento);
  - posponer / pospuesta (not aplazada);
  - padre o madre;
  - personal;
  - Configuración.
- Spanish covers only about 2,770 of 5,596 keys today. Missing keys fall back to English. That is
  known and out of scope for wording fixes.
