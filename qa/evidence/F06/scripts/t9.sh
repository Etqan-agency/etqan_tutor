. ./lib.sh; . ./ids.env
W=200 r adm qa PATCH catalogue/packages/$P1/ '{"price_minor":200000,"session_minutes":60,"duration_value":2}'
r adm qa GET subscriptions/$S_EG/; echo "   old: $(jq_ "(d['price_minor'],d['currency'],d.get('session_minutes'),d['term_ends_on'],d['sessions_total'])")"
W=200 r adm qa POST subscriptions/$S_EG/renew/ '{}'; R1=$(jq_ "d['id']"); echo "   renewal: $(jq_ "(d['price_minor'],d['currency'],d.get('session_minutes'),d['starts_on'],d['term_ends_on'],d['sessions_total'])")"
# SA country row currency change -> renewal takes the new price
r adm qa PUT catalogue/packages/$P1/country-prices/ '[{"country":"SA","price_minor":1400,"currency":"USD"}]'
r adm qa POST subscriptions/$S_SA/renew/ '{}'; R2=$(jq_ "d['id']"); echo "   SA renewal: $(jq_ "(d['price_minor'],d['currency'])")"
# S8: package currency PATCH, EG renewal of explicit-price sub 18 (120000 EGP)
r adm qa PATCH catalogue/packages/$P1/ '{"currency":"USD","price_minor":3000}'
r adm qa POST subscriptions/$S_EXP/renew/ '{}'; R3=$(jq_ "d['id']"); echo "   S8 renewal: $(jq_ "(d['price_minor'],d['currency'])")"
# S6: same currency, cheaper country row -> carried?
r adm qa PATCH catalogue/packages/$P1/ '{"currency":"EGP","price_minor":150000,"session_minutes":45,"duration_value":1}'
r adm qa PUT catalogue/packages/$P1/country-prices/ '[{"country":"SA","price_minor":5000,"currency":"SAR"}]'
echo "R1=$R1 R2=$R2 R3=$R3" >> ids.env
Q "select id,renewed_from_id,price_minor,currency,session_minutes,duration_value,duration_unit,sessions_total,starts_on,term_ends_on,status from academy_qa.scheduling_subscription where id in ($S_EG,$S_SA,$S_EXP,$R1,$R2,$R3) order by id"
Q "select subscription_id,currency,amount_minor,status from academy_qa.billing_invoice where subscription_id in ($R1,$R2,$R3) order by 1"
