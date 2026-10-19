. ./lib.sh; . ./ids.env
dup(){ Q "select occurs_on,to_char(starts_at at time zone 'Africa/Cairo','HH24:MI'),student_id,teacher_id,count(*),string_agg(subscription_id::text||'/'||status||'/'||student_attendance,' ') from academy_qa.scheduling_session where status<>'cancelled' and student_id=(select id from academy_qa.identity_studentprofile where user_id=$1) group by 1,2,3,4 having count(*)>1"; }
W=300 r adm qa POST subscriptions/ "{\"student\":214,\"course\":$C2,\"teacher\":7,\"package\":$P1,\"starts_on\":\"2026-10-05\",\"slots\":[{\"weekdays\":[0],\"start_time\":\"06:00\"}]}"; SA_=$(jq_ "d['id']")
r adm qa POST schedule/generate/ "{\"from\":\"2026-10-05\",\"to\":\"2026-10-19\",\"subscription\":$SA_}"
SID=$(Q "select id from academy_qa.scheduling_session where subscription_id=$SA_ and occurs_on='2026-10-19'"); echo "A=$SA_ session 10-19 id=$SID"
W=400 r adm qa POST sessions/$SID/attendance/ '{"student_attendance":"present","teacher_attendance":"present"}'
Q "select id,occurs_on,status,student_attendance from academy_qa.scheduling_session where subscription_id=$SA_ order by occurs_on"
W=300 r adm qa POST subscriptions/$SA_/renew/ '{"starts_on":"2026-10-19"}'; RA=$(jq_ "d.get('id')")
r adm qa POST schedule/generate/ "{\"from\":\"2026-10-19\",\"to\":\"2026-11-02\",\"subscription\":$RA}"
Q "select subscription_id,occurs_on,to_char(starts_at at time zone 'Africa/Cairo','HH24:MI'),status,student_attendance from academy_qa.scheduling_session where subscription_id in ($SA_,$RA) order by occurs_on,subscription_id"
echo "DUPLICATES for student 214:"; dup 214
echo "A=$SA_ RA=$RA SID=$SID" >> ids.env
