. ./lib.sh; . ./ids.env
python3 -c "
from zoneinfo import ZoneInfo;from datetime import datetime,timezone as T
z=ZoneInfo('Africa/Cairo')
for d in ['2026-10-19','2026-10-26','2026-11-02','2026-11-09','2026-11-16']: print('expect',d,datetime.fromisoformat(d+'T18:00').replace(tzinfo=z).astimezone(T.utc))"
W=200 r adm qa POST subscriptions/ "{\"student\":214,\"course\":$C1,\"teacher\":217,\"package\":$P1,\"starts_on\":\"2026-10-19\",\"slots\":[{\"weekdays\":[0],\"start_time\":\"18:00\"}]}"; S10=$(jq_ "d['id']"); echo "S10=$S10" >> ids.env
r adm qa GET subscriptions/$S10/sessions/; echo "$RESP" | python3 -c "import json,sys;d=json.load(sys.stdin);d=d.get('results',d);print([(x.get('occurs_on'),x.get('starts_at')) for x in d])"
W=600 r adm qa POST schedule/generate/ "{\"from\":\"2026-10-19\",\"to\":\"2026-11-30\",\"subscription\":$S10}"
W=600 r adm qa POST schedule/generate/ "{\"from\":\"2026-10-19\",\"to\":\"2026-11-30\",\"subscription\":$S10}"
Q "select occurs_on,starts_at at time zone 'UTC',starts_at at time zone 'Africa/Cairo',minutes,generated,slot_id is not null,teacher_id,student_id,status from academy_qa.scheduling_session where subscription_id=$S10 order by starts_at"
