. ./lib.sh; . ./ids.env
echo "== TC-009 step 5 redo"
DA=$(Q "select id from academy_qa.identity_user where email='f05-dup@qa.etqan.test'"); echo "DA=$DA" >> ids.env
r adm qa PATCH people/students/$DA/ '{"user":{"email":"F05-DUP@qa.etqan.test"}}' >/dev/null; echo "[$CODE] email now $(Q "select email from academy_qa.identity_user where id=$DA")"; sleep 1; mails f05-dup@qa.etqan.test
echo "== TC-010 confirm"
KEY=$(curl -s "http://localhost:8025/api/v1/search?query=to:f05-pend@qa.etqan.test" | python3 -c "import sys,json;print(json.load(sys.stdin)['messages'][0]['ID'])" | xargs -I{} curl -s http://localhost:8025/api/v1/message/{} | python3 -c "import sys,json,re;print(re.findall(r'key=(\w+)',json.load(sys.stdin)['Text'])[0])")
rm -f $J/anon; api anon qa GET identity/csrf/; r anon qa POST identity/verify-email/ "{\"key\":\"$KEY\"}"
api adm qa GET people/students/$S1/; echo "email=$(jq_ "d['user']['email']") pending=$(jq_ "d['user']['pending_email']")"
Q "select email,\"primary\",verified from academy_qa.account_emailaddress where user_id=$S1 order by id"; Q "select email from academy_qa.identity_user where id=$S1"
login so qa f05-stu1@qa.etqan.test 'QA-Stu1-2026!'; login s1 qa f05-pend@qa.etqan.test 'QA-Stu1-2026!'
sleep 2; mails f05-stu1@qa.etqan.test
r anon qa POST identity/verify-email/ "{\"key\":\"$KEY\"}"
r adm qa POST people/parents/ '{"user":{"full_name":"QA5 Reuse old","email":"f05-stu1@qa.etqan.test"},"profile":{}}' | cut -c1-60
