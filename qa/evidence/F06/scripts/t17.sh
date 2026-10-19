. ./lib.sh; . ./ids.env
DC=/Users/khaledsakr/.etqan-qa-tools/dc.sh
W=200 r adm qa POST subscriptions/ "{\"student\":213,\"course\":$C1,\"teacher\":218,\"package\":$P1,\"starts_on\":\"2026-10-19\",\"slots\":[{\"weekdays\":[0,1,2,3,4,5,6],\"start_time\":\"10:00\"}]}"; S17=$(jq_ "d['id']"); echo "S17=$S17" >> ids.env
Q "select count(*) from academy_qa.scheduling_session where subscription_id=$S17"
r adm qa POST people/teachers/218/deactivate/; r adm qa POST people/students/213/deactivate/
T0=$(Q "select now()"); echo "deactivated at $T0"
Q "select id,full_name,is_active from academy_qa.identity_user where id in (213,218)"
Q "delete from academy_qa.scheduling_session where subscription_id=$S17 and occurs_on in ('2026-10-25','2026-10-26') and student_attendance='not_set' returning occurs_on"
$DC exec -T django python manage.py tenant_command shell --schema=academy_qa -c "from etqan.scheduling.services import run_lifecycle; print(run_lifecycle())" 2>&1 | tail -1
W=300 r adm qa POST schedule/generate/ "{\"from\":\"2026-10-19\",\"to\":\"2026-11-02\",\"subscription\":$S17}"
echo "sessions created after deactivation: $(Q "select count(*)||' '||string_agg(occurs_on::text,',') from academy_qa.scheduling_session where subscription_id=$S17 and created_at > '$T0'")"
api adm qa GET "schedule/today/"; echo "today board contains S17 rows: $(python3 -c "import sys;print(sys.argv[1].count('\"subscription_id\":$S17'))" "$RESP")  teacher C on board: $(python3 -c "import sys;print('QA6 Teacher C' in sys.argv[1])" "$RESP")"
W=250 r adm qa POST subscriptions/ "{\"student\":213,\"course\":$C1,\"teacher\":7,\"package\":$P1,\"starts_on\":\"2026-10-19\",\"slots\":[{\"weekdays\":[5],\"start_time\":\"11:00\"}]}"
r adm qa POST subscriptions/ "{\"student\":212,\"course\":$C1,\"teacher\":218,\"package\":$P1,\"starts_on\":\"2026-10-19\",\"slots\":[{\"weekdays\":[5],\"start_time\":\"11:00\"}]}"
r adm qa POST subscriptions/$S17/renew/ '{}'; echo "   renew with inactive people -> $CODE"; RN17=$( [ $CODE = 201 ] && jq_ "d['id']" ); echo "RN17=$RN17" >> ids.env
