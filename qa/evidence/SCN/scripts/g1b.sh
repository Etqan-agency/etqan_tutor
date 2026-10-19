. ./lib.sh; . ./ids.env
V(){ QQ "$1" | grep -v '^SET$'; }
NEW=89; NINV=153; sed -i '' '/^G1_NINV=/d' ids.env; echo "G1_NINV=$NINV" >> ids.env
echo "== G1b (helper fix: QQ printed 'SET'; NEW=$NEW NINV=$NINV) $(date -u +%FT%TZ)"
V "select id,student_id,teacher_id,status,starts_on,term_ends_on,renewed_from_id from scheduling_subscription where id in ($SUB2,$NEW)"
echo "payer check: invoice payer $(V "select payer_id from billing_invoice where id=$NINV") vs SUB2 invoice payer $(V "select payer_id from billing_invoice where id=$INV2") ; FAM-A payer $(V "select payer_id from identity_family where id=$FA" 2>/dev/null)"
echo "renewal sessions now: $(V "select count(*) from scheduling_session where subscription_id=$NEW") (starts 11-19, beyond the 21-day horizon)"
W=600 r adm qa POST schedule/generate/ "{\"from\":\"2026-10-19\",\"to\":\"2026-12-31\",\"subscription\":$NEW}"
V "select subscription_id,count(*),min(occurs_on),max(occurs_on) from scheduling_session where subscription_id in ($SUB2,$NEW) group by 1"
echo "same-instant duplicates across SUB2+NEW (non-cancelled): $(V "select count(*) from (select starts_at from scheduling_session where subscription_id in ($SUB2,$NEW) and status<>'cancelled' group by 1 having count(*)>1) x")"
echo "renewal invoice count: $(V "select count(*) from billing_invoice where subscription_id=$NEW")"
W=200 r pa qa GET billing/invoices/$NINV/
W=200 r pb qa GET billing/invoices/$NINV/
W=200 r tea qa GET billing/invoices/$NINV/
W=200 r oadm qaother GET billing/invoices/$NINV/
echo "-- cleanup"
W=200 r adm qa POST billing/invoices/$NINV/void/ '{"reason":"SCN gate G1 cleanup"}'
W=200 r adm qa DELETE subscriptions/$NEW/
echo "after cleanup: sub row $(V "select count(*) from scheduling_subscription where id=$NEW") sessions $(V "select count(*) from scheduling_session where subscription_id=$NEW") invoice $(V "select status from billing_invoice where id=$NINV") SUB2 renewal $(V "select count(*) from scheduling_subscription where renewed_from_id=$SUB2")"
