. ./lib.sh
echo "== restore settings to the s0 values"
W=400 r adm qa PATCH academy/settings/ '{"generation_horizon_days":14,"absent_consumes_session":true,"excused_consumes_session":false}'
W=300 r adm qa PATCH payroll/settings/ '{"student_absent_pay_bp":10000,"student_excused_pay_bp":10000,"at_disposal_pays":false}'
