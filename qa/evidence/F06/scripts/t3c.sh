. ./lib.sh; . ./ids.env
W=300 r adm qa PUT catalogue/packages/$PI/country-prices/ '{"rows":[]}'
W=300 r adm qa PUT catalogue/packages/$PI/country-prices/ '[]'
W=300 r adm qa POST access/roles/ '{"name_ar":"QA6 باقة","name_en":"QA6 PkgViewOnly","permissions":["package.view","package.view_any"]}'; R2=$(jq_ "d['id']"); echo "R2=$R2" >> ids.env
W=200 r adm qa PATCH access/staff/2/ "{\"role_ids\":[$R2]}"
login nocode qa qa-staff-nocode@qa.etqan.test 'QA-People-2026!'
W=200 r nocode qa GET catalogue/packages/$P1/price/?student=216
W=200 r nocode qa GET catalogue/packages/$P1/price/
W=200 r adm qa PATCH access/staff/2/ '{"role_ids":[]}'
login nocode qa qa-staff-nocode@qa.etqan.test 'QA-People-2026!'
