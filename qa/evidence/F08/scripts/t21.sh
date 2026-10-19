. ./lib.sh; . ./ids.env
DC=/Users/khaledsakr/.etqan-qa-tools/dc.sh
proj(){ api adm qa GET payroll/payslips/projection/; jq_ "[(r['paid_so_far_minor'],r['projected_minor']) for r in d['rows'] if r['teacher']['id']==7]"; }
inlist(){ api adm qa GET "sessions/?page_size=500$1"; jq_ "[i for i in [$P5,$X1,$B1,$F1,$P6] if i in [x['id'] for x in d['results']]]"; }
echo "== TC-021"
echo "before: remA=$(rem $A) proj=$(proj) inv=$(Q "select coalesce(sum(total_minor),0) from academy_qa.billing_invoice where subscription_id=$A" 2>&1|head -1)"
W=500 r adm qa POST sessions/archive/ "{\"ids\":[$P5,$X1,$B1,$F1,$P6]}"
echo "after:  remA=$(rem $A) proj=$(proj)"
echo "default list: $(inlist '') only: $(inlist '&archived=only') include: $(inlist '&archived=include')"
Q "select id,archived_at is not null,archived_by_id from academy_qa.scheduling_session where id in ($P5,$X1,$B1,$F1,$P6) order by id"
r adm qa POST sessions/$B1/restore/
api stu qa GET "sessions/?page_size=500"; echo "student default list has archived? $(jq_ "[i for i in [$P5,$X1,$B1] if i in [x['id'] for x in d['results']]]")"
echo "== TC-026 / S1 probes on archived rows"
r adm qa POST sessions/$P5/attendance/ '{"student_attendance":"excused"}'; echo "remA now $(rem $A)"
r adm qa POST sessions/$X1/pays-teacher/ '{"pays_teacher":false}'; echo "proj now $(proj)"
r adm qa POST sessions/$X1/times/ '{"actual_minutes":20}'
r adm qa POST sessions/$X1/cancel/ '{"reason":"archived cancel"}'
r adm qa POST sessions/$X1/restore/
r adm qa PUT sessions/$X1/report/ '{"behaviour":2,"participation":2}'
r adm qa POST sessions/bulk/ "{\"ids\":[$P5],\"action\":\"absent\"}"
S "$P5,$X1"; act "$X1" | tail -3
echo "-- unarchive perms"
r codes qa POST sessions/unarchive/ "{\"ids\":[$P5]}"
r sup qa POST sessions/unarchive/ "{\"ids\":[$P5]}"
$DC exec -T django python manage.py set_features qa --off session_archive 2>&1 | tail -1
echo "switch off default list: $(inlist '')"
r adm qa POST sessions/unarchive/ "{\"ids\":[$P5]}"
$DC exec -T django python manage.py set_features qa --on session_archive 2>&1 | tail -1
W=300 r adm qa POST sessions/unarchive/ "{\"ids\":[$P5,$X1,$B1,$P6]}"
echo "== TC-026 / S5: undo a completed session with report (P5)"
api adm qa POST sessions/$P5/attendance/ '{"student_attendance":"present"}'; api adm qa POST sessions/$X1/pays-teacher/ '{"pays_teacher":true}'
Q "select count(*) from academy_qa.scheduling_sessionreport where session_id=$P5"
r adm qa POST sessions/$P5/attendance/ '{"student_attendance":"not_set"}'
api adm qa GET sessions/$P5/; echo "P5 status=$(jq_ "d['status']") has_report=$(jq_ "d['has_report']")"
api adm qa GET "reports/missing/?page_size=500"; echo "P5 in missing: $(jq_ "$P5 in [x['id'] for x in d['results']]")"
api adm qa GET sessions/$P5/report/; echo "GET report $CODE"
r adm qa PUT sessions/$P5/report/ '{"behaviour":4,"participation":4}'
api adm qa POST sessions/$P5/attendance/ '{"student_attendance":"present"}'; echo "re-marked P5 $CODE; remA $(rem $A) proj $(proj)"
