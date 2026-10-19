. ./lib.sh; . ./ids.env
mk(){ api adm qa POST subscriptions/ "{\"student\":$1,\"course\":$C1,\"teacher\":217,\"package\":$P1,\"starts_on\":\"2026-10-19\",\"slots\":[{\"weekdays\":[1],\"start_time\":\"$2\"}]}"; jq_ "d['id']"; }
race(){ local id=$1; for who in adm codes; do ( api $who qa POST subscriptions/$id/renew/ '{}'; echo "$who renew $id -> $CODE ${RESP:0:90}" ) & done; wait; }
X1=$(mk 213 08:00); X2=$(mk 215 09:00); echo "X1=$X1 X2=$X2" >> ids.env
race $X1; race $X2
echo "-- S4: cancel the renewal of X1 then race again"
RX=$(Q "select id from academy_qa.scheduling_subscription where renewed_from_id=$X1"); W=120 r adm qa POST subscriptions/$RX/cancel/ '{}'
Q "select id,renewed_from_id,status from academy_qa.scheduling_subscription where id=$RX"
race $X1
Q "select renewed_from_id,count(*) from academy_qa.scheduling_subscription where status<>'cancelled' and renewed_from_id is not null group by 1 having count(*)>1"
Q "select id,renewed_from_id,status from academy_qa.scheduling_subscription where id>$X2 or id=$RX order by id"
Q "select subscription_id,count(*) from academy_qa.billing_invoice where subscription_id in (select id from academy_qa.scheduling_subscription where id>$X2 or id=$RX) group by 1"
docker logs --since 2m etqan_tutor-django-1 2>&1 | grep -c -i traceback
