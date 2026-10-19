. ./lib.sh
: > ids.env
W=600 r adm qa PATCH academy/settings/ '{"generation_horizon_days":21,"auto_invoice_on_subscription":true,"invoice_due_days":7,"absent_consumes_session":false,"excused_consumes_session":false}'
W=600 r adm qa PATCH payroll/settings/ '{"student_absent_pay_bp":5000,"student_excused_pay_bp":2500,"at_disposal_pays":false}'
W=600 r adm qa PATCH billing/settings/ '{"local_payment_enabled":true}'
W=500 mk T2 people/teachers/ '{"user":{"full_name":"SCN Teacher Two","email":"scn-teacher2@qa.etqan.test"},"profile":{}}'
W=500 mk T3 people/teachers/ '{"user":{"full_name":"SCN Payroll Teacher","email":"scn-teacher3@qa.etqan.test"},"profile":{}}'
W=500 mk TG people/teachers/ '{"user":{"full_name":"SCN Teacher Gone","email":"scn-teacher-gone@qa.etqan.test"},"profile":{}}'
echo T1=7 >> ids.env; T1=7
W=500 mk C1 catalogue/courses/ "{\"name_ar\":\"سكن\",\"name_en\":\"SCN Quran\",\"teacher_ids\":[$T1,$T2,$T3]}"
W=800 mk PKG catalogue/packages/ '{"name_ar":"س","name_en":"SCN Pkg 2x4w","sessions_per_week":2,"session_minutes":60,"duration_value":1,"duration_unit":"month","price_minor":150000,"currency":"EGP"}'
for t in $T1 $T2 $T3; do W=400 r adm qa POST payroll/rates/ "{\"teacher\":$t,\"hourly_rate_minor\":6000}"; done
cat ids.env
