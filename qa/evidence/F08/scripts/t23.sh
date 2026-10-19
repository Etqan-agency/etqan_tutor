. ./lib.sh; . ./ids.env
DC=/Users/khaledsakr/.etqan-qa-tools/dc.sh
echo "== TC-023"
r adm qa POST sessions/regular/ "{\"subscription\":$A,\"occurs_on\":\"2026-09-20\",\"start_time\":\"10:00\"}"
r adm qa POST sessions/regular/ '{"subscription":80,"occurs_on":"2026-10-20","start_time":"10:00"}'
for m in 14 241; do r adm qa POST sessions/extra/ "{\"student\":5,\"course\":2,\"teacher\":7,\"occurs_on\":\"2026-10-20\",\"start_time\":\"10:00\",\"minutes\":$m}"; done
r adm qa POST sessions/extra/ '{"student":5,"course":2,"teacher":7,"occurs_on":"2026-10-20","start_time":"10:00"}'
r adm qa POST sessions/extra/ '{"student":5,"course":2,"teacher":217,"occurs_on":"2026-10-20","start_time":"10:00","minutes":30}'
W=200 mk O1 sessions/extra/ '{"student":5,"course":2,"teacher":7,"occurs_on":"2026-10-26","start_time":"10:00","minutes":30}' >/dev/null
api adm qa GET sessions/$O1/; echo "O1=$O1 (overlaps session 1 at 07:00Z) created; conflicts in create response checked below"
api adm qa DELETE sessions/$O1/
W=120 r adm qa POST sessions/extra/ '{"student":5,"course":2,"teacher":7,"occurs_on":"2026-10-26","start_time":"10:00","minutes":30}'; echo "conflicts: $(jq_ "len(d.get('conflicts',[]))")"; O2=$(jq_ "d['session']['id']")
echo "-- delete rules"
r adm qa DELETE sessions/$P2/
r adm qa DELETE sessions/3/
r adm qa DELETE sessions/$C1/
echo "-- S4: activity of an unmarked hand-added session disappears on delete"
api adm qa POST sessions/$O2/pays-teacher/ '{"pays_teacher":false}'; api adm qa POST sessions/$O2/postpone/ '{"occurs_on":"2026-10-27","start_time":"21:00"}'
echo "O2 activity rows before delete: $(Q "select count(*) from academy_qa.scheduling_sessionactivity where session_id=$O2")"
$DC exec -T django python manage.py set_features qa --off manual_sessions extra_sessions 2>&1 | tail -1
r adm qa DELETE sessions/$O2/
echo "O2 rows after delete: session=$(Q "select count(*) from academy_qa.scheduling_session where id=$O2") activity=$(Q "select count(*) from academy_qa.scheduling_sessionactivity where session_id=$O2")"
r adm qa POST sessions/extra/ '{"student":5,"course":2,"teacher":7,"occurs_on":"2026-10-26","start_time":"10:00","minutes":30}'
$DC exec -T django python manage.py set_features qa --on manual_sessions extra_sessions 2>&1 | tail -1
Q "select id,generated,created_by_id,subscription_id from academy_qa.scheduling_session where id in ($P1,$X1,3)"
echo "== TC-025"
api adm qa POST sessions/extra/ '{"student":5,"course":2,"teacher":7,"occurs_on":"2026-10-29","start_time":"23:30","minutes":30}'; Z1=$(jq_ "d['session']['id']"); echo "ambiguous 10-29 23:30 -> $(jq_ "d['session']['starts_at']") (first occurrence = 20:30Z)"
api adm qa POST sessions/extra/ '{"student":5,"course":2,"teacher":7,"occurs_on":"2026-10-30","start_time":"00:30","minutes":30}'; Z2=$(jq_ "d['session']['id']"); echo "10-30 00:30 -> $(jq_ "d['session']['starts_at']") (UTC+2 = 22:30Z on 10-29)"
api adm qa DELETE sessions/$Z1/; api adm qa DELETE sessions/$Z2/
st=$(TZ=Africa/Cairo date -v+1M +%H:%M)
mk G1 sessions/extra/ "{\"student\":5,\"course\":2,\"teacher\":7,\"occurs_on\":\"2026-10-19\",\"start_time\":\"$st\",\"minutes\":30}" >/dev/null
api adm qa GET sessions/$G1/; echo "G1=$G1 starts_at=$(jq_ "d['starts_at']") has_started=$(jq_ "d['has_started']") now=$(date -u +%H:%M:%S)"
r adm qa POST sessions/$G1/attendance/ '{"student_attendance":"present"}'
r tea qa POST sessions/$G1/attendance/ '{"student_attendance":"present"}'
r adm qa POST sessions/$G1/times/ '{"student_in_at":"2026-10-19T00:00:00Z"}'
r adm qa POST sessions/bulk/ "{\"ids\":[$G1],\"action\":\"present\"}"
for i in $(seq 1 30); do api adm qa GET sessions/$G1/; [ "$(jq_ "d['has_started']")" = True ] && break; sleep 5; done
echo "after wait now=$(date -u +%H:%M:%S) has_started=$(jq_ "d['has_started']")"
r tea qa POST sessions/$G1/attendance/ '{"student_attendance":"present"}'
S "$G1"
