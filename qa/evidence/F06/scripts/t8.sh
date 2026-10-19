. ./lib.sh; . ./ids.env
DC=/Users/khaledsakr/.etqan-qa-tools/dc.sh
W=300 r adm qa PUT catalogue/packages/$P1/country-prices/ '[{"country":"SA","price_minor":5000,"currency":"SAR"}]'
r adm qa GET "catalogue/packages/$P1/price/?student=216"; r adm qa GET "catalogue/packages/$P1/price/?student=212"
sub(){ echo "{\"student\":$1,\"course\":$C1,\"teacher\":7,\"package\":$P1,\"starts_on\":\"2026-10-19\",\"slots\":[{\"weekdays\":[0,3],\"start_time\":\"18:00\"}]$2}"; }
W=500 r adm qa POST subscriptions/ "$(sub 216)"; S_SA=$(jq_ "d['id']")
r adm qa POST subscriptions/ "$(sub 212)"; S_EG=$(jq_ "d['id']")
n0=$(Q "select count(*) from academy_qa.scheduling_subscription")
W=300 r adm qa POST subscriptions/ "$(sub 213 ',"currency":"SAR"')"; echo "   count unchanged? $n0 -> $(Q "select count(*) from academy_qa.scheduling_subscription")"
r adm qa POST subscriptions/ "$(sub 213 ',"price_minor":120000,"currency":"EGP"')"; S_EXP=$(jq_ "d['id']")
$DC exec -T django python manage.py set_features qa --off country_pricing 2>&1 | tail -1
r adm qa GET "catalogue/packages/$P1/price/?student=216"
W=300 r adm qa POST subscriptions/ "$(sub 216 ',"notes":"switch off"')"; S_OFF=$(jq_ "d['id']")
$DC exec -T django python manage.py set_features qa --on country_pricing 2>&1 | tail -1
echo "S_SA=$S_SA S_EG=$S_EG S_EXP=$S_EXP S_OFF=$S_OFF" >> ids.env
Q "select id,student_id,price_minor,currency,sessions_total,session_minutes,starts_on,term_ends_on,status from academy_qa.scheduling_subscription where id in ($S_SA,$S_EG,$S_EXP,$S_OFF) order by id"
Q "\d academy_qa.billing_invoice" | grep -i "subscription\|total\|currency" 
