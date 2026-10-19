. ./lib.sh; . ./ids.env
echo "== GATE G1 renewal chain (SUB2 $SUB2, SA2, T2, payer PA) $(date -u +%FT%TZ)"
login adm qa qa-admin@qa.etqan.test 'QA-Admin-2026!' >/dev/null
login tea qa qa-teacher@qa.etqan.test 'QA-People-2026!' >/dev/null
login pa qa scn-parent-a@qa.etqan.test 'QA-People-2026!' >/dev/null
login pb qa scn-parent-b@qa.etqan.test 'QA-People-2026!' >/dev/null
login oadm qaother qaother-admin@qa.etqan.test 'QA-Other-2026!' >/dev/null
INV0=$(QQ "select count(*) from billing_invoice"); SES0=$(QQ "select count(*) from scheduling_session"); SUBC0=$(QQ "select count(*) from scheduling_subscription")
echo "before: invoices $INV0 sessions $SES0 subs $SUBC0"
api adm qa GET subscriptions/$SUB2/; echo "SUB2 renewal_starts_on/can_renew: $(j "(d.get('renewal_starts_on'),d.get('can_renew'),d.get('renewal'),d.get('ends_on'),d.get('status'))")"
r tea qa POST subscriptions/$SUB2/renew/ '{}'
r pa qa POST subscriptions/$SUB2/renew/ '{}'
r oadm qa POST subscriptions/$SUB2/renew/ '{}'
echo "counts after denied: inv $(QQ "select count(*) from billing_invoice") subs $(QQ "select count(*) from scheduling_subscription")"
W=900 r adm qa POST subscriptions/$SUB2/renew/ '{}'
NEW=$( [ "$CODE" = 201 ] && j "d.get('subscription',d)['id']" ); echo "G1_NEW=$NEW" >> ids.env; echo "new sub $NEW conflicts: $(j "d.get('conflicts')")"
QQ "select id,student_id,teacher_id,status,starts_on,ends_on,renewed_from_id from scheduling_subscription where id in ($SUB2,${NEW:-0})"
QQ "select id,number,student_id,payer_id,amount_minor,currency,status,subscription_id from billing_invoice where subscription_id=${NEW:-0}"
NINV=$(QQ "select id from billing_invoice where subscription_id=${NEW:-0} limit 1"); echo "G1_NINV=$NINV" >> ids.env
echo "dup sessions same student/teacher/instant across SUB2+NEW:"; QQ "select starts_at,count(*) from scheduling_session where subscription_id in ($SUB2,${NEW:-0}) and status<>'cancelled' group by 1 having count(*)>1"
QQ "select subscription_id,count(*),min(occurs_on),max(occurs_on) from scheduling_session where subscription_id in ($SUB2,${NEW:-0}) group by 1"
W=300 r adm qa POST subscriptions/$SUB2/renew/ '{}'
echo "after 2nd renew: invoices for SUB2-chain $(QQ "select count(*) from billing_invoice where subscription_id in (select id from scheduling_subscription where renewed_from_id=$SUB2)") renewals $(QQ "select count(*) from scheduling_subscription where renewed_from_id=$SUB2")"
W=200 r pa qa GET billing/invoices/$NINV/
W=200 r pb qa GET billing/invoices/$NINV/
W=200 r oadm qaother GET billing/invoices/$NINV/
echo "qaother row unaffected: $(QO "select count(*) from billing_invoice where id=$NINV")"
echo "-- cleanup"
W=200 r adm qa POST billing/invoices/$NINV/void/ '{"reason":"SCN gate G1 cleanup"}'
W=200 r adm qa DELETE subscriptions/$NEW/
echo "after cleanup: sub row $(QQ "select count(*) from scheduling_subscription where id=$NEW") sessions $(QQ "select count(*) from scheduling_session where subscription_id=$NEW") invoice $(QQ "select status from billing_invoice where id=$NINV")"
echo "final: invoices $(QQ "select count(*) from billing_invoice") sessions $(QQ "select count(*) from scheduling_session") subs $(QQ "select count(*) from scheduling_subscription")"
