. ./lib.sh; . ./ids.env
W=200
echo "== TC-005"
r adm qa DELETE catalogue/packages/$P1/; r adm qa DELETE catalogue/courses/$C1/
r adm qa POST catalogue/packages/$P1/duplicate/; DP=$(jq_ "d['id']"); echo "   copy name=$(jq_ "d['name_en']") active=$(jq_ "d['is_active']")"
r adm qa POST catalogue/courses/$C1/duplicate/; DC_=$(jq_ "d['id']"); echo "   copy name=$(jq_ "d['name_en']") active=$(jq_ "d['is_active']") teachers=$(jq_ "d['teacher_ids']")"
Q "select package_id,country,price_minor,currency from academy_qa.catalogue_packagecountryprice where package_id in ($P1,$DP) order by 1"
r adm qa PATCH catalogue/packages/$P1/ '{"is_active":false}'
r adm qa POST subscriptions/ "{\"student\":215,\"course\":$C1,\"teacher\":7,\"package\":$P1,\"starts_on\":\"2026-10-20\",\"slots\":[{\"weekdays\":[1],\"start_time\":\"14:00\"}]}"
r adm qa PATCH catalogue/packages/$P1/ '{"is_active":true}'
r adm qa PATCH catalogue/courses/$C2/ '{"is_active":false}'
r adm qa POST subscriptions/ "{\"student\":215,\"course\":$C2,\"teacher\":7,\"package\":$P1,\"starts_on\":\"2026-10-20\",\"slots\":[{\"weekdays\":[1],\"start_time\":\"14:00\"}]}"
r adm qa PATCH catalogue/courses/$C2/ '{"is_active":true}'
r adm qa GET subscriptions/$S_SA/; echo "   existing sub keeps: $(jq_ "(d['price_minor'],d['currency'],d['sessions_total'])")"
r adm qa DELETE catalogue/packages/$DP/; r adm qa DELETE catalogue/courses/$DC_/
echo "== TC-007"
cnt(){ Q "select count(*)||':'||string_agg(country||price_minor||currency,',' order by country) from academy_qa.catalogue_packagecountryprice where package_id=$P1"; }
echo "before $(cnt)"
W=160
for b in '[{"country":"SA","price_minor":1,"currency":"SAR"},{"country":"SA","price_minor":2,"currency":"SAR"}]' '[{"country":"AE","price_minor":-1,"currency":"AED"}]' '[{"country":"AE","price_minor":1.5,"currency":"AED"}]' '[{"country":"AE","price_minor":true,"currency":"AED"}]' '[{"country":"AE","price_minor":9223372036854775808,"currency":"AED"}]' '[{"country":"XX1","price_minor":1,"currency":"AED"}]' '[{"country":"S","price_minor":1,"currency":"AED"}]' '[{"country":"","price_minor":1,"currency":"AED"}]' '[{"country":"AE","price_minor":1,"currency":"S"}]' '{"rows":"x"}' '"x"' '[{"country":"AE","price_minor":100,"currency":"AED"},{"country":"KW","price_minor":-5,"currency":"KWD"}]'; do r adm qa PUT catalogue/packages/$P1/country-prices/ "$b"; echo "     -> $(cnt)"; done
r adm qa PUT catalogue/packages/$P1/country-prices/ '[{"country":"AE","price_minor":1,"currency":"sar"}]'; echo "     -> $(cnt)"
big=$(python3 -c "import json,string,itertools;c=[a+b for a,b in itertools.product(string.ascii_uppercase,repeat=2)];print(json.dumps([{'country':x,'price_minor':i,'currency':'USD'} for i,x in enumerate(c[:251])]))")
r adm qa PUT catalogue/packages/$P1/country-prices/ "$big"; echo "     251 -> $(Q "select count(*) from academy_qa.catalogue_packagecountryprice where package_id=$P1")"
big=$(python3 -c "import json,string,itertools;c=[a+b for a,b in itertools.product(string.ascii_uppercase,repeat=2)];print(json.dumps([{'country':x,'price_minor':i,'currency':'USD'} for i,x in enumerate(c[:250])]))")
r adm qa PUT catalogue/packages/$P1/country-prices/ "$big" >/dev/null; echo "[$CODE] 250 -> $(Q "select count(*) from academy_qa.catalogue_packagecountryprice where package_id=$P1")"
echo "== TC-006 API: replace + lowercase"
r adm qa PUT catalogue/packages/$P1/country-prices/ '[{"country":"SA","price_minor":5000,"currency":"SAR"},{"country":"AE","price_minor":4000,"currency":"AED"}]'
r adm qa PUT catalogue/packages/$P1/country-prices/ '[{"country":"sa","price_minor":5000,"currency":"SAR"},{"country":"US","price_minor":3000,"currency":"USD"}]'
echo "     -> $(cnt)"
r adm qa PUT catalogue/packages/$P1/country-prices/ '[{"country":"SA","price_minor":5000,"currency":"SAR"}]'
