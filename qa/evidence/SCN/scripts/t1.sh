. ./lib.sh; . ./ids.env
echo "== TC-001"
W=250 mk SA1 people/students/ '{"user":{"full_name":"SCN Student A1","email":"scn-a1@qa.etqan.test"},"profile":{"country":"EG","date_of_birth":"2014-05-10","gender":"male"}}'
W=250 mk SA2 people/students/ '{"user":{"full_name":"SCN Student A2","email":"scn-a2@qa.etqan.test"},"profile":{"country":"EG","date_of_birth":"2016-03-01","gender":"female"}}'
W=250 mk PA people/parents/ '{"user":{"full_name":"SCN Parent A","email":"scn-parent-a@qa.etqan.test"},"profile":{"gender":"male"}}'
W=250 mk SB1 people/students/ '{"user":{"full_name":"SCN Student B1","email":"scn-b1@qa.etqan.test"},"profile":{"country":"EG","gender":"male"}}'
W=250 mk PB people/parents/ '{"user":{"full_name":"SCN Parent B","email":"scn-parent-b@qa.etqan.test"},"profile":{"gender":"female"}}'
. ./ids.env
r adm qa POST people/students/$SA1/guardians/ "{\"parent_id\":$PA}"
r adm qa POST people/students/$SA2/guardians/ "{\"parent_id\":$PA}"
r adm qa POST people/students/$SB1/guardians/ "{\"parent_id\":$PB}"
W=400 mk FA people/families/ "{\"name\":\"SCN Family A\",\"student_ids\":[$SA1,$SA2],\"payer_id\":$PA}"
W=400 mk FB people/families/ "{\"name\":\"SCN Family B\",\"student_ids\":[$SB1],\"payer_id\":$PB}"
. ./ids.env
W=900 r adm qa GET people/families/$FA/
W=600 r adm qa GET "billing/payers/?student=$SA1"
echo "-- SA1 into FAM-B (must be 400)"
W=400 r adm qa PATCH people/families/$FB/ "{\"student_ids\":[$SB1,$SA1]}"
W=400 r adm qa POST people/families/ "{\"name\":\"SCN Family X\",\"student_ids\":[$SA1]}"
QQ "select id,name,payer_id from people_family where id in ($FA,$FB)" 2>&1
QQ "select id,email,role,is_active from identity_user where id in ($SA1,$SA2,$PA,$SB1,$PB)"
QQ "select count(*) from identity_studentprofile where user_id in ($SA1,$SA2,$SB1)" 2>&1
QQ "select lower(email),count(*) from identity_user where email like 'scn-%' group by 1 having count(*)>1"
QQ "select user_id,verified,primary from account_emailaddress where user_id in ($SA1,$SA2,$PA,$SB1,$PB) order by user_id" 2>&1
sleep 3
for e in scn-parent-a scn-a1 scn-a2 scn-b1 scn-parent-b; do echo "$e: $(mails $e@qa.etqan.test)"; done
