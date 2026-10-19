. ./lib.sh
echo "== TC-001"; W=900 r adm qa POST people/students/ '{"user":{"full_name":"QA5 Sami","email":"f05-stu1@qa.etqan.test","phone":"+201005550101","preferred_language":"ar"},"profile":{"gender":"male","country":"eg","date_of_birth":"2012-03-01","status":"trial","notes":"private note","nationality":"arab","tag_ids":[1]}}'
S1=$(jq_ "d['id']"); echo S1=$S1 > ids.env
Q "select id,role,is_active,password like '!%' unusable from academy_qa.identity_user where id=$S1"; Q "select email,\"primary\",verified from academy_qa.account_emailaddress where user_id=$S1"
Q "select count(*) from academy_qa.identity_studentprofile where user_id=$S1"; Q "select count(*) from academy_qa.identity_studentprofile_tags t join academy_qa.identity_studentprofile p on p.id=t.studentprofile_id where p.user_id=$S1"
sleep 3; mails f05-stu1@qa.etqan.test; echo "link: $(link f05-stu1@qa.etqan.test)"
accept f05-stu1@qa.etqan.test s1 'QA-Stu1-2026!'
W=900 r s1 qa GET identity/me/
Q "select password like '!%' from academy_qa.identity_user where id=$S1"; Q "select verified from academy_qa.account_emailaddress where user_id=$S1"
echo "== TC-002"
r adm qa POST people/students/ '{"user":{"full_name":"QA5 NoMail A"},"profile":{}}'; N1=$(jq_ "d['id']"); r adm qa POST people/students/ '{"user":{"full_name":"QA5 NoMail B"},"profile":{}}'; N2=$(jq_ "d['id']"); echo "N1=$N1 N2=$N2" >> ids.env
Q "select id,email is null,email from academy_qa.identity_user where id in ($N1,$N2)"
r adm qa POST people/students/$N1/invite/; r adm qa POST people/students/$N1/password-reset/
r adm qa PATCH people/students/$N1/ '{"user":{"email":"f05-nomail@qa.etqan.test"}}'; sleep 2; mails f05-nomail@qa.etqan.test; OLDL=$(link f05-nomail@qa.etqan.test)
r adm qa PATCH people/students/$N1/ '{"user":{"email":""}}'
r adm qa PATCH people/students/$N1/ '{"user":{"email":"f05-nomail2@qa.etqan.test"}}'; sleep 2; mails f05-nomail2@qa.etqan.test
Q "select email from academy_qa.account_emailaddress where user_id=$N1"; Q "select email from academy_qa.identity_user where id=$N1"
up=$(python3 -c "import sys,urllib.parse as u;p=u.urlparse(sys.argv[1]);q=dict(u.parse_qsl(p.query or p.fragment));print(q.get('uid'),q.get('token'))" "$OLDL"); set -- $up
rm -f $J/anon; api anon qa GET identity/csrf/; r anon qa POST identity/password/reset/confirm/ "{\"uid\":\"$1\",\"token\":\"$2\",\"new_password\":\"QA-Old-Link-2026!\"}"
echo "== TC-003"
T0=$(Q "select count(*) from academy_qa.identity_user")
r adm qa POST people/teachers/ '{"user":{"full_name":"QA5 Teacher G","email":"f05-tg@qa.etqan.test"},"profile":{}}'
r adm qa POST people/teachers/ '{"user":{"full_name":"QA5 Teacher G","email":"f05-tg@qa.etqan.test"},"profile":{"gender":"female","payout_method":"vodafone_cash"}}'
echo "count before=$T0 after=$(Q "select count(*) from academy_qa.identity_user")"; mails f05-tg@qa.etqan.test
W=900 r adm qa POST people/teachers/ '{"user":{"full_name":"QA5 Teacher G","email":"f05-tg@qa.etqan.test"},"profile":{"gender":"female","payout_method":"vodafone_cash","payout_details":"+201005550202","pay_currency":"usd","tag_ids":[22],"course_ids":[]}}'; TG=$(jq_ "d['id']")
r adm qa PATCH people/teachers/$TG/ '{"profile":{"payout_method":""}}'
r adm qa PATCH people/teachers/$TG/ '{"user":{"phone":"+201005550203"}}'
r adm qa POST people/teachers/ '{"user":{"full_name":"QA5 Teacher H","email":"f05-th@qa.etqan.test"},"profile":{"gender":"male"}}'; TH=$(jq_ "d['id']"); echo "TG=$TG TH=$TH" >> ids.env
Q "select user_id,pay_currency,payout_method,payout_details from academy_qa.identity_teacherprofile where user_id in ($TG,$TH)"; sleep 2; mails f05-tg@qa.etqan.test; mails f05-th@qa.etqan.test
