. ./lib.sh; . ./ids.env
echo "== TC-004"
r adm qa POST people/parents/ '{"user":{"full_name":"QA5 Parent One","email":"f05-par1@qa.etqan.test"},"profile":{"has_whatsapp":true}}'; P1=$(jq_ "d['id']")
r adm qa POST people/parents/ '{"user":{"full_name":"QA5 Parent Two","email":"f05-par2@qa.etqan.test"},"profile":{}}'; P2=$(jq_ "d['id']")
r adm qa POST people/students/ '{"user":{"full_name":"QA5 Kid Zed"},"profile":{}}'; K1=$(jq_ "d['id']")
r adm qa POST people/students/ '{"user":{"full_name":"QA5 Kid Amr"},"profile":{}}'; K2=$(jq_ "d['id']")
echo "P1=$P1 P2=$P2 K1=$K1 K2=$K2" >> ids.env
r adm qa POST people/students/$K1/guardians/ "{\"parent_id\":$P1}"; r adm qa POST people/students/$K2/guardians/ "{\"parent_id\":$P1}"; r adm qa POST people/students/$K1/guardians/ "{\"parent_id\":$P2}"
W=600 r adm qa POST people/students/$K1/guardians/ "{\"parent_id\":$P1}"
Q "select parent_id,student_id,count(*) from academy_qa.identity_guardianship group by 1,2 having count(*)>1"
api adm qa GET people/parents/$P1/children/; echo "children: $(jq_ "[c.get('id') for c in (d if isinstance(d,list) else d.get('results',d))]")"
api adm qa GET people/students/$K1/guardians/; echo "guardians: $(jq_ "[(c.get('id'),c.get('user',c).get('full_name')) for c in (d if isinstance(d,list) else d.get('results',d))]")"
r adm qa DELETE people/students/$K1/guardians/$P2/; r adm qa DELETE people/students/$K1/guardians/$P2/
r adm qa POST people/students/$K1/guardians/ "{\"parent_id\":$TG}"
r adm qa POST people/students/$K1/guardians/ "{\"parent_id\":$P2}" >/dev/null
sleep 2; accept f05-par1@qa.etqan.test p1 'QA-Par1-2026!'
r p1 qa GET identity/me/ >/dev/null; echo "p1 me $CODE children=$(jq_ "[c['id'] for c in d.get('children',[])]")"
$DC exec -T django python manage.py set_features qa --off parents 2>&1 | tail -1
r adm qa GET people/parents/; r adm qa GET people/students/$K1/guardians/
r p1 qa GET identity/me/; login p1x qa f05-par1@qa.etqan.test 'QA-Par1-2026!'
$DC exec -T django python manage.py set_features qa --on parents 2>&1 | tail -1
login p1 qa f05-par1@qa.etqan.test 'QA-Par1-2026!'; api p1 qa GET identity/me/; echo "children after on: $(jq_ "[c['id'] for c in d.get('children',[])]")"
Q "select count(*) from academy_qa.identity_guardianship where parent_id in (select id from academy_qa.identity_parentprofile where user_id in ($P1,$P2))"
echo "== TC-005"
W=600 r adm qa GET "people/families/payers/?students=$K1,$K2"
W=700 r adm qa POST people/families/ "{\"name\":\"QA5 Family A\",\"student_ids\":[$K1,$K2],\"payer_id\":$P1,\"notes\":\"x\"}"; F=$(jq_ "d['id']"); echo "F=$F" >> ids.env
FC=$(Q "select count(*) from academy_qa.identity_family")
r adm qa POST people/families/ "{\"name\":\"QA5 F bad1\",\"student_ids\":[$N2],\"payer_id\":$P1}"
r adm qa POST people/families/ "{\"name\":\"QA5 F bad2\",\"student_ids\":[$N2],\"payer_id\":$TG}"
r adm qa POST people/families/ "{\"name\":\"QA5 F bad3\",\"student_ids\":[],\"payer_id\":$P1}"
r adm qa POST people/families/ "{\"name\":\"QA5 F bad4\",\"student_ids\":[$K1],\"payer_id\":$K1}"
r adm qa POST people/families/ "{\"name\":\"$(python3 -c 'print("x"*121)')\",\"student_ids\":[$N2],\"payer_id\":$N2}"
r adm qa POST people/families/ "{\"name\":\"   \",\"student_ids\":[$N2],\"payer_id\":$N2}"
echo "family count $FC -> $(Q "select count(*) from academy_qa.identity_family")"
r adm qa PATCH people/families/$F/ "{\"payer_id\":$K1}"; r adm qa PATCH people/families/$F/ "{\"payer_id\":$P1}" >/dev/null
r adm qa PATCH people/families/$F/ "{\"student_ids\":[$K1]}"
Q "select user_id,family_id from academy_qa.identity_studentprofile where user_id in ($K1,$K2)"
api adm qa GET "people/students/?account_type=family&page_size=100"; echo "family list: $(jq_ "[x['id'] for x in d['results']]")"
api adm qa GET "people/students/?family=$F"; echo "?family: $(jq_ "[x['id'] for x in d['results']]")"
api adm qa GET "people/students/?account_type=individual&page_size=100"; echo "indiv count $(jq_ "d['count']") has K2: $(jq_ "$K2 in [x['id'] for x in d['results']]")"
r adm qa PATCH people/families/$F/ "{\"student_ids\":[$K1,$K2]}" >/dev/null; echo "re-add $CODE"
r adm qa PATCH people/families/$F/ '{"is_active":false}'; Q "select user_id,family_id from academy_qa.identity_studentprofile where user_id in ($K1,$K2)"
api adm qa GET "people/families/?search=qa5&active=false"; echo "retired search: $(jq_ "[x['id'] for x in d.get('results',d)]")"
r adm qa DELETE people/families/$F/
r adm qa PATCH people/families/$F/ '{"is_active":true}' >/dev/null; echo "reactivate $CODE"
echo "== TC-006"
UPD0=$(Q "select updated_at from academy_qa.identity_family where id=$F" 2>&1); echo "fam row: $(Q "select * from academy_qa.identity_family where id=$F")"
r adm qa POST people/parents/$P1/deactivate/ >/dev/null; echo "deact $CODE"
api adm qa GET people/families/$F/; echo "flag=$(jq_ "d['payer_needs_choosing']") payer=$(jq_ "d.get('payer')")"
$DC exec -T django python manage.py tenant_command shell --schema=academy_qa -c "from etqan.identity import services as s; print('payer',s.family_payer($K1), [u.id for u in s.guardians_by_link($K1)])" 2>&1 | tail -2
r adm qa POST people/parents/$P1/activate/ >/dev/null; api adm qa GET people/families/$F/; echo "after activate flag=$(jq_ "d['payer_needs_choosing']")"
r adm qa DELETE people/students/$K1/guardians/$P1/ >/dev/null; api adm qa GET people/families/$F/; echo "after unlink flag=$(jq_ "d['payer_needs_choosing']")"
echo "fam row: $(Q "select * from academy_qa.identity_family where id=$F")"
r adm qa PATCH people/families/$F/ "{\"payer_id\":$K1}" >/dev/null; api adm qa GET people/families/$F/; echo "repair $CODE flag=$(jq_ "d['payer_needs_choosing']")"
