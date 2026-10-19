. ./lib.sh; . ./ids.env
DC=/Users/khaledsakr/.etqan-qa-tools/dc.sh
$DC exec -T django python -c "
from zoneinfo import ZoneInfo;from datetime import datetime,timezone as T
z=ZoneInfo('Africa/Cairo')
for s in ['2027-04-29T23:30','2027-04-30T00:30','2027-05-06T23:30','2027-05-07T00:30','2027-04-22T23:30','2027-04-23T00:30','2026-10-29T23:30','2026-10-30T00:30']:
  d=datetime.fromisoformat(s).replace(tzinfo=z); print('expect fold0',s,d.astimezone(T.utc), 'fold1', d.replace(fold=1).astimezone(T.utc))"
W=300 r adm qa PATCH catalogue/courses/$C1/ "{\"teacher_ids\":[7,217,218]}"
W=300 r adm qa POST subscriptions/ "{\"student\":215,\"course\":$C1,\"teacher\":218,\"package\":$P1,\"starts_on\":\"2027-04-01\",\"slots\":[{\"weekdays\":[4],\"start_time\":\"00:30\",\"minutes\":30},{\"weekdays\":[4],\"start_time\":\"01:15\",\"minutes\":30},{\"weekdays\":[3],\"start_time\":\"23:30\"}]}"; S11=$(jq_ "d['id']")
W=900 r adm qa POST schedule/generate/ "{\"from\":\"2027-04-20\",\"to\":\"2027-05-10\",\"subscription\":$S11}"
Q "select occurs_on,to_char(starts_at at time zone 'UTC','YYYY-MM-DD HH24:MI'),to_char(starts_at at time zone 'Africa/Cairo','YYYY-MM-DD HH24:MI'),minutes from academy_qa.scheduling_session where subscription_id=$S11 order by starts_at"
W=300 r adm qa POST subscriptions/ "{\"student\":215,\"course\":$C1,\"teacher\":218,\"package\":$P1,\"starts_on\":\"2026-10-22\",\"slots\":[{\"weekdays\":[3],\"start_time\":\"23:30\"},{\"weekdays\":[4],\"start_time\":\"00:30\"}]}"; S11b=$(jq_ "d['id']")
W=900 r adm qa POST schedule/generate/ "{\"from\":\"2026-10-22\",\"to\":\"2026-11-06\",\"subscription\":$S11b}"
Q "select occurs_on,to_char(starts_at at time zone 'UTC','YYYY-MM-DD HH24:MI'),to_char(starts_at at time zone 'Africa/Cairo','YYYY-MM-DD HH24:MI'),minutes from academy_qa.scheduling_session where subscription_id=$S11b order by starts_at"
echo "S11=$S11 S11b=$S11b" >> ids.env
docker logs --since 3m etqan_tutor-django-1 2>&1 | grep -ci "traceback"
