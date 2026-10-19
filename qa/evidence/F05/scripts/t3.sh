. ./lib.sh; . ./ids.env
echo "== TC-006 follow-up (payer P1 unlinked from both family students)"
r adm qa POST people/students/$K1/guardians/ "{\"parent_id\":$P1}" >/dev/null; r adm qa PATCH people/families/$F/ "{\"payer_id\":$P1}" >/dev/null
r adm qa DELETE people/students/$K1/guardians/$P1/ >/dev/null; r adm qa DELETE people/students/$K2/guardians/$P1/ >/dev/null
api adm qa GET people/families/$F/; echo "flag after full unlink=$(jq_ "d['payer_needs_choosing']")"
r adm qa PATCH people/families/$F/ "{\"payer_id\":$K1}" >/dev/null; api adm qa GET people/families/$F/; echo "repair flag=$(jq_ "d['payer_needs_choosing']")"
r adm qa POST people/students/$K1/guardians/ "{\"parent_id\":$P1}" >/dev/null; r adm qa POST people/students/$K2/guardians/ "{\"parent_id\":$P1}" >/dev/null
echo "== TC-007"
IDS=$(Q "select string_agg(id::text,',' order by id) from (select id from academy_qa.identity_user where full_name like 'QA5 Bulk%' order by id) x"); echo "BULK=$IDS" > bulk.env
B20=$(echo $IDS | cut -d, -f1-20); B10=$(echo $IDS | cut -d, -f21-30)
r adm qa POST people/students/bulk/ "{\"ids\":[$B20],\"action\":\"set_status\",\"status\":\"paused\"}"
Q "select count(*) from academy_qa.identity_studentprofile where user_id in ($B20) and status='paused'"
r adm qa POST people/tags/ '{"kind":"student","name_en":"QA5 Bulk Tag","name_ar":"QA5 وسم"}'; BT=$(jq_ "d['id']"); r adm qa POST people/tags/ '{"kind":"student","name_en":"QA5 Retired","name_ar":"QA5 متقاعد"}'; RT=$(jq_ "d['id']"); echo "BT=$BT RT=$RT" >> ids.env
r adm qa POST people/students/bulk/ "{\"ids\":[$B20],\"action\":\"add_tag\",\"tag_id\":$BT}"; r adm qa POST people/students/bulk/ "{\"ids\":[$B20],\"action\":\"add_tag\",\"tag_id\":$BT}"
Q "select count(*),count(distinct studentprofile_id) from academy_qa.identity_studentprofile_tags where tag_id=$BT"
r adm qa POST people/students/bulk/ "{\"ids\":[$(echo $B20|cut -d, -f1-5)],\"action\":\"remove_tag\",\"tag_id\":$BT}"; Q "select count(*) from academy_qa.identity_studentprofile_tags where tag_id=$BT"
r adm qa POST people/students/bulk/ "{\"ids\":[$B20],\"action\":\"add_tag\",\"tag_id\":$RT}" >/dev/null; r adm qa PATCH people/tags/$RT/ '{"is_active":false}' >/dev/null
r adm qa POST people/students/bulk/ "{\"ids\":[$B20],\"action\":\"add_tag\",\"tag_id\":$RT}"; r adm qa POST people/students/bulk/ "{\"ids\":[$B20],\"action\":\"remove_tag\",\"tag_id\":$RT}"
# live session on one bulk student: give the first B10 student an email+password via shell
V=$(echo $B10|cut -d, -f1); O=$(echo $B10|cut -d, -f2)
$DC exec -T django python manage.py tenant_command shell --schema=academy_qa -c "
from etqan.identity.models import User
for i,e in (($V,'f05-bulkv@qa.etqan.test'),($O,'f05-bulko@qa.etqan.test')):
    u=User.objects.get(pk=i); u.email=e; u.set_password('QA-Bulk-2026!'); u.save()
" 2>&1 | grep -v -i warn | tail -2
login bv qa f05-bulkv@qa.etqan.test 'QA-Bulk-2026!'; login bo qa f05-bulko@qa.etqan.test 'QA-Bulk-2026!'
r adm qa POST people/students/bulk/ "{\"ids\":[$(echo $B10|cut -d, -f1,3-10)],\"action\":\"deactivate\"}"
r bv qa GET identity/me/ | cut -c1-80; r bo qa GET identity/me/ | cut -c1-60; r adm qa GET identity/me/ | cut -c1-40
r adm qa POST people/students/bulk/ "{\"ids\":[$(echo $B10|cut -d, -f1,3-10)],\"action\":\"activate\"}"; Q "select count(*) from academy_qa.identity_user where id in ($B10) and is_active"
I501=$(python3 -c "print(','.join(str(i) for i in range(1,502)))")
r adm qa POST people/students/bulk/ "{\"ids\":[$I501],\"action\":\"set_status\",\"status\":\"active\"}"; r adm qa POST people/students/bulk/ '{"ids":[],"action":"set_status","status":"active"}'
OTH0=$(Q "select md5(string_agg(t::text,'' order by id)) from academy_qaother.identity_studentprofile t")
r adm qa POST people/students/bulk/ "{\"ids\":[$TG,5,999999,$(echo $B20|cut -d, -f1)],\"action\":\"set_status\",\"status\":\"trial\"}"
Q "select user_id,status from academy_qa.identity_studentprofile where user_id in ($TG,5,$(echo $B20|cut -d, -f1))"; echo "qaother students unchanged: $([ "$OTH0" = "$(Q "select md5(string_agg(t::text,'' order by id)) from academy_qaother.identity_studentprofile t")" ] && echo yes || echo NO)"
W=500 r adm qa POST people/students/bulk/ "{\"ids\":[$(echo $B20|cut -d, -f19-20),$K1],\"action\":\"create_family\",\"name\":\"QA5 Bulk Family\",\"payer_id\":$(echo $B20|cut -d, -f19)}"
W=500 r adm qa POST people/students/bulk/ "{\"ids\":[$(echo $B20|cut -d, -f19-20),$K1],\"action\":\"create_family\",\"family_name\":\"QA5 Bulk Family\"}"
