. ./lib.sh; . ./ids.env
st(){ api adm qa GET subscriptions/$1/; echo "   sub $1: status=$(jq_ "d['status']") ends_on=$(jq_ "d['ends_on']") grace=$(jq_ "d['grace_ends_on']")"; }
W=200 r adm qa DELETE pauses/2/
r adm qa POST pauses/2/end/; st $S_SA
Q "select id,subscription_id,from_date,to_date from academy_qa.scheduling_subscriptionpause where id in (2,3)"
r adm qa DELETE pauses/3/; st $S_SA
Q "select id from academy_qa.scheduling_subscriptionpause where id=3"
echo "-- overlap old 17 (ends 11-25 after pause) vs renewal R1=$R1 (starts 11-19)"
W=300 r adm qa POST schedule/generate/ "{\"from\":\"2026-11-10\",\"to\":\"2026-11-30\",\"subscription\":$S_EG}"
r adm qa POST schedule/generate/ "{\"from\":\"2026-11-10\",\"to\":\"2026-11-30\",\"subscription\":$R1}"
Q "select subscription_id,occurs_on,to_char(starts_at at time zone 'Africa/Cairo','HH24:MI') from academy_qa.scheduling_session where subscription_id in ($S_EG,$R1) and occurs_on between '2026-11-10' and '2026-11-30' order by occurs_on,subscription_id"
Q "select occurs_on,starts_at,student_id,teacher_id,count(*) from academy_qa.scheduling_session where status<>'cancelled' group by 1,2,3,4 having count(*)>1"
