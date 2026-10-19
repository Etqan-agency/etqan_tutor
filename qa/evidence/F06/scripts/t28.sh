. ./lib.sh; . ./ids.env
W=200
# fresh sub w/o invoice: price 0
r adm qa POST subscriptions/ "{\"student\":215,\"course\":$C2,\"teacher\":7,\"package\":$P2,\"price_minor\":0,\"starts_on\":\"2026-10-20\",\"slots\":[{\"weekdays\":[1],\"start_time\":\"14:00\"}]}"; F=$(jq_ "d['id']"); echo "F=$F inv=$(Q "select count(*) from academy_qa.billing_invoice where subscription_id=$F") sess=$(Q "select count(*) from academy_qa.scheduling_session where subscription_id=$F")"
echo "-- slots"
r adm qa POST subscriptions/$F/slots/ '{"weekdays":[1],"start_time":"14:00"}'
r adm qa POST subscriptions/$F/slots/ '{"weekdays":[],"start_time":"15:00"}'
r adm qa POST subscriptions/$F/slots/ '{"weekdays":[0,1,2,3,4,5,6,0],"start_time":"15:00"}'
r adm qa POST subscriptions/$F/slots/ '{"weekdays":[3],"start_time":"15:00","minutes":14}'
r adm qa POST subscriptions/$F/slots/ '{"weekdays":[3],"start_time":"15:00","minutes":241}'
r adm qa POST subscriptions/$F/slots/ '{"weekdays":[3],"start_time":"15:00","meeting_url":"not a url"}'
SL=$(Q "select id from academy_qa.scheduling_scheduleslot where subscription_id=$F limit 1")
r adm qa PATCH slots/$SL/ '{"start_time":"14:30"}'; Q "select occurs_on,to_char(starts_at at time zone 'Africa/Cairo','HH24:MI') from academy_qa.scheduling_session where subscription_id=$F order by 1"
r adm qa DELETE slots/$SL/
r adm qa PATCH subscriptions/$F/ '{"price_minor":-1}'
echo "-- clean delete"
r adm qa DELETE subscriptions/$F/; Q "select (select count(*) from academy_qa.scheduling_session where subscription_id=$F)||' sess / '||(select count(*) from academy_qa.scheduling_scheduleslot where subscription_id=$F)||' slots'"
echo "-- guarded deletes"
r adm qa DELETE subscriptions/$K1/
r adm qa DELETE subscriptions/$S_EG/
W=200 r adm qa POST subscriptions/ "{\"student\":215,\"course\":$C2,\"teacher\":7,\"package\":$P2,\"price_minor\":0,\"starts_on\":\"2026-10-12\",\"slots\":[{\"weekdays\":[0],\"start_time\":\"07:00\"}]}"; M=$(jq_ "d['id']")
api adm qa POST schedule/generate/ "{\"from\":\"2026-10-19\",\"to\":\"2026-10-19\",\"subscription\":$M}"; MS=$(Q "select id from academy_qa.scheduling_session where subscription_id=$M and occurs_on='2026-10-19'")
r adm qa POST sessions/$MS/attendance/ '{"student_attendance":"present","teacher_attendance":"present"}'
r adm qa DELETE subscriptions/$M/
r adm qa PATCH subscriptions/$M/ '{"starts_on":"2026-10-13"}'
echo "M=$M" >> ids.env
Q "select count(*) from academy_qa.scheduling_session se left join academy_qa.scheduling_subscription s on s.id=se.subscription_id where se.subscription_id is not null and s.id is null"
Q "select count(*) from academy_qa.scheduling_scheduleslot sl left join academy_qa.scheduling_subscription s on s.id=sl.subscription_id where s.id is null"
