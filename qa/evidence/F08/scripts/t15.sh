. ./lib.sh; . ./ids.env
DC=/Users/khaledsakr/.etqan-qa-tools/dc.sh
proj(){ api adm qa GET payroll/payslips/projection/; jq_ "[(r['paid_so_far_minor'],r['projected_minor']) for r in d['rows'] if r['teacher']['id']==7]"; }
t1=$(TZ=Africa/Cairo date -v+10M +%H:%M); t2=$(TZ=Africa/Cairo date -v-60M +%H:%M)
mk T1 sessions/extra/ "{\"student\":5,\"course\":2,\"teacher\":7,\"occurs_on\":\"2026-10-19\",\"start_time\":\"$t1\",\"minutes\":30}" >/dev/null
mk T2 sessions/extra/ "{\"student\":5,\"course\":2,\"teacher\":7,\"occurs_on\":\"2026-10-19\",\"start_time\":\"$t2\",\"minutes\":60}" >/dev/null
api adm qa GET sessions/$T2/; st=$(jq_ "d['starts_at']"); echo "T1=$T1 T2=$T2 starts $st"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "== TC-015"
r tea qa POST sessions/$T1/times/ "{\"teacher_in_at\":\"$NOW\"}"
r tea qa POST sessions/$T1/times/ "{\"teacher_out_at\":\"$NOW\"}"
r tea qa POST sessions/$T2/times/ "{\"student_in_at\":\"$NOW\"}"
IN=$(python3 -c "import datetime as d;s=d.datetime.fromisoformat('$st'.replace('Z','+00:00'));print((s+d.timedelta(minutes=1)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
OUT=$(python3 -c "import datetime as d;s=d.datetime.fromisoformat('$st'.replace('Z','+00:00'));print((s+d.timedelta(minutes=56)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
BAD=$(python3 -c "import datetime as d;s=d.datetime.fromisoformat('$st'.replace('Z','+00:00'));print((s-d.timedelta(minutes=30)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
FAR=$(python3 -c "import datetime as d;s=d.datetime.fromisoformat('$st'.replace('Z','+00:00'));print((s+d.timedelta(minutes=700)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
P0=$(proj)
r tea qa POST sessions/$T2/times/ "{\"teacher_in_at\":\"$IN\",\"teacher_out_at\":\"$OUT\"}"
Q "select teacher_in_at,teacher_out_at,actual_minutes from academy_qa.scheduling_session where id=$T2"
r tea qa POST sessions/$T2/times/ "{\"teacher_out_at\":\"$BAD\"}"
r tea qa POST sessions/$T2/times/ "{\"teacher_out_at\":\"$FAR\"}"
r adm qa POST sessions/$T2/times/ '{"actual_minutes":45}'
r adm qa POST sessions/$T2/times/ '{"actual_minutes":601}'
r adm qa POST sessions/$T2/attendance/ '{"student_attendance":"present"}' >/dev/null
Q "select teacher_in_at,teacher_out_at,actual_minutes,minutes,status from academy_qa.scheduling_session where id=$T2"
echo "projection before times=$P0 after times+mark=$(proj) (expect +6000 from minutes=60, not 45)"
echo "== TC-024 teacher_attendance switch"
mk TA1 sessions/extra/ '{"student":5,"course":2,"teacher":7,"occurs_on":"2026-10-17","start_time":"20:00","minutes":30}' >/dev/null
mk TA2 sessions/regular/ "{\"subscription\":$A,\"occurs_on\":\"2026-10-16\",\"start_time\":\"20:00\"}" >/dev/null
echo "remA0 $(rem $A)"
r tea qa POST sessions/$TA2/attendance/ '{"teacher_attendance":"present"}'
Q "select status,teacher_attendance from academy_qa.scheduling_session where id=$TA2"
r tea qa POST sessions/$TA2/attendance/ '{"student_attendance":"present"}'; echo "remA $(rem $A)"
r tea qa POST sessions/$TA2/attendance/ '{"teacher_attendance":"absent"}'; echo "remA after teacher absent $(rem $A)"
$DC exec -T django python manage.py set_features qa --off teacher_attendance 2>&1 | tail -1
r tea qa POST sessions/$TA1/attendance/ '{"student_attendance":"present"}'
r tea qa POST sessions/$TA1/attendance/ '{"teacher_attendance":"present"}'
r tea qa POST sessions/$TA1/times/ "{\"teacher_in_at\":\"2026-10-17T17:01:00Z\"}"
r tea qa PUT sessions/$TA2/report/ '{"behaviour":3,"participation":3}'
r adm qa POST sessions/$TA1/attendance/ '{"student_attendance":"present","teacher_attendance":"present"}'
$DC exec -T django python manage.py set_features qa --on teacher_attendance 2>&1 | tail -1
S "$TA1,$TA2"
