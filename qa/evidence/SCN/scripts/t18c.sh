. ./lib.sh; . ./ids.env
TP1=$(QQ "select id from identity_teacherprofile where user_id=$T1"|tail -1)
QQ "select * from payroll_studentrate"; QQ "select id,teacher_id,course_id,hourly_rate_minor,currency,counts from payroll_teacherrate where teacher_id in ($TP1,$T1)"
QQ "select * from payroll_payadjustment where year=2026 and month=10" 2>&1 | head -5
echo "-- delta probe: U4 pays_teacher off -> projection, then back on"
api adm qa GET payroll/payslips/projection/; P0=$(j "[r['paid_so_far_minor'] for r in d['rows'] if r['teacher']['id']==$T1][0]")
W=200 r adm qa PATCH sessions/$U4/ '{"pays_teacher":false}'
api adm qa GET payroll/payslips/projection/; P1=$(j "[r['paid_so_far_minor'] for r in d['rows'] if r['teacher']['id']==$T1][0]")
W=200 r adm qa PATCH sessions/$U4/ '{"pays_teacher":true}'
api adm qa GET payroll/payslips/projection/; P2=$(j "[r['paid_so_far_minor'] for r in d['rows'] if r['teacher']['id']==$T1][0]")
echo "T1 paid_so_far: before $P0, U4 off $P1 (delta $((P0-P1))), restored $P2"
QQ "select pays_teacher from scheduling_session where id=$U4"
echo "Sept sessions in Oct projection? T3 (Sept only) row absent from projection: see T3 row [] above"
