. ./lib.sh
echo "== Gate check G1 (Agent 2): over-consumption past the package total on Sub C 84 (8 sessions)"
api adm qa GET identity/me/ ; echo "admin session $CODE"
d(){ api adm qa GET subscriptions/84/; jq_ "(d['sessions_used'],d['sessions_remaining'],d.get('extra_sessions'),d.get('progress'))"; }
echo "start used/remaining/extra/progress = $(d)"
IDS=""
for n in 2 3 4 5 6 7 8 9; do W=150 r adm qa POST sessions/regular/ "{\"subscription\":84,\"occurs_on\":\"2026-10-0$n\",\"start_time\":\"09:00\"}"; id=$(jq_ "d.get('session',d)['id']"); IDS="$IDS${IDS:+,}$id"; done
echo "created $IDS"
for id in ${IDS//,/ }; do api adm qa POST sessions/$id/attendance/ '{"student_attendance":"present"}'; printf "%s:%s " $id $CODE; done; echo
echo "after 8 more present: used/remaining/extra/progress = $(d)"
echo "DB consuming count: $(Q "select count(*) from academy_qa.scheduling_session where subscription_id=84 and status='completed' and student_attendance='present' and kind<>'extra'")"
api tea qa GET subscriptions/84/; echo "teacher view $CODE"
api stu qa GET subscriptions/84/; echo "foreign student view $CODE"
api oth qaother GET subscriptions/84/; echo "qaother view $CODE"
echo "-- cleanup: undo + delete"
for id in ${IDS//,/ }; do api adm qa POST sessions/$id/attendance/ '{"student_attendance":"not_set"}'; a=$CODE; api adm qa DELETE sessions/$id/; printf "%s:%s/%s " $id $a $CODE; done; echo
echo "end used/remaining/extra/progress = $(d)"
echo "left rows: $(Q "select count(*) from academy_qa.scheduling_session where id in ($IDS)")"
