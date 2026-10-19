. ./lib.sh; . ./ids.env
W=160
for s in 57 59; do Q "select id,student_id,renewed_from_id,status from academy_qa.scheduling_subscription where id=$s"; r adm qa POST subscriptions/$s/cancel/ '{}'
 for i in $(Q "select id from academy_qa.billing_invoice where subscription_id=$s and status<>'void'"); do r adm qa POST billing/invoices/$i/void/ '{}'; done
 r adm qa DELETE subscriptions/$s/; done
Q "select id,renewed_from_id from academy_qa.scheduling_subscription where renewed_from_id=11"
r adm qa PUT schedule/availability/7/ '{"windows":[]}'; r adm qa PUT schedule/availability/217/ '{"windows":[]}'
r adm qa PATCH access/staff/3/ '{"role_ids":[3]}'
r adm qa PATCH access/roles/$RID/ '{"is_active":false}'; r adm qa PATCH access/roles/$R2/ '{"is_active":false}'
echo "-- qaother rows"
r oth qaother POST subscriptions/$OSUB/cancel/ '{}'
for i in $(Q "select id from academy_qaother.billing_invoice where subscription_id=$OSUB and status<>'void'"); do r oth qaother POST billing/invoices/$i/void/ '{}'; done
r oth qaother DELETE subscriptions/$OSUB/
r oth qaother DELETE catalogue/packages/$OP/; r oth qaother DELETE catalogue/courses/$OC/
Q "select (select count(*) from academy_qaother.scheduling_subscription)||' subs, '||(select count(*) from academy_qaother.catalogue_package)||' pkgs'"
Q "select timezone,generation_horizon_days from academy_qa.academy_academysettings"
