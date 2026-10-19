. ./lib.sh; . ./ids.env
DC=/Users/khaledsakr/.etqan-qa-tools/dc.sh
sess(){ Q "select s.subscription_id,occurs_on,to_char(starts_at at time zone 'UTC','MM-DD HH24:MI')||'Z',to_char(starts_at at time zone 'America/New_York','MM-DD HH24:MI')||' NY' from academy_qa.scheduling_session s where subscription_id in ($S10${1:+,$1}) order by starts_at"; }
echo "before:"; sess
W=400 r adm qa PATCH academy/settings/ '{"timezone":"America/New_York"}'; echo "   (any warning key in response? $(jq_ "[k for k in d if 'warn' in k.lower() or 'notice' in k.lower()]"))"
echo "after tz change (no action):"; sess
$DC exec -T django python manage.py tenant_command shell --schema=academy_qa -c "from etqan.scheduling.services import run_lifecycle; print(run_lifecycle())" 2>&1 | tail -1
W=300 r adm qa POST subscriptions/$S10/renew/ '{}'; R12=$(jq_ "d['id']"); echo "R12=$R12" >> ids.env
W=300 r adm qa POST schedule/generate/ "{\"from\":\"2026-10-19\",\"to\":\"2026-12-14\",\"subscription\":$R12}"
W=300 r adm qa POST schedule/generate/ "{\"from\":\"2026-10-19\",\"to\":\"2026-12-14\",\"subscription\":$S10}"
echo "after lifecycle + generate:"; sess $R12
W=200 r adm qa GET subscriptions/$S10/slots/
W=200 r adm qa PATCH academy/settings/ '{"timezone":"Africa/Cairo"}'
Q "select timezone from academy_qa.academy_academysettings"
