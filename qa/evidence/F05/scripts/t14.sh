. ./lib.sh; . ./ids.env
TOK(){ awk '$6=="csrftoken"{print $7}' $J/$1|tail -1; }
mpc(){ local jar=$1 sub=$2 m=$3 p=$4; shift 4; curl -s -o $J/.out -w '%{http_code}' -b $J/$jar -c $J/$jar -X $m -H "X-CSRFToken: $(TOK $jar)" -H "Referer: http://$sub.etqan.localhost/app/" "$@" "http://$sub.etqan.localhost/api/v1/$p"; }
$DC exec -T django python manage.py set_features qaother --on families parents contracts 2>&1 | tail -1
echo "== TC-022"
r adm qa POST access/roles/ '{"name_ar":"QA5 عقود","name_en":"QA5 Contract ViewAny","permissions":["contract.view_any"]}' | cut -c1-30; RV=$(Q "select id from academy_qa.access_staffrole where name_en='QA5 Contract ViewAny'")
r adm qa POST access/roles/ '{"name_ar":"QA5 عقود2","name_en":"QA5 Contract View","permissions":["contract.view","contract.view_any"]}' | cut -c1-30; RV2=$(Q "select id from academy_qa.access_staffrole where name_en='QA5 Contract View'")
r adm qa POST access/staff/ "{\"full_name\":\"QA5 CVA\",\"email\":\"f05-cva@qa.etqan.test\",\"role_ids\":[$RV]}" | cut -c1-20; r adm qa POST access/staff/ "{\"full_name\":\"QA5 CV\",\"email\":\"f05-cv@qa.etqan.test\",\"role_ids\":[$RV2]}" | cut -c1-20
sleep 2; accept f05-cva@qa.etqan.test cva 'QA-Cva-2026!x' | tail -1; accept f05-cv@qa.etqan.test cv 'QA-Cv-2026!xx' | tail -1
login tb qa qa-teacher2@qa.etqan.test 'QA-People-2026!' | cut -c1-14
CT=$(Q "select id from academy_qa.employment_contract order by id limit 1"); echo "CT=$CT"
printf "%-7s %5s %5s %5s %5s %5s %5s\n" jar list det file post patch del
for j in adm nocode cva cv tch tb stu par anon; do
 l=$(mpc $j qa GET contracts/); n=$(python3 -c "import json;d=json.load(open('$J/.out'));print(len(d['results']))" 2>/dev/null)
 printf "%-7s %5s %5s %5s %5s %5s %5s\n" $j "$l($n)" $(mpc $j qa GET contracts/$CT/) $(mpc $j qa GET contracts/$CT/file/) $(mpc $j qa POST contracts/ -F teacher=7 -F reference=PERM -F details=x) $(mpc $j qa PATCH contracts/$CT/ -F details=perm) $( [ $j = adm ] && echo skip || mpc $j qa DELETE contracts/$CT/)
done
grep -c . /dev/null; Q "select id,reference,details from academy_qa.employment_contract order by id"
echo "-- direct media URL probes"; FP=$(Q "select file from academy_qa.employment_contract where id=$CT")
for u in "/media/$FP" "/private_media/$FP" "/private/$FP" "/media/../private_media/$FP"; do echo "$u -> $(curl -s -o /dev/null -w '%{http_code}' "http://qa.etqan.localhost$u")"; done
echo "-- qaother admin on qa contract id (own host):"; echo "oth $(mpc oth qaother GET contracts/$CT/) file $(mpc oth qaother GET contracts/$CT/file/)"
echo "-- switch off"; $DC exec -T django python manage.py set_features qa --off contracts 2>&1 | tail -1
echo "adm list $(mpc adm qa GET contracts/) file $(mpc adm qa GET contracts/$CT/file/) ; tch file $(mpc tch qa GET contracts/$CT/file/)"
$DC exec -T django python manage.py set_features qa --on contracts 2>&1 | tail -1
echo "-- deactivated teacher A old session"; r adm qa POST people/teachers/7/deactivate/ | cut -c1-12; echo "tch file $(mpc tch qa GET contracts/$CT/file/)"; r adm qa POST people/teachers/7/activate/ | cut -c1-12; login tch qa qa-teacher@qa.etqan.test 'QA-People-2026!' | cut -c1-12
