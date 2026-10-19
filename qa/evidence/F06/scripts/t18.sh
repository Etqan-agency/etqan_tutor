. ./lib.sh; . ./ids.env
W=100 r adm qa POST people/teachers/218/activate/; r adm qa POST people/students/213/activate/
cf(){ python3 -c "
import json,sys;d=json.loads(sys.argv[1]);c=d.get('conflicts',[]);print('n_conflicts=',len(c));
for x in c[:6]: print('  ',json.dumps({k:(v if not isinstance(v,dict) else {kk:v[kk] for kk in ('id','subscription_id','occurs_on','starts_at','minutes') if kk in v}) for k,v in x.items()})[:300])" "$RESP"; }
echo "-- same teacher 7, Mon/Thu 18:00, subs 16-19"
W=100 r adm qa POST schedule/generate/ "{\"from\":\"2026-10-19\",\"to\":\"2026-10-26\",\"subscription\":$S_EXP}"; cf
r adm qa POST schedule/generate/ "{\"from\":\"2026-10-19\",\"to\":\"2026-10-26\"}"; cf
echo "-- create response for a new clashing sub (teacher 7, Thu 18:00, student 4)"
W=100 r adm qa POST subscriptions/ "{\"student\":215,\"course\":$C1,\"teacher\":7,\"package\":$P2,\"starts_on\":\"2026-10-19\",\"slots\":[{\"weekdays\":[3],\"start_time\":\"18:00\"}]}"; K1=$(jq_ "d['id']"); echo "keys: $(jq_ "[k for k in d if 'confl' in k or 'warn' in k or 'clash' in k]")"; jq_ "{k:(len(v) if isinstance(v,list) else v) for k,v in d.items() if 'confl' in k or 'warn' in k or 'clash' in k}"
echo "-- S5: same student 212 (teacher 7 Thu 18:00) gets teacher B at Thu 18:00"
r adm qa POST subscriptions/ "{\"student\":212,\"course\":$C1,\"teacher\":217,\"package\":$P2,\"starts_on\":\"2026-10-19\",\"slots\":[{\"weekdays\":[3],\"start_time\":\"18:00\"}]}"; K2=$(jq_ "d['id']"); jq_ "{k:v for k,v in d.items() if 'confl' in k or 'warn' in k or 'clash' in k}" | cut -c1-300
r adm qa POST schedule/generate/ "{\"from\":\"2026-10-19\",\"to\":\"2026-10-26\",\"subscription\":$K2}"; cf
echo "-- teacher B back-to-back (X1 Tue 08:00 45m) vs 08:45 and overlap 08:35"
r adm qa POST subscriptions/ "{\"student\":214,\"course\":$C1,\"teacher\":217,\"package\":$P2,\"starts_on\":\"2026-10-19\",\"slots\":[{\"weekdays\":[1],\"start_time\":\"08:45\"}]}"; K3=$(jq_ "d['id']"); jq_ "{k:(len(v) if isinstance(v,list) else v) for k,v in d.items() if 'confl' in k}"
r adm qa POST subscriptions/ "{\"student\":216,\"course\":$C1,\"teacher\":217,\"package\":$P2,\"starts_on\":\"2026-10-19\",\"slots\":[{\"weekdays\":[1],\"start_time\":\"08:35\"}]}"; K4=$(jq_ "d['id']"); jq_ "{k:(len(v) if isinstance(v,list) else v) for k,v in d.items() if 'confl' in k}"
echo "K1=$K1 K2=$K2 K3=$K3 K4=$K4" >> ids.env
grep -n "def .*conflict" -A3 ../../../../backend/etqan/scheduling/services/generation.py | head -20
