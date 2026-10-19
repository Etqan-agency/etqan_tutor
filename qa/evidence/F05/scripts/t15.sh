. ./lib.sh; . ./ids.env
TOK(){ awk '$6=="csrftoken"{print $7}' $J/$1|tail -1; }
CK(){ for t in identity_user identity_studentprofile identity_teacherprofile identity_parentprofile identity_family identity_tag identity_guardianship employment_contract; do echo -n "$t:$(Q "select md5(coalesce(string_agg(t::text,'' order by id),'')) from $1.$t t" | cut -c1-8) "; done; echo; }
echo "== TC-016"
r oth qaother POST people/parents/ '{"user":{"full_name":"QA5 Other Parent","email":"f05-other-par@qa.etqan.test"},"profile":{}}' | cut -c1-30; OP=$(Q "select id from academy_qaother.identity_user where email='f05-other-par@qa.etqan.test'")
OS=$(Q "select id from academy_qaother.identity_user where email='f05-other-stu@qa.etqan.test'")
r oth qaother POST people/families/ "{\"name\":\"QA5 Other Fam\",\"student_ids\":[$OS],\"payer_id\":$OS}" | cut -c1-30
r oth qaother POST people/tags/ '{"kind":"student","name_en":"QA5 Other Tag","name_ar":"آخر"}' | cut -c1-30
echo "qaother ids: student=$OS parent=$OP; max qa ids user=$(Q "select max(id) from academy_qa.identity_user") family=$(Q "select max(id) from academy_qa.identity_family") tag=$(Q "select max(id) from academy_qa.identity_tag")"
BO=$(CK academy_qaother); BQ=$(CK academy_qa); echo "before qaother: $BO"
echo "-- qaother admin against qa-only ids (on its own host)"
for p in people/students/$S1/ people/parents/$P1/ people/teachers/$TG/ people/families/$F/ people/tags/$BT/ contracts/1/ contracts/1/file/ people/students/$S1/guardians/; do api oth qaother GET $p; echo "GET $p -> $CODE"; done
api oth qaother PATCH people/students/$S1/ '{"user":{"full_name":"HACK"}}'; echo "PATCH student -> $CODE"; api oth qaother POST people/students/$S1/deactivate/; echo "deactivate -> $CODE"
api oth qaother POST people/students/$OS/guardians/ "{\"parent_id\":$P1}"; echo "link qa parent to qaother student -> $CODE ${RESP:0:80}"
api oth qaother POST people/families/ "{\"name\":\"QA5 X\",\"student_ids\":[$K1],\"payer_id\":$P1}"; echo "family with qa ids -> $CODE ${RESP:0:100}"
api oth qaother POST people/students/bulk/ "{\"ids\":[$S1,$K1,$K2],\"action\":\"set_status\",\"status\":\"paused\"}"; echo "bulk qa ids -> $CODE $RESP"
api oth qaother PATCH people/students/$OS/ "{\"profile\":{\"tag_ids\":[$BT]}}"; echo "qa tag id on qaother student -> $CODE ${RESP:0:100}"
echo "-- qa admin: search/CSV for qaother names"
api adm qa GET "people/students/?q=Other%20Student"; echo "q=Other Student -> $(jq_ "d['count']")"; curl -s -b $J/adm "http://qa.etqan.localhost/api/v1/people/students/?format=csv" | grep -c "QA5 Other"
echo "-- cookie replay"
SQ=$(awk '$6=="sessionid"{print $7}' $J/adm | tail -1); SO=$(awk '$6=="sessionid"{print $7}' $J/oth | tail -1)
echo "qa cookie on qaother: $(curl -s -o /dev/null -w '%{http_code}' -H "Cookie: sessionid=$SQ" http://qaother.etqan.localhost/api/v1/identity/me/)  qaother cookie on qa: $(curl -s -o /dev/null -w '%{http_code}' -H "Cookie: sessionid=$SO" http://qa.etqan.localhost/api/v1/identity/me/)"
echo "qa cookie on qa (control): $(curl -s -o /dev/null -w '%{http_code}' -H "Cookie: sessionid=$SQ" http://qa.etqan.localhost/api/v1/identity/me/)"
echo "qa admin cookie on qaother people list: $(curl -s -o /dev/null -w '%{http_code}' -H "Cookie: sessionid=$SQ" http://qaother.etqan.localhost/api/v1/people/students/)"
login xo qa qaother-admin@qa.etqan.test 'QA-Other-2026!'; login xq qaother qa-admin@qa.etqan.test 'QA-Admin-2026!'
echo "-- reset token cross-academy (qaother student invite link on qa host)"
L=$(link f05-other-stu@qa.etqan.test); set -- $(python3 -c "import sys,urllib.parse as u;p=u.urlparse(sys.argv[1]);q=dict(u.parse_qsl(p.query or p.fragment));print(q.get('uid'),q.get('token'),p.netloc)" "$L"); echo "link host=$3"
rm -f $J/anon; api anon qa GET identity/csrf/; r anon qa POST identity/password/reset/confirm/ "{\"uid\":\"$1\",\"token\":\"$2\",\"new_password\":\"QA-Cross-2026!x\"}"
AO=$(CK academy_qaother); AQ=$(CK academy_qa)
echo "qaother unchanged: $([ "$BO" = "$AO" ] && echo YES || echo "NO: $AO")"; echo "qa unchanged: $([ "$BQ" = "$AQ" ] && echo YES || echo "NO: $AQ")"
