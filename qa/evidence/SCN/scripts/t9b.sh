. ./lib.sh; . ./ids.env
NOW=$(TZ=Africa/Cairo date -v-10M +%H:%M)
W=200 mk SVX sessions/extra/ "{\"student\":$SA1,\"course\":$C1,\"teacher\":$T1,\"occurs_on\":\"2026-10-19\",\"start_time\":\"$NOW\",\"minutes\":60,\"pays_teacher\":false}"
. ./ids.env
W=200 r adm qa PATCH sessions/$SVX/ '{"supervisor_id":4}'
W=300 r sup qa POST supervision/$SVX/open/
W=300 r sup qa POST supervision/$SVX/attendance/ '{"status":"present"}'
QQ "select id,supervisor_id,supervisor_attendance,student_attendance,status from scheduling_session where id=$SVX"
QQ "select session_id,actor_id,action,changes::text from scheduling_sessionactivity where session_id=$SVX order by id"
QQ "select count(*), count(*) filter (where archived_at is not null or status='cancelled') from scheduling_session where supervisor_id=4"
W=200 r adm qa PATCH sessions/$SVX/ '{"supervisor_id":null}'
W=200 r adm qa POST sessions/$SVX/cancel/ '{"reason":"SCN TC-009 helper"}'
