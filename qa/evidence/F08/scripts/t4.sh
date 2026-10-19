. ./lib.sh; . ./ids.env
echo "== TC-004"
r adm qa POST sessions/$P6/attendance/ '{"student_attendance":"present"}'
W=500 r adm qa POST payroll/payslips/generate/ '{"year":2026,"month":7}'
PS=$(Q "select id from academy_qa.payroll_payslip where teacher_id=1 and year=2026 and month=7"); echo "PS=$PS" >> ids.env; echo PS=$PS
Q "select id,status,gross_minor,net_minor from academy_qa.payroll_payslip where id=$PS"
W=300 r adm qa POST payroll/payslips/$PS/issue/
N0=$(Q "select count(*) from academy_qa.scheduling_sessionactivity where session_id=$P6"); T0=$(Q "select net_minor from academy_qa.payroll_payslip where id=$PS")
r adm qa POST sessions/$P6/attendance/ '{"student_attendance":"absent"}'
r adm qa POST sessions/$P6/attendance/ '{"teacher_attendance":"absent"}'
r adm qa POST sessions/$P6/cancel/ '{"reason":"x"}'
r adm qa POST sessions/$P6/restore/
r adm qa POST sessions/$P6/postpone/ '{"occurs_on":"2026-10-25","start_time":"10:00"}'
r adm qa POST sessions/$P6/times/ '{"actual_minutes":30}'
r adm qa POST sessions/$P6/disposal/ '{"reason":"x"}'
r adm qa POST sessions/$P6/pays-teacher/ '{"pays_teacher":false}'
r adm qa POST sessions/bulk/ "{\"ids\":[$P6],\"action\":\"present\"}"
r adm qa POST sessions/bulk/ "{\"ids\":[$P6],\"action\":\"cancel\",\"reason\":\"x\"}"
r adm qa DELETE sessions/$P6/
r adm qa PUT sessions/$P6/report/ '{"behaviour":3,"participation":3}'
S "$P6"
echo "activity rows before=$N0 after=$(Q "select count(*) from academy_qa.scheduling_sessionactivity where session_id=$P6"); net before=$T0 after=$(Q "select net_minor from academy_qa.payroll_payslip where id=$PS")"
Q "select count(*), bool_and(payroll_locked) from academy_qa.scheduling_session where teacher_id=1 and occurs_on between '2026-07-01' and '2026-07-31' and status='completed'"
Q "select count(*) filter (where payroll_locked) from academy_qa.scheduling_session where teacher_id=1 and occurs_on not between '2026-07-01' and '2026-07-31'"
echo "== TC-005"
r adm qa POST sessions/$P7/cancel/ '{"reason":""}'
r adm qa POST sessions/$P7/cancel/ '{"reason":"teacher ill"}'
Q "select status,cancel_reason,cancelled_by_id,cancelled_at is not null from academy_qa.scheduling_session where id=$P7"
r adm qa POST sessions/$P7/cancel/ '{"reason":"again"}'
r adm qa POST sessions/$P7/attendance/ '{"student_attendance":"present"}'
r adm qa POST sessions/$P7/restore/
Q "select status,cancel_reason,cancelled_by_id,cancelled_at from academy_qa.scheduling_session where id=$P7"
r adm qa POST sessions/$P7/restore/
r adm qa POST sessions/$P7/attendance/ '{"student_attendance":"present"}'
r adm qa POST sessions/$P7/cancel/ '{"reason":"after mark"}'
r adm qa POST sessions/$P7/restore/
r adm qa POST sessions/$F1/attendance/ '{"student_attendance":"present"}'
S "$P7,$F1"; act "$P7"
