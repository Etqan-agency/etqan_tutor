. ./lib.sh; . ./ids.env
perms=$(python3 -c "
v=['view','view_any','create','update','delete','replicate']
p=[f'{r}.{x}' for r in ['course','package','subscription','session','study_group','weekly_schedule','teacher_schedule'] for x in v]+['trial_session.view','trial_session.view_any','trial_session.create']
import json;print(json.dumps(p))")
W=200 r adm qa POST access/roles/ "{\"name_ar\":\"QA6 كتالوج\",\"name_en\":\"QA6 Catalogue+Subs\",\"permissions\":$perms}"; RID=$(jq_ "d['id']"); echo "RID=$RID" >> ids.env
W=300 r adm qa PATCH access/staff/3/ "{\"role_ids\":[3,$RID]}"
login codes qa qa-staff-codes@qa.etqan.test 'QA-People-2026!'
W=200 r adm qa POST catalogue/packages/ '{"name_ar":"غ","name_en":"QA6 Inactive","sessions_per_week":1,"session_minutes":30,"duration_value":1,"duration_unit":"month","price_minor":100,"currency":"EGP","is_active":false}'; PI=$(jq_ "d['id']"); echo "PI=$PI" >> ids.env
rm -f $J/anon; api anon qa GET identity/csrf/
body='{"name_ar":"ب","name_en":"QA6 Perm","sessions_per_week":2,"session_minutes":45,"duration_value":1,"duration_unit":"month","price_minor":150000,"currency":"EGP"}'
for who in adm codes nocode sup tea stu par anon; do
  echo "--- $who"; cnt0=$(Q "select count(*)||'/'||max(updated_at) from academy_qa.catalogue_package")
  api $who qa GET catalogue/courses/; c1=$CODE; api $who qa GET catalogue/packages/; c2=$CODE
  vis=$( [ $CODE = 200 ] && jq_ "sorted(x['id'] for x in d.get('results',d))" ); 
  api $who qa POST catalogue/packages/ "$body"; c3=$CODE; NEW=$( [ $CODE = 201 ] && jq_ "d['id']" )
  api $who qa PATCH catalogue/packages/$P1/ '{"is_active":true}'; c4=$CODE
  api $who qa POST catalogue/packages/$P1/duplicate/; c5=$CODE; DUP=$( [ $CODE = 201 ] && jq_ "d['id']" )
  api $who qa PUT catalogue/packages/$PI/country-prices/ '{"rows":[]}'; c6=$CODE
  api $who qa GET "catalogue/packages/$P1/price/?student=216"; c7=$CODE; pr=${RESP:0:80}
  for x in $NEW $DUP; do api $who qa DELETE catalogue/packages/$x/; c8=$CODE; done
  [ -z "$NEW$DUP" ] && { api $who qa DELETE catalogue/packages/$PI/; c8=$CODE; }
  echo "GETcourses=$c1 GETpkgs=$c2 ids=$vis POST=$c3 PATCH=$c4 DUP=$c5 PUTcp=$c6 price=$c7 DEL=$c8 | $pr"
  echo "   pkg count/maxupd before=$cnt0 after=$(Q "select count(*)||'/'||max(updated_at) from academy_qa.catalogue_package")"
done
# leftovers of admin DUP (copy) cleanup
Q "select id,name_en,is_active from academy_qa.catalogue_package order by id"
