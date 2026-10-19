. ./lib.sh; . ./ids.env
api adm qa DELETE sessions/$J7/; echo "del J7 $CODE"
api adm qa POST subscriptions/ '{"student":32,"course":2,"teacher":7,"package":2,"starts_on":"2026-10-01","notes":"F08 Sub C (UI)"}'; echo "SubC $CODE"; SC=$(jq_ "d['id']"); echo "SC=$SC" >> ids.env
st=$(TZ=Africa/Cairo date -v-10M +%H:%M)
mk U1 sessions/regular/ "{\"subscription\":$SC,\"occurs_on\":\"2026-10-19\",\"start_time\":\"$st\"}" >/dev/null
echo "SC=$SC U1=$U1 at $st; rem $(rem $SC)"
Q "select id,student_id,status from academy_qa.scheduling_session where student_id=(select id from academy_qa.identity_studentprofile where user_id=32) and occurs_on='2026-10-19'"
