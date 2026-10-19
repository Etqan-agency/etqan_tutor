# F06 retest 1 (Agent 2): QA-039/040/041/042 original repros on fresh data
. ./lib.sh; . ./ids.env
DC=/Users/khaledsakr/.etqan-qa-tools/dc.sh
cf(){ python3 -c "
import json,sys;d=json.loads(sys.argv[1]);c=d.get('conflicts','<NO KEY>');
if isinstance(c,str): print('conflicts key:',c); sys.exit()
print('n_conflicts=',len(c))
for x in c[:8]: print('  session',x['session'].get('id'),x['session'].get('occurs_on'),x['session'].get('starts_at'),'| other',x['other'].get('id'),x['other'].get('subscription_id'),x['other'].get('starts_at'))" "$RESP"; }
login adm qa qa-admin@qa.etqan.test 'QA-Admin-2026!'
echo "===== QA-042 create with a clash (teacher 7 Thu 18:00 already held by subs 16-19/35)"
W=150 r adm qa POST subscriptions/ "{\"student\":216,\"course\":$C1,\"teacher\":7,\"package\":$P2,\"starts_on\":\"2026-10-19\",\"slots\":[{\"weekdays\":[3],\"start_time\":\"18:00\"}]}"; N1=$(jq_ "d['id']"); cf
echo "DB check: teacher-7 non-cancelled sessions overlapping sub $N1"
Q "select a.id,a.occurs_on,b.id,b.subscription_id from academy_qa.scheduling_session a join academy_qa.scheduling_session b on a.teacher_id=b.teacher_id and a.id<>b.id and b.status<>'cancelled' and a.starts_at < b.starts_at + make_interval(mins=>b.minutes) and b.starts_at < a.starts_at + make_interval(mins=>a.minutes) where a.subscription_id=$N1 and a.status<>'cancelled' order by 2,3"
echo "===== QA-042 control create without clash (teacher 217 Sat 03:00)"
r adm qa POST subscriptions/ "{\"student\":216,\"course\":$C1,\"teacher\":217,\"package\":$P2,\"starts_on\":\"2026-10-19\",\"slots\":[{\"weekdays\":[5],\"start_time\":\"03:00\"}]}"; N2=$(jq_ "d['id']"); cf
echo "===== QA-042 renew with a clash / control"
r adm qa POST subscriptions/$N1/renew/ '{}'; N1R=$(jq_ "d.get('id')"); cf
r adm qa POST subscriptions/$N2/renew/ '{}'; N2R=$(jq_ "d.get('id')"); cf
echo "===== QA-042 GET detail has no conflicts key (create/renew only)"
api adm qa GET subscriptions/$N1/; echo "[$CODE] keys has conflicts: $(jq_ "'conflicts' in d")"
echo "===== QA-042 non-office cannot create (teacher jar)"
login tea qa qa-teacher@qa.etqan.test 'QA-People-2026!'
W=120 r tea qa POST subscriptions/ "{\"student\":216,\"course\":$C1,\"teacher\":7,\"package\":$P2,\"starts_on\":\"2026-10-19\",\"slots\":[{\"weekdays\":[3],\"start_time\":\"18:00\"}]}"
echo "===== QA-039 original repro (early renewal over a marked session), student 215 Mon 05:00"
W=150 r adm qa POST subscriptions/ "{\"student\":215,\"course\":$C2,\"teacher\":7,\"package\":$P1,\"starts_on\":\"2026-10-05\",\"slots\":[{\"weekdays\":[0],\"start_time\":\"05:00\"}]}"; A2=$(jq_ "d['id']"); cf
r adm qa POST schedule/generate/ "{\"from\":\"2026-10-05\",\"to\":\"2026-10-19\",\"subscription\":$A2}"
SID2=$(Q "select id from academy_qa.scheduling_session where subscription_id=$A2 and occurs_on='2026-10-19'"); echo "A2=$A2 session 10-19=$SID2"
W=120 r adm qa POST sessions/$SID2/attendance/ '{"student_attendance":"present","teacher_attendance":"present"}'
W=150 r adm qa POST subscriptions/$A2/renew/ '{"starts_on":"2026-10-19"}'; RA2=$(jq_ "d.get('id')"); cf
r adm qa POST schedule/generate/ "{\"from\":\"2026-10-19\",\"to\":\"2026-11-02\",\"subscription\":$RA2}"; cf
Q "select subscription_id,occurs_on,to_char(starts_at at time zone 'Africa/Cairo','HH24:MI'),status,student_attendance from academy_qa.scheduling_session where subscription_id in ($A2,$RA2) and occurs_on between '2026-10-12' and '2026-10-26' order by occurs_on,subscription_id"
echo "===== QA-040 original repro: deactivate teacher 218 + student 213 (sub S17=$S17)"
W=100 r adm qa POST people/teachers/218/deactivate/; r adm qa POST people/students/213/deactivate/
T0=$(Q "select now()"); echo "deactivated at $T0"
Q "select id,is_active from academy_qa.identity_user where id in (213,218)"
Q "delete from academy_qa.scheduling_session where subscription_id=$S17 and occurs_on in ('2026-10-19','2026-10-27','2026-10-28') and student_attendance='not_set' and teacher_attendance='not_set' and status='scheduled' returning occurs_on"
echo "run_lifecycle:"; $DC exec -T django python manage.py tenant_command shell --schema=academy_qa -c "from etqan.scheduling.services import run_lifecycle; print(run_lifecycle())" 2>&1 | tail -1
W=400 r adm qa POST schedule/generate/ "{\"from\":\"2026-10-19\",\"to\":\"2026-11-02\",\"subscription\":$S17}"; echo "created=$(jq_ "d.get('created')") skipped_inactive=$(jq_ "d.get('skipped_inactive')")"
echo "sessions of S17 created after deactivation: $(Q "select count(*) from academy_qa.scheduling_session where subscription_id=$S17 and created_at > '$T0'")"
api adm qa GET schedule/today/; echo "today board S17 rows (inactive): $(python3 -c "import sys,json;d=json.loads(sys.argv[1]);print(sum(1 for r in d['rows'] if r.get('subscription_id')==$S17))" "$RESP")"
echo "renew/create with inactive people still refused:"; W=150 r adm qa POST subscriptions/$S17/renew/ '{}'
echo "-- teacher only inactive (student re-activated): still skipped"
W=80 r adm qa POST people/students/213/activate/
W=400 r adm qa POST schedule/generate/ "{\"from\":\"2026-10-19\",\"to\":\"2026-11-02\",\"subscription\":$S17}"; echo "created=$(jq_ "d.get('created')") skipped_inactive=$(jq_ "d.get('skipped_inactive')")"
echo "-- reactivate teacher -> horizon refills"
W=80 r adm qa POST people/teachers/218/activate/
api adm qa GET schedule/today/; echo "today board S17 rows (active): $(python3 -c "import sys,json;d=json.loads(sys.argv[1]);print([ (r.get('state'),r.get('session_id')) for r in d['rows'] if r.get('subscription_id')==$S17])" "$RESP")"
W=400 r adm qa POST schedule/generate/ "{\"from\":\"2026-10-19\",\"to\":\"2026-11-02\",\"subscription\":$S17}"; echo "created=$(jq_ "d.get('created')") skipped_inactive=$(jq_ "d.get('skipped_inactive')")"
Q "select occurs_on from academy_qa.scheduling_session where subscription_id=$S17 and created_at > '$T0' order by 1"
echo "===== QA-041 API unchanged: PATCH timezone keeps old instants (proposal), restored"
r adm qa GET academy/settings/; echo "tz=$(jq_ "d.get('timezone')")"
echo "N1=$N1 N2=$N2 N1R=$N1R N2R=$N2R A2=$A2 RA2=$RA2 SID2=$SID2" >> ids.env
