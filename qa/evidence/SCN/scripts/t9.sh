. ./lib.sh; . ./ids.env
echo "== TC-009"
SV=354
W=300 r adm qa PATCH sessions/$SV/ '{"supervisor_id":4}'
api sup qa GET supervision/; echo "[$CODE] sup list ids: $(j "[x.get('id', x.get('session',{}).get('id')) for x in (d['results'] if isinstance(d,dict) and 'results' in d else d)][:20]") ${RESP:0:200}"
QQ "select count(*) from scheduling_session where supervisor_id=(select id from identity_user where id=4) or supervisor_id=4"
W=300 r sup qa POST supervision/$SV/open/
W=300 r sup qa POST supervision/$SV/attendance/ '{"supervisor_attendance":"present"}'
W=200 r tea qa GET supervision/
W=200 r sup qa GET "sessions/?page_size=5"
W=200 r sup qa POST subscriptions/ "{\"student\":$SA2,\"course\":$C1,\"teacher\":$T2,\"package\":$PKG,\"starts_on\":\"2026-10-20\"}"
W=200 r sup qa DELETE sessions/$U2/
QQ "select id,supervisor_id,supervisor_attendance,student_attendance,status from scheduling_session where id=$SV"
QQ "select session_id,actor_id,action,changes::text from scheduling_sessionactivity where session_id=$SV order by id"
W=200 r adm qa PATCH sessions/$SV/ '{"supervisor_id":null}'
QQ "select supervisor_id,supervisor_attendance from scheduling_session where id=$SV"
