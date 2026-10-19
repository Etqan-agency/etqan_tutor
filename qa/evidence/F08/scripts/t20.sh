. ./lib.sh; . ./ids.env
DC=/Users/khaledsakr/.etqan-qa-tools/dc.sh
mk L1 sessions/extra/ '{"student":5,"course":2,"teacher":7,"occurs_on":"2026-10-14","start_time":"21:30","minutes":30}' >/dev/null
api adm qa POST sessions/$L1/attendance/ '{"student_attendance":"present"}'
api adm qa POST sessions/$L1/cancel/ '{"reason":"l1"}'
api adm qa POST sessions/$L1/restore/
api tea qa POST sessions/$L1/times/ '{"teacher_in_at":"2026-10-14T18:31:00Z"}'
W=900 r adm qa GET sessions/$L1/activity/
act "$L1"
E=($(Q "select id from academy_qa.scheduling_sessionactivity where session_id=$L1 order by id")); echo "entries ${E[*]}"
echo "-- revert newest (times ${E[3]})"; r adm qa POST sessions/$L1/activity/${E[3]}/revert/
Q "select teacher_in_at from academy_qa.scheduling_session where id=$L1"
echo "-- revert restore (${E[2]}) -> back to cancelled"; r adm qa POST sessions/$L1/activity/${E[2]}/revert/
Q "select status,cancel_reason from academy_qa.scheduling_session where id=$L1"
echo "-- stale: revert attendance entry (${E[0]}) whose status changed since"; r adm qa POST sessions/$L1/activity/${E[0]}/revert/
NEW=$(Q "select max(id) from academy_qa.scheduling_sessionactivity where session_id=$L1"); echo "-- revert a revert ($NEW)"; r adm qa POST sessions/$L1/activity/$NEW/revert/
act "$L1"
PE=$(Q "select id from academy_qa.scheduling_sessionactivity where session_id=$P6 order by id limit 1"); echo "-- locked P6 entry $PE"; r adm qa POST sessions/$P6/activity/$PE/revert/
CE=$(Q "select id from academy_qa.scheduling_sessionactivity where session_id=$C1 order by id limit 1"); echo "-- compensated original C1 entry $CE"; r adm qa POST sessions/$C1/activity/$CE/revert/
for w in tea nocode codes stu sup; do api $w qa GET sessions/$L1/activity/; echo -n "GET $w=$CODE  "; done; echo
api tea qa POST sessions/$L1/activity/${E[1]}/revert/; echo "teacher revert=$CODE"
$DC exec -T django python manage.py set_features qa --off activity_log 2>&1 | tail -1
r adm qa GET sessions/$L1/activity/; r adm qa POST sessions/$L1/activity/${E[1]}/revert/
$DC exec -T django python manage.py set_features qa --on activity_log 2>&1 | tail -1
