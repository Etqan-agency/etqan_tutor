. ./lib.sh; . ./ids.env
proj(){ api adm qa GET payroll/payslips/projection/; jq_ "[(r['paid_so_far_minor'],r['projected_minor'],r['scheduled_sessions']) for r in d['rows'] if r['teacher']['id']==7]"; }
cons(){ Q "select count(*) from academy_qa.scheduling_session s, academy_qa.academy_academysettings a where s.subscription_id=$A and s.status='completed' and (s.student_attendance='present' or (s.student_attendance='absent' and a.absent_consumes_session) or (s.student_attendance='excused' and a.excused_consumes_session)) and s.teacher_attendance<>'absent' and s.kind in ('regular','compensation') and not s.compensated"; }
echo "== TC-002"
W=200 r adm qa PATCH academy/settings/ '{"absent_consumes_session":false,"excused_consumes_session":false}'
echo "rem0 $(rem $A) sqlcons=$(cons)"
r adm qa POST sessions/$P2/attendance/ '{"student_attendance":"absent"}'; echo "after P2 absent: $(rem $A) sql=$(cons)"
r adm qa POST sessions/$P3/attendance/ '{"student_attendance":"excused"}'; echo "after P3 excused: $(rem $A) sql=$(cons)"
r adm qa POST sessions/$P4/attendance/ '{"student_attendance":"present","teacher_attendance":"absent"}'; echo "after P4 present+teacher absent: $(rem $A) sql=$(cons)"
r adm qa POST sessions/$P5/attendance/ '{"student_attendance":"present"}'; echo "after P5 present: $(rem $A) sql=$(cons)"
r adm qa PATCH academy/settings/ '{"absent_consumes_session":true}'; echo "absent_consumes=true: $(rem $A) sql=$(cons)"
r adm qa PATCH academy/settings/ '{"excused_consumes_session":true}'; echo "excused_consumes=true: $(rem $A) sql=$(cons)"
r adm qa POST sessions/$P5/attendance/ '{"student_attendance":"late"}'
S "$P2,$P3,$P4,$P5"
r adm qa PATCH academy/settings/ '{"absent_consumes_session":true,"excused_consumes_session":false}'; echo "restored original settings (absent=true excused=false): $(rem $A)"
echo "== TC-003"
echo "proj0 $(proj) rem $(rem $A)"
r adm qa POST sessions/$X1/attendance/ '{"student_attendance":"present"}'; echo "X1 present: proj $(proj) rem $(rem $A)"
r adm qa POST sessions/$X2/attendance/ '{"student_attendance":"present"}'; echo "X2 present: proj $(proj) rem $(rem $A)"
r adm qa POST sessions/$X2/pays-teacher/ '{"pays_teacher":true}'; echo "X2 pays on: proj $(proj)"
r adm qa POST sessions/$X4/attendance/ '{"student_attendance":"present"}'; echo "X4 (45min pays=false) present: proj $(proj)"
r adm qa POST sessions/$X4/pays-teacher/ '{"pays_teacher":true}'; echo "X4 pays on: proj $(proj)"
S "$X1,$X2,$X4"
Q "select count(*) from academy_qa.scheduling_session where payroll_locked and id between 235 and 260"
