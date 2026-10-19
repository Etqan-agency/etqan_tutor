. ./lib.sh; . ./ids.env
W=160
for s in 75 76 73 74 78 77; do r adm qa POST subscriptions/$s/cancel/ '{}'
 for i in $(Q "select id from academy_qa.billing_invoice where subscription_id=$s and status<>'void'"); do r adm qa POST billing/invoices/$i/void/ '{}'; done
 r adm qa DELETE subscriptions/$s/; done
Q "select id,status from academy_qa.scheduling_subscription where id between 73 and 78"
Q "select subscription_id,count(*) from academy_qa.scheduling_session where subscription_id between 73 and 78 group by 1"
