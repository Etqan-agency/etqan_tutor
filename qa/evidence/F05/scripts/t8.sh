. ./lib.sh; . ./ids.env
uidtok(){ python3 -c "import sys,urllib.parse as u;p=u.urlparse(sys.argv[1]);q=dict(u.parse_qsl(p.query or p.fragment));print(q.get('uid'),q.get('token'))" "$1"; }
echo "== TC-011"
SU=$(Q "select count(*) from public.django_session" 2>/dev/null || echo na); echo "sessions table: $SU"
r adm qa POST people/students/$S1/deactivate/ | grep -o '"is_active":[a-z]*,"account_state":"[a-z_]*"'
r s1 qa GET identity/me/; login s1x qa f05-pend@qa.etqan.test 'QA-Stu1-2026!'; r stu qa GET identity/me/ | cut -c1-30
r adm qa POST people/students/$S1/deactivate/ | cut -c1-20
r adm qa POST people/students/$S1/activate/ | grep -o '"account_state":"[a-z_]*"'; login s1 qa f05-pend@qa.etqan.test 'QA-Stu1-2026!'
# teacher with quick-login (impersonation) session
cp $J/adm $J/imp; r imp qa POST people/teachers/7/quick-login/ | cut -c1-80; r imp qa GET identity/me/ | cut -c1-60
r adm qa POST people/teachers/7/deactivate/ | cut -c1-20; r imp qa GET identity/me/ | cut -c1-90; r tch qa GET identity/me/ | cut -c1-90
r adm qa POST people/teachers/7/activate/ | cut -c1-20; login tch qa qa-teacher@qa.etqan.test 'QA-People-2026!'
# admins
W=400 r adm qa POST people/admins/1/deactivate/
r adm qa POST people/admins/ '{"user":{"full_name":"QA5 Admin Two","email":"f05-adm2@qa.etqan.test"},"profile":{}}' | cut -c1-120; A2=$(Q "select id from academy_qa.identity_user where email='f05-adm2@qa.etqan.test'"); echo "A2=$A2" >> ids.env
sleep 2; accept f05-adm2@qa.etqan.test a2 'QA-Adm2-2026!'
api a2 qa GET people/admins/; echo "blocked flags (a2 view): $(jq_ "[(x['id'],x['user'].get('deactivation_blocked', x.get('deactivation_blocked'))) for x in d['results']]")"
r a2 qa POST people/admins/1/deactivate/ | grep -o '"is_active":[a-z]*'; r adm qa GET identity/me/ | cut -c1-70
r a2 qa POST people/admins/$A2/deactivate/
api a2 qa GET people/admins/; echo "blocked flags: $(jq_ "[(x['id'],x.get('deactivation_blocked'),x['user'].get('deactivation_blocked')) for x in d['results']]")"
r a2 qa POST people/admins/1/activate/ | grep -o '"is_active":[a-z]*'; login adm qa qa-admin@qa.etqan.test 'QA-Admin-2026!'
r codes qa POST people/admins/$A2/deactivate/
r adm qa POST people/admins/$A2/deactivate/ | grep -o '"is_active":[a-z]*'; r a2 qa GET identity/me/ | cut -c1-60
echo "active admins: $(Q "select count(*) from academy_qa.identity_user where role='admin' and is_active")"
echo "== TC-012"
r adm qa POST people/students/ '{"user":{"full_name":"QA5 Inv Deact","email":"f05-invd@qa.etqan.test"},"profile":{}}' | cut -c1-20; ID_=$(Q "select id from academy_qa.identity_user where email='f05-invd@qa.etqan.test'"); echo "ID_=$ID_" >> ids.env
sleep 2; L=$(link f05-invd@qa.etqan.test); r adm qa POST people/students/$ID_/deactivate/ | cut -c1-20
W=300 r adm qa POST people/students/$ID_/invite/
set -- $(uidtok "$L"); rm -f $J/anon; api anon qa GET identity/csrf/; r anon qa POST identity/password/reset/confirm/ "{\"uid\":\"$1\",\"token\":\"$2\",\"new_password\":\"QA-InvD-2026!x\"}"
Q "select is_active, password like '!%' as unusable, (select verified from academy_qa.account_emailaddress where user_id=$ID_) from academy_qa.identity_user where id=$ID_"
login invd qa f05-invd@qa.etqan.test 'QA-InvD-2026!x'
r adm qa GET people/students/$ID_/ | grep -o '"is_active":[a-z]*,"account_state":"[a-z_]*"'
# forgot-password while inactive (S1)
r adm qa POST people/students/$S1/deactivate/ >/dev/null; B=$(curl -s "http://localhost:8025/api/v1/search?query=to:f05-pend@qa.etqan.test" | python3 -c "import sys,json;print(json.load(sys.stdin)['messages_count'])")
r anon qa POST identity/password/reset/ '{"email":"f05-pend@qa.etqan.test"}'; sleep 3; echo "mails to inactive before=$B after=$(curl -s "http://localhost:8025/api/v1/search?query=to:f05-pend@qa.etqan.test" | python3 -c "import sys,json;print(json.load(sys.stdin)['messages_count'])")"
r adm qa POST people/students/$S1/activate/ >/dev/null; login s1 qa f05-pend@qa.etqan.test 'QA-Stu1-2026!'
r adm qa POST people/teachers/$TH/deactivate/ >/dev/null
api adm qa GET "people/teachers/?is_active=true&page_size=100"; echo "active teachers has TH: $(jq_ "$TH in [x['id'] for x in d['results']]") count=$(jq_ "d['count']") SQL=$(Q "select count(*) from academy_qa.identity_user where role='teacher' and is_active")"
api adm qa GET "people/teachers/?is_active=false&page_size=100"; echo "inactive teachers: $(jq_ "[x['id'] for x in d['results']]")"
r adm qa POST people/parents/$P1/deactivate/ >/dev/null; login p1x qa f05-par1@qa.etqan.test 'QA-Par1-2026!'
api adm qa GET people/students/$K1/guardians/; echo "guardians still list P1: $(jq_ "$P1 in [x['id'] for x in d]")"
r adm qa POST people/parents/$P1/activate/ >/dev/null; r adm qa POST people/teachers/$TH/activate/ >/dev/null; login p1 qa f05-par1@qa.etqan.test 'QA-Par1-2026!'
echo "== TC-027"
L=$(link f05-par1@qa.etqan.test 1 2>/dev/null || link f05-par1@qa.etqan.test); set -- $(uidtok "$L"); echo "par1 link uid=$1"
r anon qa POST identity/password/reset/confirm/ "{\"uid\":\"$1\",\"token\":\"$2\",\"new_password\":\"QA-Reuse-2026!x\"}"
r adm qa POST people/students/ '{"user":{"full_name":"QA5 Tok","email":"f05-tok@qa.etqan.test"},"profile":{}}' >/dev/null; sleep 2; L=$(link f05-tok@qa.etqan.test); set -- $(uidtok "$L"); TU=$1; TT=$2
P0=$(Q "select md5(password) from academy_qa.identity_user where email in ('f05-tok@qa.etqan.test','qa-admin@qa.etqan.test') order by id")
OU=$(python3 -c "import base64;print(base64.urlsafe_b64encode(b'1').decode().rstrip('='))")
r anon qa POST identity/password/reset/confirm/ "{\"uid\":\"$OU\",\"token\":\"$TT\",\"new_password\":\"QA-Tamper-2026!x\"}"
r anon qa POST identity/password/reset/confirm/ "{\"uid\":\"$TU\",\"token\":\"${TT:0:10}\",\"new_password\":\"QA-Tamper-2026!x\"}"
r anon qa POST identity/password/reset/confirm/ "{\"uid\":\"$TU\",\"token\":\"$TT\",\"new_password\":\"12345678\"}"
r anon qa POST identity/password/reset/confirm/ "{\"uid\":\"$TU\",\"token\":\"$TT\",\"new_password\":\"password\"}"
rm -f $J/anono; api anono qaother GET identity/csrf/; r anono qaother POST identity/password/reset/confirm/ "{\"uid\":\"$TU\",\"token\":\"$TT\",\"new_password\":\"QA-Cross-2026!x\"}"
echo "passwords unchanged: $([ "$P0" = "$(Q "select md5(password) from academy_qa.identity_user where email in ('f05-tok@qa.etqan.test','qa-admin@qa.etqan.test') order by id")" ] && echo yes || echo NO)"
Q "select count(*) from academy_qaother.identity_user where id=$(python3 -c "import base64,sys;print(base64.urlsafe_b64decode(sys.argv[1]+'==').decode())" $TU)"
