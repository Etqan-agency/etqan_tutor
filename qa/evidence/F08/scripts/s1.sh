. ./lib.sh
DC=/Users/khaledsakr/.etqan-qa-tools/dc.sh
$DC exec -T django python manage.py set_features qa --on manual_sessions extra_sessions compensation_sessions disposal_status session_times postponement activity_log session_archive subscription_archive supervision session_reports teacher_attendance payroll_rules salary_projections 2>&1 | tail -1
Q "select features->>'session_times', features->>'activity_log', features->>'session_archive', features->>'compensation_sessions', features->>'zoom_api' from public.tenants_academy where schema_name='academy_qa'"
echo "ORIG settings absent_consumes=true excused_consumes=false" 
W=400 r adm qa POST subscriptions/ '{"student":5,"course":2,"teacher":7,"package":2,"starts_on":"2026-10-01","notes":"F08 Sub A"}'
A=$(jq_ "d['id']"); echo "A=$A" > ids.env
W=200 r adm qa POST subscriptions/ '{"student":5,"course":2,"teacher":7,"package":2,"starts_on":"2026-10-01","notes":"F08 Sub B"}'
B=$(jq_ "d['id']"); echo "B=$B" >> ids.env
# mk NAME body
mk(){ W=260 r adm qa POST "$2" "$3"; local id=$( [ $CODE = 201 ] && jq_ "d['id']" ); echo "$1=$id" >> ids.env; }
for n in 1 2 3 4 5; do mk P$n sessions/regular/ "{\"subscription\":$A,\"occurs_on\":\"2026-10-1$n\",\"start_time\":\"0$((n+2)):00\"}"; done
for n in 7 8 9; do mk P$n sessions/regular/ "{\"subscription\":$B,\"occurs_on\":\"2026-10-0$n\",\"start_time\":\"08:00\"}"; done
mk C1 sessions/regular/ "{\"subscription\":$B,\"occurs_on\":\"2026-10-03\",\"start_time\":\"08:00\"}"
mk C2 sessions/regular/ "{\"subscription\":$B,\"occurs_on\":\"2026-10-04\",\"start_time\":\"08:00\"}"
mk F1 sessions/regular/ "{\"subscription\":$B,\"occurs_on\":\"2026-10-21\",\"start_time\":\"08:00\"}"
mk F2 sessions/regular/ "{\"subscription\":$B,\"occurs_on\":\"2026-10-22\",\"start_time\":\"08:00\"}"
mk P6 sessions/extra/ '{"student":5,"course":2,"teacher":7,"occurs_on":"2026-07-15","start_time":"10:00","minutes":60}'
mk X1 sessions/extra/ "{\"student\":5,\"course\":2,\"teacher\":7,\"subscription\":$A,\"occurs_on\":\"2026-10-18\",\"start_time\":\"10:00\",\"minutes\":60}"
mk X2 sessions/extra/ "{\"student\":5,\"course\":2,\"teacher\":7,\"subscription\":$A,\"occurs_on\":\"2026-10-18\",\"start_time\":\"12:00\",\"minutes\":30,\"pays_teacher\":false}"
mk X4 sessions/extra/ "{\"student\":5,\"course\":2,\"teacher\":7,\"occurs_on\":\"2026-10-18\",\"start_time\":\"14:00\",\"minutes\":45,\"pays_teacher\":false}"
cat ids.env | tr '\n' ' '; echo
. ./ids.env
W=600 r adm qa GET subscriptions/$A/
Q "select id,kind,status,occurs_on,starts_at,minutes,pays_teacher,generated,subscription_id,student_id,teacher_id from academy_qa.scheduling_session where id in ($P1,$P6,$X1,$X2,$F1)"
