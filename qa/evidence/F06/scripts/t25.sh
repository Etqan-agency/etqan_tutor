. ./lib.sh; . ./ids.env
DC=/Users/khaledsakr/.etqan-qa-tools/dc.sh
LC(){ $DC exec -T django python manage.py tenant_command shell --schema=academy_qa -c "from etqan.scheduling.services import run_lifecycle; print(run_lifecycle())" 2>&1 | tail -1; }
mk(){ api adm qa POST subscriptions/ "{\"student\":$1,\"course\":$C2,\"teacher\":7,\"package\":$P1,\"starts_on\":\"$2\",\"slots\":[{\"weekdays\":[0,1,2,3,4,5,6],\"start_time\":\"$3\"}]}"; echo "[$CODE] ${RESP:0:120}" >&2; jq_ "d['id']"; }
E1=$(mk 215 2026-09-09 21:00); E2=$(mk 215 2026-09-15 21:30); echo "E1=$E1 E2=$E2" >> ids.env
st(){ Q "select id,status,expired_at is not null,term_ends_on,(select count(*) from academy_qa.scheduling_session se where se.subscription_id=s.id),(select count(*) from academy_qa.scheduling_session se where se.subscription_id=s.id and se.starts_at>now()) from academy_qa.scheduling_subscription s where id in ($E1,$E2,27,28) order by id"; }
api adm qa GET subscriptions/$E2/; echo "E2 in_grace=$(jq_ "d['in_grace']") grace_ends=$(jq_ "d['grace_ends_on']")"
api adm qa GET subscriptions/$E1/; echo "E1 status(api)=$(jq_ "d['status']") grace_ends=$(jq_ "d['grace_ends_on']")"
echo "before:"; st
LC; echo "after run1:"; st
LC; echo "after run2:"; st
