. ./lib.sh; . ./ids.env
echo "== TC-009"
r adm qa POST people/students/ '{"user":{"full_name":"QA5 Dup A","email":"f05-dup@qa.etqan.test"},"profile":{}}' | cut -c1-40; DA=$(jq_ "d['id']")
M0=$(curl -s "http://localhost:8025/api/v1/messages?limit=1" | python3 -c "import sys,json;print(json.load(sys.stdin)['total'])"); U0=$(Q "select count(*) from academy_qa.identity_user")
r adm qa POST people/parents/ '{"user":{"full_name":"QA5 Dup1","email":"f05-dup@qa.etqan.test"},"profile":{}}'
r adm qa POST people/parents/ '{"user":{"full_name":"QA5 Dup2","email":"F05-DUP@QA.ETQAN.TEST"},"profile":{}}'
r adm qa POST people/parents/ '{"user":{"full_name":"QA5 Dup3","email":" f05-dup@qa.etqan.test "},"profile":{}}'
r adm qa PATCH people/students/$N2/ '{"user":{"email":"F05-Dup@qa.etqan.test"}}'
r adm qa PATCH people/students/$DA/ '{"user":{"email":"F05-DUP@qa.etqan.test"}}' | cut -c1-200
Q "select email from academy_qa.identity_user where id=$DA"
# pending email: signed-in s1 gets pending f05-pend@
r adm qa PATCH people/students/$S1/ '{"user":{"email":"f05-pend@qa.etqan.test"}}' | grep -o '"email":"[^"]*","phone[^}]*pending_email":"[^"]*"'
r adm qa POST people/parents/ '{"user":{"full_name":"QA5 Dup4","email":"f05-pend@qa.etqan.test"},"profile":{}}'
r oth qaother POST people/teachers/ '{"user":{"full_name":"QA5 Other Dup","email":"f05-dup@qa.etqan.test"},"profile":{"gender":"male"}}' | cut -c1-60
r adm qa POST people/teachers/ '{"user":{"full_name":"QA5 Dup5","email":"QA-Admin@qa.etqan.test"},"profile":{"gender":"male"}}'
sleep 2; M1=$(curl -s "http://localhost:8025/api/v1/messages?limit=1" | python3 -c "import sys,json;print(json.load(sys.stdin)['total'])")
echo "users $U0 -> $(Q "select count(*) from academy_qa.identity_user")  mails $M0 -> $M1 (expected +2: pending confirm/alert for s1, qaother invite)"
PGPASSWORD=etqan psql -h localhost -p 5433 -U etqan -d etqan -c "\d academy_qa.identity_user" | grep -i "unique\|ci"
Q "select (select count(*) from academy_qa.identity_user where lower(email)='f05-dup@qa.etqan.test'),(select count(*) from academy_qaother.identity_user where lower(email)='f05-dup@qa.etqan.test')"
echo "== TC-010 (S1 now has pending f05-pend@; use that as the 'new' address)"
api adm qa GET people/students/$S1/; echo "email=$(jq_ "d['user']['email']") pending=$(jq_ "d['user']['pending_email']")"
Q "select email,\"primary\",verified from academy_qa.account_emailaddress where user_id=$S1 order by id"
login so qa f05-stu1@qa.etqan.test 'QA-Stu1-2026!'; login sn qa f05-pend@qa.etqan.test 'QA-Stu1-2026!'
mails f05-pend@qa.etqan.test; mails f05-stu1@qa.etqan.test
ID=$(curl -s "http://localhost:8025/api/v1/search?query=to:f05-pend@qa.etqan.test" | python3 -c "import sys,json;print(json.load(sys.stdin)['messages'][0]['ID'])"); curl -s http://localhost:8025/api/v1/message/$ID | python3 -c "import sys,json,re;t=json.load(sys.stdin)['Text'];print(re.findall(r'https?://\S+',t))"
