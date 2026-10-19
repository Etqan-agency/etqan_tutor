. ./lib.sh; . ./ids.env
proj(){ api adm qa GET payroll/payslips/projection/; jq_ "[(r['paid_so_far_minor'],r['projected_minor']) for r in d['rows'] if r['teacher']['id']==7]"; }
echo "== TC-027 (added by Agent 2): teacher re-marks an 11-day-old session; consumption and pay follow until a payslip locks it"
echo "start: P8 $(Q "select status,student_attendance from academy_qa.scheduling_session where id=$P8") remB=$(rem $B) proj=$(proj)"
api tea qa POST sessions/$P8/attendance/ '{"student_attendance":"present"}'; echo "teacher present $CODE remB=$(rem $B) proj=$(proj)"
api tea qa POST sessions/$P8/attendance/ '{"teacher_attendance":"absent"}'; echo "teacher self-absent $CODE remB=$(rem $B) proj=$(proj)"
api tea qa POST sessions/$P8/attendance/ '{"teacher_attendance":"present"}'; echo "teacher self-present $CODE remB=$(rem $B) proj=$(proj)"
echo "locked July session P6 by teacher:"; r tea qa POST sessions/$P6/attendance/ '{"student_attendance":"absent"}'
act "$P8" | tail -3
