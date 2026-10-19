. ./lib.sh; . ./ids.env
DC=/Users/khaledsakr/.etqan-qa-tools/dc.sh
tm(){ TZ=Africa/Cairo date -v${1}M +%H:%M; }
mkv(){ mk $1 sessions/extra/ "{\"student\":5,\"course\":2,\"teacher\":7,\"occurs_on\":\"2026-10-19\",\"start_time\":\"$2\",\"minutes\":$3,\"meeting_url\":\"https://example.test/$1\"}" >/dev/null; }
mkv V1 $(tm +5) 30; mkv V2 $(tm +120) 30; mkv V3 $(tm -30) 60; mkv V4 $(tm -90) 30; mkv V5 $(tm +7) 30; mkv V6 $(tm +6) 30
r adm qa POST sessions/$V5/cancel/ '{"reason":"v"}' >/dev/null
for v in $V1 $V2 $V3 $V4 $V5; do api adm qa PATCH sessions/$v/ '{"supervisor_id":4}'; echo -n "assign $v=$CODE "; done
api adm qa PATCH sessions/$V6/ '{"supervisor_id":136}'; echo "assign V6=$CODE"
echo "V1..V6=$V1 $V2 $V3 $V4 $V5 $V6"
api sup qa GET "supervision/?page_size=200"; echo "supervision list has: $(jq_ "[i for i in [$V1,$V2,$V3,$V4,$V5,$V6] if i in [x['id'] for x in d.get('results',d)]]")"
for v in V1 V2 V3 V4 V5 V6; do id=$(eval echo \$$v); echo -n "open $v: "; r sup qa POST supervision/$id/open/; done
Q "select id,opened_by_supervisor_at from academy_qa.scheduling_session where id in ($V1,$V3)"
r sup qa POST supervision/$V1/open/ >/dev/null; Q "select id,opened_by_supervisor_at from academy_qa.scheduling_session where id=$V1"
r sup qa POST supervision/$V3/attendance/ '{"status":"present"}'
r sup qa POST supervision/$V2/attendance/ '{"status":"present"}'
r sup qa POST supervision/$V4/attendance/ '{"status":"present"}'
r sup qa POST supervision/$V3/attendance/ '{"status":"excused"}'
r codes qa POST supervision/$V3/open/
echo "-- S6 probe: office PATCH supervisor_attendance on future V2 and cancelled V5"
r adm qa PATCH sessions/$V2/ '{"supervisor_attendance":"present"}'
r adm qa PATCH sessions/$V5/ '{"supervisor_attendance":"present"}'
r adm qa PATCH sessions/$P6/ '{"supervisor_attendance":"present"}'
Q "select id,status,supervisor_id,supervisor_attendance,opened_by_supervisor_at,payroll_locked from academy_qa.scheduling_session where id in ($V2,$V5,$P6)"
r adm qa PATCH sessions/$V3/ '{"supervisor_id":136}'
Q "select id,supervisor_id,supervisor_attendance,opened_by_supervisor_at from academy_qa.scheduling_session where id=$V3"
r adm qa PATCH sessions/$V4/ '{"supervisor_id":null}'
r adm qa PATCH sessions/$V4/ '{"supervisor_attendance":"present"}'
act "$V3"
$DC exec -T django python manage.py set_features qa --off supervision 2>&1 | tail -1
r sup qa GET supervision/; r sup qa POST supervision/$V1/open/; r sup qa POST supervision/$V1/attendance/ '{"status":"present"}'
$DC exec -T django python manage.py set_features qa --on supervision 2>&1 | tail -1
echo "V=$V1,$V2,$V3,$V4,$V5,$V6" 
