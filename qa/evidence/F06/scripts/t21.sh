. ./lib.sh; . ./ids.env
DC=/Users/khaledsakr/.etqan-qa-tools/dc.sh
Q "select id,converted_to_id from academy_qa.scheduling_trialrequest where id=$TR"
nsub(){ Q "select count(*)||' subs / '||(select count(*) from academy_qa.billing_invoice)||' inv' from academy_qa.scheduling_subscription"; }
echo "== TC-021"; n0=$(nsub); echo "before $n0"
W=300 r adm qa POST bundles/multi-course/ "{\"student_id\":212,\"starts_on\":\"2026-10-19\",\"rows\":[{\"course\":$C1,\"teacher\":7,\"package\":$P1,\"slots\":[{\"weekdays\":[0],\"start_time\":\"17:00\"}]},{\"course\":$C2,\"teacher\":7,\"package\":$P2,\"price_minor\":0}]}"; BM=$(jq_ "d.get('id') or d.get('bundle',{}).get('id')"); echo "BM=$BM" >> ids.env
Q "select s.id,s.bundle_id,s.price_minor,s.currency,(select count(*) from academy_qa.billing_invoice i where i.subscription_id=s.id) from academy_qa.scheduling_subscription s where bundle_id=$BM"
n1=$(nsub); echo "after ok $n1"
r adm qa POST bundles/multi-course/ "{\"student_id\":212,\"starts_on\":\"2026-10-19\",\"rows\":[{\"course\":$C1,\"teacher\":7,\"package\":$P1},{\"course\":$C2,\"teacher\":7,\"package\":$PI}]}"
r adm qa POST bundles/multi-course/ "{\"student_id\":212,\"starts_on\":\"2026-10-19\",\"rows\":[{\"course\":$C1,\"teacher\":7,\"package\":$P1}]}"
r adm qa POST bundles/multi-course/ "{\"student_id\":212,\"starts_on\":\"2026-10-19\",\"rows\":[{\"course\":$C1,\"teacher\":7,\"package\":$P1},{\"course\":$C1,\"teacher\":217,\"package\":$P1}]}"
echo "after failures $(nsub) (expect $n1)"
# bundle cancel with a marked member session
MS=$(Q "select se.id from academy_qa.scheduling_session se join academy_qa.scheduling_subscription s on s.id=se.subscription_id where s.bundle_id=$BM and se.occurs_on='2026-10-19' limit 1"); echo "member session 10-19: $MS"
grep -n "path(" ../../../../backend/etqan/scheduling/api/urls.py | sed -n '/bundles/p' >/dev/null
r adm qa GET bundles/$BM/
echo "== TC-022"
r adm qa POST people/families/ '{"name":"QA6 Family","student_ids":[212,213],"payer_id":212}'; FAM=$(jq_ "d['id']"); echo "FAM=$FAM" >> ids.env
r adm qa POST bundles/family/ "{\"family_id\":$FAM,\"starts_on\":\"2026-10-19\",\"rows\":[{\"student\":212,\"course\":$C1,\"teacher\":7,\"package\":$P1,\"slots\":[{\"weekdays\":[6],\"start_time\":\"12:00\"}]},{\"student\":213,\"course\":$C1,\"teacher\":7,\"package\":$P1,\"slots\":[{\"weekdays\":[6],\"start_time\":\"13:00\"}]}]}"; BF=$(jq_ "d.get('id')"); echo "BF=$BF" >> ids.env
Q "select s.id,s.bundle_id,u.full_name,s.price_minor,s.currency from academy_qa.scheduling_subscription s join academy_qa.identity_studentprofile p on p.id=s.student_id join academy_qa.identity_user u on u.id=p.user_id where bundle_id=$BF"
Q "select id,kind,family_id,student_id,study_group_id from academy_qa.scheduling_subscriptionbundle where id in ($BM,$BF)"
r adm qa POST bundles/family/ "{\"family_id\":$FAM,\"starts_on\":\"2026-10-19\",\"rows\":[{\"student\":212,\"course\":$C1,\"teacher\":7,\"package\":$P1},{\"student\":212,\"course\":$C2,\"teacher\":7,\"package\":$P1}]}"
r adm qa POST bundles/family/ "{\"family_id\":$FAM,\"starts_on\":\"2026-10-19\",\"rows\":[{\"student\":212,\"course\":$C1,\"teacher\":7,\"package\":$P1},{\"student\":216,\"course\":$C1,\"teacher\":7,\"package\":$P1}]}"
r par qa GET subscriptions/; echo "   parent sees students: $(jq_ "sorted(set(x['student']['full_name'] for x in d.get('results',d)))")"
r par qa GET bundles/$BF/; r par qa GET bundles/
r adm qa PATCH people/families/$FAM/ '{"is_active":false}'
r adm qa POST bundles/family/ "{\"family_id\":$FAM,\"starts_on\":\"2026-10-19\",\"rows\":[{\"student\":212,\"course\":$C1,\"teacher\":7,\"package\":$P1},{\"student\":213,\"course\":$C1,\"teacher\":7,\"package\":$P1}]}"
r adm qa PATCH people/families/$FAM/ '{"is_active":true}'
$DC exec -T django python manage.py set_features qa --off family_subscriptions 2>&1 | tail -1
r adm qa POST bundles/family/ "{\"family_id\":$FAM,\"starts_on\":\"2026-10-19\",\"rows\":[{\"student\":212,\"course\":$C1,\"teacher\":7,\"package\":$P1},{\"student\":213,\"course\":$C1,\"teacher\":7,\"package\":$P1}]}"
$DC exec -T django python manage.py set_features qa --on family_subscriptions 2>&1 | tail -1
echo "final $(nsub)"
