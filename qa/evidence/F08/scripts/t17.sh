. ./lib.sh; . ./ids.env
DC=/Users/khaledsakr/.etqan-qa-tools/dc.sh
tm(){ TZ=Africa/Cairo date -v${1}M +%H:%M; }
mkj(){ mk $1 sessions/extra/ "{\"student\":${4:-5},\"course\":2,\"teacher\":7,\"occurs_on\":\"2026-10-19\",\"start_time\":\"$2\",\"minutes\":30$3}" >/dev/null; }
t20=$(tm +20)
mkj J1 $t20; mkj J7 $t20 "" 32; mkj J2 $(tm +240); mkj J3 $(tm +15) ',"meeting_url":"https://example.test/room"'; mkj J4 $(tm +25); mkj J6 $(tm -5); mkj J8 $(tm +22)
r adm qa POST sessions/$J4/cancel/ '{"reason":"j"}' >/dev/null
JJ="$J1,$J7,$J2,$J3,$J4,$J6,$J8"; echo "J1 J7 J2 J3 J4 J6 J8 = $JJ"
M(){ Q "select id,status,starts_at,meeting_url,meeting_provider,meeting_ref from academy_qa.scheduling_session where id in ($JJ) order by id"; }
M
echo "other blank due qa sessions before: $(Q "select string_agg(id::text,',') from academy_qa.scheduling_session where status='scheduled' and meeting_url='' and archived_at is null and starts_at between now()-interval '4 hours' and now()+interval '24 hours' and id not in ($JJ)")"
PROV='from etqan.scheduling.services import meetings; print("provisioned", meetings.provision_meetings())'
echo "-- zoom_api OFF (default) run"; $DC exec -T django python manage.py tenant_command shell --schema=academy_qa -c "$PROV" 2>&1 | tail -1
$DC exec -T django python manage.py set_features qa --on zoom_api 2>&1 | tail -1
echo "-- zoom_api ON run 1"; $DC exec -T django python manage.py tenant_command shell --schema=academy_qa -c "$PROV" 2>&1 | grep -v W004 | tail -3
M
echo "-- run 2"; $DC exec -T django python manage.py tenant_command shell --schema=academy_qa -c "$PROV" 2>&1 | tail -1
M
$DC exec -T django python manage.py set_features qa --off zoom_api 2>&1 | tail -1
mkj J9 $(tm +10)
echo "-- zoom_api OFF again (J9=$J9 blank)"; $DC exec -T django python manage.py tenant_command shell --schema=academy_qa -c "$PROV" 2>&1 | tail -1
Q "select id,meeting_url from academy_qa.scheduling_session where id=$J9"
Q "select count(*) filter (where meeting_url ~ '^https://meet\.jit\.si/Etqan[0-9a-f]{32}$'), count(*) filter (where meeting_provider='jitsi') from academy_qa.scheduling_session where id in ($JJ)"
$DC exec -T django printenv JITSI_BASE_URL; $DC exec -T django python -c "print('ok')" >/dev/null
docker logs etqan_tutor-django-1 --since 10m 2>&1 | grep -i "zoom\|meeting" | tail -5
