. ./lib.sh; . ./ids.env
W=250 r adm qa POST trials/ "{\"student\":214,\"course\":$C1,\"source\":\"api\",\"minutes\":30,\"heard_from\":\"referral\"}"; TR=$(jq_ "d['id']"); echo "TR=$TR" >> ids.env
r adm qa GET "trials/suggest/?course=$C1&occurs_on=2026-10-19&start_time=07:00&minutes=30"
r adm qa POST trials/$TR/schedule/ '{"teacher_id":7,"occurs_on":"2026-10-19","start_time":"07:00"}'
r adm qa POST trials/$TR/schedule/ '{"teacher_id":7,"occurs_on":"2026-10-19","start_time":"07:10"}'
TS=$(Q "select id from academy_qa.scheduling_session where trial_id=$TR and status<>'cancelled'"); Q "select id,kind,subscription_id,slot_id,status from academy_qa.scheduling_session where trial_id=$TR"
sb="{\"student\":214,\"course\":$C1,\"teacher\":7,\"package\":$P2,\"starts_on\":\"2026-10-20\",\"slots\":[{\"weekdays\":[2],\"start_time\":\"16:00\"}],\"trial_id\":$TR}"
echo "-- convert before completion"; r adm qa POST subscriptions/ "$sb"
r adm qa POST sessions/$TS/attendance/ '{"student_attendance":"present","teacher_attendance":"present"}'
echo "-- wrong student"; r adm qa POST subscriptions/ "$(echo $sb | sed 's/"student":214/"student":215/')"
echo "-- staff codes (no trial_session.update)"; r codes qa POST subscriptions/ "$sb"
n0=$(Q "select count(*) from academy_qa.scheduling_subscription")
r adm qa POST subscriptions/ "$sb"; CV=$(jq_ "d.get('id')"); echo "CV=$CV" >> ids.env
r adm qa POST subscriptions/ "$sb"
Q "select id,status,converted_to_id from academy_qa.scheduling_trialrequest where id=$TR"
Q "select subscription_id,amount_minor,currency from academy_qa.billing_invoice where subscription_id=$CV"
r adm qa DELETE trials/$TR/
Q "select count(*) from academy_qa.scheduling_session where kind='trial' and trial_id=$TR and status<>'cancelled'"
