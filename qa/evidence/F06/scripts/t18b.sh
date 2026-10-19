. ./lib.sh; . ./ids.env
Q "select subscription_id,occurs_on,to_char(starts_at at time zone 'Africa/Cairo','HH24:MI'),minutes from academy_qa.scheduling_session where subscription_id in ($X1,$K3,$K4) and occurs_on='2026-10-20' order by starts_at"
Q "delete from academy_qa.scheduling_session where subscription_id in ($K3,$K4) and occurs_on='2026-10-20' returning subscription_id"
W=100 r adm qa POST schedule/generate/ "{\"from\":\"2026-10-20\",\"to\":\"2026-10-20\",\"subscription\":$K3}"
python3 -c "import json,sys;d=json.loads(sys.argv[1]);print('K3 back-to-back conflicts:',[(x['session']['starts_at'],x['other']['starts_at']) for x in d['conflicts']])" "$RESP"
r adm qa POST schedule/generate/ "{\"from\":\"2026-10-20\",\"to\":\"2026-10-20\",\"subscription\":$K4}"
python3 -c "import json,sys;d=json.loads(sys.argv[1]);print('K4 10-min overlap conflicts:',[(x['session']['subscription_id'],x['session']['starts_at'],x['other']['subscription_id'],x['other']['starts_at']) for x in d['conflicts']])" "$RESP"
