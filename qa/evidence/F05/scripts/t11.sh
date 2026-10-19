. ./lib.sh; . ./ids.env; . ./bulk.env
api adm qa GET access/roles/; echo "$RESP" | python3 -c "import sys,json;d=json.load(sys.stdin);d=d.get('results',d);[print(x['id'],x['name_en'],len(x['permissions'])) for x in d]" | head -12
echo "== TC-014"
r adm qa POST access/staff/ '{"full_name":"QA5 St Edit","email":"f05-st-edit@qa.etqan.test","role_ids":[29]}' | cut -c1-150
sleep 2; accept f05-st-edit@qa.etqan.test ed 'QA-StEdit-2026!'
api ed qa GET identity/me/; echo "ed perms: $(jq_ "sorted(d['permissions'])")"
r ed qa POST people/students/ '{"user":{"full_name":"QA5 Ed Student","email":"f05-ed-stu@qa.etqan.test"},"profile":{}}' | cut -c1-30; ES=$(Q "select id from academy_qa.identity_user where email='f05-ed-stu@qa.etqan.test'"); echo "ES=$ES" >> ids.env
r ed qa PATCH people/students/$ES/ '{"user":{"phone":"+201005550888"}}' | cut -c1-30
FC=$(Q "select count(*) from academy_qa.identity_family")
r ed qa POST people/students/bulk/ "{\"ids\":[$ES],\"action\":\"create_family\",\"name\":\"QA5 Ed Fam\",\"payer_id\":$ES}"
r ed qa POST people/students/bulk/ "{\"ids\":[$ES],\"action\":\"add_to_family\",\"family_id\":$F}"; Q "select family_id from academy_qa.identity_studentprofile where user_id=$ES"
r ed qa POST people/students/bulk/ "{\"ids\":[$ES],\"action\":\"remove_from_family\"}" | cut -c1-40
echo "families $FC -> $(Q "select count(*) from academy_qa.identity_family")"
echo "-- S3: link a parent without parent.view"
W=400 r ed qa POST people/students/$ES/guardians/ "{\"parent_id\":$P2}"
W=400 r ed qa GET people/students/$ES/guardians/
r ed qa GET people/parents/$P2/
W=300 r ed qa GET "people/families/payers/?students=$K1"
r ed qa DELETE people/students/$ES/guardians/$P2/
r ed qa POST people/tags/ '{"kind":"student","name_en":"QA5 Ed tag","name_ar":"ت"}'; r ed qa POST people/teachers/ '{"user":{"full_name":"QA5 Ed T"},"profile":{"gender":"male"}}'
r ed qa POST people/students/$ES/quick-login/; r ed qa POST people/admins/1/deactivate/
echo "== TC-015"
r adm qa POST access/staff/ '{"full_name":"QA5 Staffer","email":"f05-staff@qa.etqan.test","role_ids":[29]}' | cut -c1-200; SF=$(Q "select id from academy_qa.identity_user where email='f05-staff@qa.etqan.test'"); echo "SF=$SF" >> ids.env
r adm qa POST access/staff/ '{"full_name":"QA5 Staffer dup","email":"F05-STAFF@qa.etqan.test","role_ids":[29]}'; r adm qa POST access/staff/ '{"full_name":"QA5 Staffer nomail","role_ids":[29]}'
sleep 2; accept f05-staff@qa.etqan.test sf 'QA-Staff-2026!'
api sf qa GET identity/me/; echo "sf perms: $(jq_ "sorted(d['permissions'])")"
Q "select role,(select count(*) from academy_qa.identity_studentprofile where user_id=$SF)+(select count(*) from academy_qa.identity_teacherprofile where user_id=$SF)+(select count(*) from academy_qa.identity_parentprofile where user_id=$SF) profiles from academy_qa.identity_user where id=$SF"
SUPROLE=$(Q "select id from academy_qa.access_staffrole where name_en ilike 'supervisor' limit 1"); echo "supervisor role $SUPROLE"
r adm qa PATCH access/staff/$SF/ "{\"role_ids\":[$SUPROLE]}" | cut -c1-40; api sf qa GET identity/me/; echo "sf perms after role change: $(jq_ "len(d['permissions'])") teacher.view_any in: $(jq_ "'teacher.view_any' in d['permissions']")"; r sf qa GET people/teachers/ | cut -c1-30
r sf qa PATCH access/staff/$SF/ '{"role_ids":[29]}'; r sf qa PATCH access/staff/$SF/ '{"is_active":false}'
r adm qa PATCH access/staff/$SF/ '{"is_active":false}' | cut -c1-40; r sf qa GET identity/me/ | cut -c1-60
r adm qa PATCH access/staff/$SF/ '{"is_active":true}' | cut -c1-40
api adm qa GET "people/admins/?page_size=100"; echo "staff in admins list: $(jq_ "[x['id'] for x in d['results'] if x['role']!='admin']")"; r adm qa GET people/staff/ | cut -c1-40
Q "select count(*) from academy_qa.access_staffrole_members" 2>/dev/null || PGPASSWORD=etqan psql -h localhost -p 5433 -U etqan -d etqan -tAc "select table_name from information_schema.tables where table_schema='academy_qa' and table_name like 'access%'"
