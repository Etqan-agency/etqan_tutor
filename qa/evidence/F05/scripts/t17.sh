. ./lib.sh; . ./ids.env; . ./bulk.env
TP(){ Q "select string_agg(position::text,',' order by position) from academy_qa.identity_tag where kind='$1'"; }
echo "== TC-020"; api adm qa GET people/tags/; echo "tags: $(jq_ "__import__('collections').Counter(t['kind'] for t in d)")"
echo "student positions: $(TP student)"
r adm qa POST people/tags/ '{"kind":"student","name_en":"QA5 Gifted","name_ar":"موهوب","emoji":"🌟"}' | cut -c1-140; GT=$(Q "select id from academy_qa.identity_tag where name_en='QA5 Gifted'")
r adm qa POST people/tags/ '{"kind":"student","name_en":"QA5 Gifted","name_ar":"موهوب2"}'; r adm qa POST people/tags/ '{"kind":"student","name_en":"qa5 GIFTED","name_ar":"موهوب3"}'
r adm qa POST people/tags/ '{"kind":"teacher","name_en":"QA5 Gifted T","name_ar":"موهوب"}' | cut -c1-60; r adm qa POST people/tags/ '{"kind":"teacher","name_en":"QA5 Gifted","name_ar":"موهوب x"}' | cut -c1-60
r adm qa PATCH people/tags/$GT/ '{"position":1}' | cut -c1-140; echo "positions: $(TP student)"
r adm qa PATCH people/tags/$GT/ '{"position":999}' | cut -c1-140; echo "positions: $(TP student)"
r adm qa PATCH people/tags/$GT/ '{"position":0}'; r adm qa PATCH people/tags/$GT/ '{"kind":"teacher"}' | cut -c1-140; Q "select kind from academy_qa.identity_tag where id=$GT"
X1=$(echo $BULK|cut -d, -f30); X2=$(echo $BULK|cut -d, -f31)
r adm qa PATCH people/students/$X1/ "{\"profile\":{\"tag_ids\":[$GT]}}" | cut -c1-12; r adm qa PATCH people/tags/$GT/ '{"is_active":false}' | cut -c1-160
r adm qa PATCH people/students/$X1/ "{\"user\":{\"phone\":\"+201005550999\"},\"profile\":{\"tag_ids\":[$GT]}}" | grep -o '"tags":\[[^]]*\]' ; echo "  code $CODE"
W=200 r adm qa PATCH people/students/$X2/ "{\"profile\":{\"tag_ids\":[$GT]}}"
W=200 r adm qa POST people/students/bulk/ "{\"ids\":[$X2],\"action\":\"add_tag\",\"tag_id\":$GT}"
api adm qa GET "people/students/?tag=$GT"; echo "filter retired tag: $(jq_ "[x['id'] for x in d['results']]") (X1=$X1)"
api adm qa GET people/tags/; echo "people count on retired tag: $(jq_ "[t['people'] for t in d if t['id']==$GT]")"
W=200 r adm qa PATCH people/students/$X1/ '{"profile":{"tag_ids":[22]}}'
r adm qa DELETE people/tags/$GT/
Q "select kind,lower(name_en),count(*) from academy_qa.identity_tag group by 1,2 having count(*)>1"
echo "-- position race: 6 parallel moves"; for i in 1 2 3 4 5 6; do T=$(Q "select id from academy_qa.identity_tag where kind='student' and is_active order by id limit 1 offset $i"); (api adm qa PATCH people/tags/$T/ "{\"position\":$((7-i))}"; echo -n "$CODE ") & done; wait; echo; echo "positions after race: $(TP student)"
echo "== TC-023 (S1)"
for k in 1 2 3; do E=f05-race$k@qa.etqan.test; seq 5 | xargs -P5 -I{} bash -c ". ./lib.sh; api adm qa POST people/students/ '{\"user\":{\"full_name\":\"QA5 Race {}\",\"email\":\"$E\"},\"profile\":{}}'; echo \$CODE" | sort | uniq -c | tr '\n' ' '; echo " rows=$(Q "select count(*) from academy_qa.identity_user where lower(email)='$E'")"; done
$DC logs --since 2m django 2>&1 | grep -i "IntegrityError\|Traceback\|500" | head -5
echo "-- family claim race"; Y1=$(echo $BULK|cut -d, -f40)
seq 2 | xargs -P2 -I{} bash -c ". ./lib.sh; api adm qa POST people/families/ '{\"name\":\"QA5 Race Fam {}\",\"student_ids\":[$Y1],\"payer_id\":$Y1}'; echo \"\$CODE \${RESP:0:80}\""
Q "select count(*) from academy_qa.identity_family where name like 'QA5 Race Fam%'"; Q "select family_id from academy_qa.identity_studentprofile where user_id=$Y1"
echo "-- parallel PATCH same email on two people"; Z1=$(echo $BULK|cut -d, -f41); Z2=$(echo $BULK|cut -d, -f42)
for z in $Z1 $Z2; do (api adm qa PATCH people/students/$z/ '{"user":{"email":"f05-race-patch@qa.etqan.test"}}'; echo "$z $CODE ${RESP:0:60}") & done; wait
Q "select count(*) from academy_qa.identity_user where lower(email)='f05-race-patch@qa.etqan.test'"
