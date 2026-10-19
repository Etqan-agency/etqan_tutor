. ./lib.sh; . ./ids.env
CKF(){ echo "$(Q "select md5(string_agg(t::text,'' order by id)) from academy_qa.identity_family t")/$(Q "select md5(string_agg(id||':'||coalesce(family_id::text,'-'),',' order by id)) from academy_qa.identity_studentprofile")"; }
B=$(CKF); echo "== TC-026 before $B"
$DC exec -T django python manage.py set_features qa --off families 2>&1 | tail -1
r adm qa GET people/families/ | cut -c1-90; r adm qa POST people/families/ "{\"name\":\"QA5 off\",\"student_ids\":[$K1],\"payer_id\":$K1}" | cut -c1-90; r adm qa GET "people/families/payers/?students=$K1" | cut -c1-90
r adm qa POST people/students/bulk/ "{\"ids\":[$K1],\"action\":\"create_family\",\"name\":\"x\",\"payer_id\":$K1}" | cut -c1-90
r adm qa POST people/students/bulk/ "{\"ids\":[$K1],\"action\":\"add_to_family\",\"family_id\":$F}" | cut -c1-90
r codes qa POST people/students/bulk/ "{\"ids\":[$K1],\"action\":\"add_to_family\",\"family_id\":$F}" | cut -c1-90
api adm qa GET people/students/$K1/; echo "student keys has account_type/family: $(jq_ "('account_type' in d['profile'], 'family' in d['profile'])")"
api adm qa GET "people/students/?account_type=family"; echo "?account_type=family [$CODE] count=$(jq_ "d['count']") (all students=$(Q "select count(*) from academy_qa.identity_user where role='student'"))"
curl -s -b $J/adm "http://qa.etqan.localhost/api/v1/people/students/?format=csv" | head -1
$DC exec -T django python manage.py set_features qa --on families 2>&1 | tail -1
A=$(CKF); echo "after $A  identical: $([ "$A" = "$B" ] && echo YES || echo NO)"; api adm qa GET people/families/$F/; echo "family $F [$CODE] students=$(jq_ "[s['id'] for s in d['students']]")"
