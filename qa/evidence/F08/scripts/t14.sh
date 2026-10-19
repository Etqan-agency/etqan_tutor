. ./lib.sh; . ./ids.env
DC=/Users/khaledsakr/.etqan-qa-tools/dc.sh
mk R2 sessions/extra/ '{"student":5,"course":2,"teacher":7,"occurs_on":"2026-10-19","start_time":"10:00","minutes":30}' >/dev/null
r adm qa POST sessions/$R2/attendance/ '{"student_attendance":"present"}' >/dev/null
R1=$P5; R3=$F1; R4=$P2
inm(){ api $1 qa GET "reports/missing/?page_size=500"; jq_ "[i for i in [$R1,$R2,$R3,$R4] if i in [x.get('id', x.get('session',{}).get('id') if isinstance(x.get('session'),dict) else x.get('session')) for x in (d.get('results',d) if isinstance(d,dict) else d)]]"; }
api tea qa GET "reports/missing/?page_size=2"; echo "missing shape: ${RESP:0:300}"
echo "missing (teacher) among R1..R4: $(inm tea); (admin): $(inm adm)"
r tea qa PUT sessions/$R1/report/ '{"behaviour":5,"participation":4,"notes":"ok"}'
sleep 1; r adm qa PUT sessions/$R1/report/ '{"behaviour":3,"participation":2}'
Q "select session_id,behaviour,participation,notes,written_by_id,created_at<updated_at from academy_qa.scheduling_sessionreport where session_id=$R1"
for b in 0 6 '"a"'; do r adm qa PUT sessions/$R1/report/ "{\"behaviour\":$b,\"participation\":3}"; done
r tea qa PUT sessions/$R3/report/ '{"behaviour":3,"participation":3}'
r tea qa PUT sessions/$R4/report/ '{"behaviour":3,"participation":3}'
for w in stu par tea2 tea; do api $w qa GET sessions/$R1/report/; echo "GET report as $w: $CODE ${RESP:0:80}"; done
echo "after PUT missing (admin): $(inm adm)"
$DC exec -T django python manage.py set_features qa --off session_reports 2>&1 | tail -1
r adm qa GET sessions/$R1/report/; r adm qa GET reports/missing/; r tea qa PUT sessions/$R1/report/ '{"behaviour":3,"participation":3}'
api adm qa GET sessions/$R1/; echo "has_report while off: $(jq_ "d.get('has_report')")"
$DC exec -T django python manage.py set_features qa --on session_reports 2>&1 | tail -1
Q "select count(*) from academy_qa.scheduling_sessionreport where session_id=$R1"
