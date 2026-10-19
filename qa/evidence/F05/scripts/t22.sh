. ./lib.sh; . ./ids.env
echo "== TC-031 impersonation cannot escalate"
login imp qa qa-admin@qa.etqan.test 'QA-Admin-2026!' | cut -c1-12; r imp qa POST people/students/$S1/quick-login/ | cut -c1-40
for p in people/students/ people/teachers/ access/staff/ contracts/ people/families/; do api imp qa GET $p; echo "imp-as-student GET $p -> $CODE"; done
api imp qa POST people/admins/ '{"user":{"full_name":"QA5 Esc","email":"f05-esc@qa.etqan.test"},"profile":{}}'; echo "POST admins -> $CODE"
api imp qa POST people/students/$S1/quick-login/; echo "nested quick-login -> $CODE"
api imp qa POST people/teachers/7/quick-login/; echo "quick-login while impersonating -> $CODE ${RESP:0:80}"
echo "esc rows: $(Q "select count(*) from academy_qa.identity_user where email='f05-esc@qa.etqan.test'")"
r adm qa POST people/students/$S1/deactivate/ | cut -c1-12; api imp qa GET identity/me/; echo "imp after target deactivated -> $CODE"; r adm qa POST people/students/$S1/activate/ | cut -c1-12
