. ./lib.sh; . ./ids.env
echo "== TC-011 redo (separate sessions)"
login adm qa qa-admin@qa.etqan.test 'QA-Admin-2026!' | cut -c1-12; login imp qa qa-admin@qa.etqan.test 'QA-Admin-2026!' | cut -c1-12; login tch qa qa-teacher@qa.etqan.test 'QA-People-2026!' | cut -c1-12
r imp qa POST people/teachers/7/quick-login/ | cut -c1-60; r imp qa GET identity/me/ | grep -o '"id":[0-9]*,"email":"[^"]*"' | head -1; r adm qa GET identity/me/ | grep -o '"id":[0-9]*' | head -1
r adm qa POST people/teachers/7/deactivate/ | grep -o '"is_active":[a-z]*'
r imp qa GET identity/me/ | cut -c1-80; r tch qa GET identity/me/ | cut -c1-80; r adm qa GET identity/me/ | cut -c1-30
r adm qa POST people/teachers/7/activate/ | grep -o '"is_active":[a-z]*'; login tch qa qa-teacher@qa.etqan.test 'QA-People-2026!' | cut -c1-12
W=400 r adm qa POST people/admins/1/deactivate/
api adm qa GET people/admins/; echo "admins: $(jq_ "[(x['id'],{k:v for k,v in x.items() if 'block' in k}) for x in d['results']]")"
r adm qa POST people/admins/ '{"user":{"full_name":"QA5 Admin Two","email":"f05-adm2@qa.etqan.test"},"profile":{}}' | cut -c1-80; A2=$(Q "select id from academy_qa.identity_user where email='f05-adm2@qa.etqan.test'"); echo "A2=$A2" >> ids.env
sleep 2; accept f05-adm2@qa.etqan.test a2 'QA-Adm2-2026!'
api a2 qa GET people/admins/; echo "admins (a2): $(jq_ "[(x['id'],{k:v for k,v in x.items() if 'block' in k}) for x in d['results']]")"
r a2 qa POST people/admins/1/deactivate/ | grep -o '"is_active":[a-z]*'; r adm qa GET identity/me/ | cut -c1-70
api a2 qa GET people/admins/; echo "admins after A1 off: $(jq_ "[(x['id'],x['user']['is_active'],{k:v for k,v in x.items() if 'block' in k}) for x in d['results']]")"
W=200 r a2 qa POST people/admins/$A2/deactivate/
r a2 qa POST people/admins/1/activate/ | grep -o '"is_active":[a-z]*'; login adm qa qa-admin@qa.etqan.test 'QA-Admin-2026!' | cut -c1-12
r codes qa POST people/admins/$A2/deactivate/
r adm qa POST people/admins/$A2/deactivate/ | grep -o '"is_active":[a-z]*'; r a2 qa GET identity/me/ | cut -c1-60
echo "active admins: $(Q "select count(*) from academy_qa.identity_user where role='admin' and is_active")"
