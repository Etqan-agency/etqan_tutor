. ./lib.sh; . ./ids.env
DC=/Users/khaledsakr/.etqan-qa-tools/dc.sh
LC(){ $DC exec -T django python manage.py tenant_command shell --schema=academy_qa -c "from etqan.scheduling.services import run_lifecycle; print(run_lifecycle())" 2>&1 | tail -1; }
fut(){ Q "select count(*) from academy_qa.scheduling_session where subscription_id=$1 and starts_at>now()"; }
a=$X2; echo "a=$a future=$(fut $a)"
W=200 r adm qa POST schedules/stop/ "{\"subscription_ids\":[$a]}"; echo "   future after stop=$(fut $a) status=$(Q "select schedule_status from academy_qa.scheduling_subscription where id=$a")"; LC; echo "   future after job=$(fut $a)"
r adm qa POST schedule/generate/ "{\"from\":\"2026-10-19\",\"to\":\"2026-11-02\",\"subscription\":$a}"
r adm qa POST schedules/delete/ "{\"subscription_ids\":[$a]}"; echo "   status=$(Q "select schedule_status from academy_qa.scheduling_subscription where id=$a")"
r adm qa POST schedules/restore/ "{\"subscription_ids\":[$a]}"; echo "   status=$(Q "select schedule_status from academy_qa.scheduling_subscription where id=$a") future=$(fut $a)"
r adm qa POST schedules/activate/ "{\"subscription_ids\":[$a]}"; echo "   status=$(Q "select schedule_status from academy_qa.scheduling_subscription where id=$a") future=$(fut $a)"
echo "-- bulk teacher change: b=27 (course C2, teacher C not on it)"
r adm qa POST schedules/teacher/ "{\"subscription_ids\":[$a,27],\"teacher_id\":218}"; echo "   a teacher=$(Q "select t.user_id from academy_qa.scheduling_subscription s join academy_qa.identity_teacherprofile t on t.id=s.teacher_id where s.id=$a")"
r adm qa POST subscriptions/ "{\"student\":216,\"course\":$C1,\"teacher\":217,\"package\":$P2,\"starts_on\":\"2026-10-19\",\"slots\":[{\"weekdays\":[0],\"start_time\":\"06:30\"}]}"; B24=$(jq_ "d['id']"); echo "B24=$B24" >> ids.env
MS=$(Q "select id from academy_qa.scheduling_session where subscription_id=$B24 and occurs_on='2026-10-19'"); [ -z "$MS" ] && { api adm qa POST schedule/generate/ "{\"from\":\"2026-10-19\",\"to\":\"2026-10-19\",\"subscription\":$B24}"; MS=$(Q "select id from academy_qa.scheduling_session where subscription_id=$B24 and occurs_on='2026-10-19'"); }
r adm qa POST sessions/$MS/attendance/ '{"student_attendance":"present","teacher_attendance":"present"}'
r adm qa POST schedules/teacher/ "{\"subscription_ids\":[$a,$B24],\"teacher_id\":218}"
Q "select se.subscription_id,se.occurs_on,se.status,t.user_id from academy_qa.scheduling_session se join academy_qa.identity_teacherprofile t on t.id=se.teacher_id where se.subscription_id in ($a,$B24) order by 1,2"
echo "-- substitution on a (teacher now $(Q "select t.user_id from academy_qa.scheduling_subscription s join academy_qa.identity_teacherprofile t on t.id=s.teacher_id where s.id=$a"))"
r adm qa POST schedules/substitutions/ "{\"subscription_ids\":[$a],\"teacher_id\":7,\"from_date\":\"2026-10-26\",\"to_date\":\"2026-11-02\"}"; SUB=$(python3 -c "import json,sys;d=json.loads(sys.argv[1]);s=d.get('substitutions',[]);print(s[0]['id'] if s and isinstance(s[0],dict) else (s[0] if s else ''))" "$RESP")
r adm qa POST schedules/substitutions/ "{\"subscription_ids\":[$a],\"teacher_id\":217,\"from_date\":\"2026-11-01\",\"to_date\":\"2026-11-05\"}"
r adm qa POST schedules/substitutions/ "{\"subscription_ids\":[$a],\"teacher_id\":217,\"from_date\":\"2026-11-10\",\"to_date\":\"2027-12-31\"}"
Q "select se.occurs_on,t.user_id,se.substitute_for_id is not null from academy_qa.scheduling_session se join academy_qa.identity_teacherprofile t on t.id=se.teacher_id where se.subscription_id=$a order by 1"
r adm qa DELETE schedules/substitutions/$SUB/
Q "select se.occurs_on,t.user_id,se.substitute_for_id is not null from academy_qa.scheduling_session se join academy_qa.identity_teacherprofile t on t.id=se.teacher_id where se.subscription_id=$a order by 1"
