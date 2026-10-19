. ./lib.sh; . ./ids.env; . ./bulk.env
r adm qa POST people/students/bulk/ '{"ids":[5],"action":"set_status","status":"active"}' >/dev/null; echo "restored qa-student status $CODE"
echo "== TC-007 add/remove family + S2"
B=$(echo $BULK|cut -d, -f21-22)
r adm qa POST people/students/bulk/ "{\"ids\":[$B],\"action\":\"add_to_family\",\"family_id\":$F}"; Q "select user_id,family_id from academy_qa.identity_studentprofile where user_id in ($B)"
r adm qa POST people/students/bulk/ "{\"ids\":[$B],\"action\":\"remove_from_family\"}"
r adm qa POST people/families/ "{\"name\":\"QA5 Retired Fam\",\"student_ids\":[$(echo $BULK|cut -d, -f23)],\"payer_id\":$(echo $BULK|cut -d, -f23)}"; RF=$(jq_ "d['id']"); echo "RF=$RF" >> ids.env
r adm qa PATCH people/families/$RF/ '{"is_active":false}' >/dev/null
W=500 r adm qa POST people/students/bulk/ "{\"ids\":[$B],\"action\":\"add_to_family\",\"family_id\":$RF}"
Q "select user_id,family_id from academy_qa.identity_studentprofile where user_id in ($B)"
W=500 r adm qa GET people/families/$RF/
W=300 r adm qa PATCH people/families/$RF/ "{\"student_ids\":[$(echo $BULK|cut -d, -f23-24)]}"
$DC exec -T django python manage.py tenant_command shell --schema=academy_qa -c "from etqan.identity import services as s; print('family_payer of added student:', s.family_payer($(echo $B|cut -d, -f1)))" 2>&1 | tail -1
r adm qa POST people/students/bulk/ "{\"ids\":[$B,$(echo $BULK|cut -d, -f24)],\"action\":\"remove_from_family\"}" >/dev/null
echo "== TC-007 session kill via bulk deactivate (s1 live, stu untouched)"
r s1 qa GET identity/me/ | cut -c1-40; S0=$(Q "select count(*) from public.django_session" 2>/dev/null)
r adm qa POST people/students/bulk/ "{\"ids\":[$S1,$(echo $BULK|cut -d, -f25)],\"action\":\"deactivate\"}"
r s1 qa GET identity/me/ | cut -c1-80; r stu qa GET identity/me/ | cut -c1-40; login s1x qa f05-stu1@qa.etqan.test 'QA-Stu1-2026!'
r adm qa POST people/students/bulk/ "{\"ids\":[$S1,$(echo $BULK|cut -d, -f25)],\"action\":\"activate\"}"; login s1 qa f05-stu1@qa.etqan.test 'QA-Stu1-2026!'
echo "== TC-008"
python3 - > /dev/null <<'P'
P
for p in 1 2 3 4 5; do api adm qa GET "people/students/?page=$p"; echo "page $p [$CODE] $(python3 -c "import sys,json;d=json.loads(sys.argv[1]);print(d.get('count'),len(d.get('results',[])),[x['id'] for x in d.get('results',[])])" "$RESP" 2>/dev/null || echo ${RESP:0:80})" ; done > pages.txt; cat pages.txt | cut -c1-120
python3 -c "
import re,ast
ids=[];c=None
for l in open('pages.txt'):
  m=re.match(r'page \d \[200\] (\d+) \d+ (\[.*\])',l)
  if m: c=int(m.group(1)); ids+=ast.literal_eval(m.group(2))
print('count',c,'collected',len(ids),'unique',len(set(ids)))"
echo "SQL students: $(Q "select count(*) from academy_qa.identity_user where role='student'")"
for q in "page_size=100" "page_size=101" "page_size=0" "page_size=abc" "page=0" "page=-1" "page=999"; do api adm qa GET "people/students/?$q"; echo "$q [$CODE] $(python3 -c "import sys,json;d=json.loads(sys.argv[1]);print(len(d['results']) if 'results' in d else d)" "$RESP" 2>/dev/null|cut -c1-80)"; done
cnt(){ api adm qa GET "people/students/?$1&page_size=100"; python3 -c "import sys,json;d=json.loads(sys.argv[1]);print(d.get('count'), len(set(x['id'] for x in d.get('results',[]))))" "$RESP" 2>/dev/null || echo "[$CODE] ${RESP:0:80}"; }
echo "q=Bulk 05 -> $(cnt 'q=Bulk%2005')  SQL $(Q "select count(*) from academy_qa.identity_user where role='student' and full_name ilike '%Bulk 05%'")"
echo "q=2010000 -> $(cnt 'q=2010000')  SQL $(Q "select count(*) from academy_qa.identity_user where role='student' and (phone like '%2010000%' or full_name ilike '%2010000%' or email ilike '%2010000%')")"
echo "q=QA5 -> $(cnt 'q=QA5')  SQL $(Q "select count(*) from academy_qa.identity_user where role='student' and full_name ilike '%QA5%'")"
echo "q=% -> $(cnt 'q=%25')  q=_ -> $(cnt 'q=_')"
echo "is_active=false -> $(cnt 'is_active=false')  SQL $(Q "select count(*) from academy_qa.identity_user where role='student' and not is_active")"
echo "status=trial -> $(cnt 'status=trial')  SQL $(Q "select count(*) from academy_qa.identity_studentprofile where status='trial'")"
echo "country=eg -> $(cnt 'country=eg')  SQL $(Q "select count(*) from academy_qa.identity_studentprofile where country='EG'")"
echo "age_group=teen -> $(cnt 'age_group=teen')  SQL $(Q "select count(*) from academy_qa.identity_studentprofile where date_of_birth > (current_date at time zone 'Africa/Cairo')::date - interval '18 years' and date_of_birth <= (current_date at time zone 'Africa/Cairo')::date - interval '13 years'")"
echo "tag=1&tag=$BT -> $(cnt "tag=1&tag=$BT")  SQL $(Q "select count(distinct studentprofile_id) from academy_qa.identity_studentprofile_tags where tag_id in (1,$BT)")"
echo "tag=abc -> $(cnt 'tag=abc')  nationality= -> $(cnt 'nationality=')  gender= -> $(cnt 'gender=')"
