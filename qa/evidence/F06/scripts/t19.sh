. ./lib.sh; . ./ids.env
DC=/Users/khaledsakr/.etqan-qa-tools/dc.sh
login teaB qa qa6-teacher-b@qa.etqan.test 'x' >/dev/null
W=250 r tea qa PUT schedule/availability/ '{"windows":[{"weekday":0,"start_time":"09:00","end_time":"12:00"}]}'
r tea qa PUT schedule/availability/ '{"windows":[{"weekday":0,"start_time":"12:00","end_time":"09:00"}]}'
w51=$(python3 -c "import json;print(json.dumps({'windows':[{'weekday':i%7,'start_time':'%02d:00'%(i//7),'end_time':'%02d:30'%(i//7)} for i in range(51)]}))")
r tea qa PUT schedule/availability/ "$w51"
r tea qa PUT schedule/availability/217/ '{"windows":[]}'
r tea qa GET schedule/availability/217/
r adm qa PUT schedule/availability/217/ '{"windows":[{"weekday":1,"start_time":"07:00","end_time":"08:00"}]}'
Q "select t.user_id,a.weekday,a.start_time,a.end_time from academy_qa.scheduling_teacheravailability a join academy_qa.identity_teacherprofile t on t.id=a.teacher_id where t.user_id in (7,217) order by 1,2"
r adm qa PUT schedule/availability/7/ '{"windows":[{"weekday":0,"start_time":"09:00","end_time":"12:00"},{"weekday":2,"start_time":"09:00","end_time":"10:00"}]}'
r adm qa PUT schedule/availability/7/ '{"windows":[{"weekday":0,"start_time":"09:00","end_time":"12:00"}]}'
Q "select count(*) from academy_qa.scheduling_teacheravailability a join academy_qa.identity_teacherprofile t on t.id=a.teacher_id where t.user_id=7"
W=200 r adm qa POST subscriptions/ "{\"student\":214,\"course\":$C2,\"teacher\":7,\"package\":$P2,\"starts_on\":\"2026-10-19\",\"slots\":[{\"weekdays\":[0],\"start_time\":\"20:00\"}]}"; A19=$(jq_ "d['id']"); echo "   outside keys: $(jq_ "{k:v for k,v in d.items() if 'outside' in k}")"
r adm qa GET subscriptions/$A19/slots/
r adm qa POST subscriptions/ "{\"student\":214,\"course\":$C2,\"teacher\":217,\"package\":$P2,\"starts_on\":\"2026-10-19\",\"slots\":[{\"weekdays\":[0],\"start_time\":\"20:00\"}]}"
$DC exec -T django python manage.py set_features qa --off teacher_availability 2>&1 | tail -1
r adm qa GET subscriptions/$A19/slots/
r tea qa PUT schedule/availability/ '{"windows":[]}'
$DC exec -T django python manage.py set_features qa --on teacher_availability 2>&1 | tail -1
echo "A19=$A19" >> ids.env
