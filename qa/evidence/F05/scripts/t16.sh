. ./lib.sh; . ./ids.env
ch(){ api $1 qa GET identity/me/; jq_ "[c['id'] for c in d.get('children',[])] if 'children' in d else 'NO-KEY'"; }
echo "== TC-017"
echo "par children: $(ch par)  SQL: $(Q "select string_agg(s.user_id::text,',') from academy_qa.identity_guardianship g join academy_qa.identity_parentprofile p on p.id=g.parent_id join academy_qa.identity_studentprofile s on s.id=g.student_id where p.user_id=6")"
api par qa GET identity/me/; echo "child profile keys: $(jq_ "sorted(d['children'][0].get('profile',{}).keys()) if d.get('children') else None")"
r adm qa POST people/students/$K2/guardians/ '{"parent_id":6}' | cut -c1-12; echo "after link K2: $(ch par)"
r adm qa DELETE people/students/5/guardians/6/ | cut -c1-12; echo "after unlink 5: $(ch par)"
r adm qa POST people/students/5/guardians/ '{"parent_id":6}' | cut -c1-12; r adm qa DELETE people/students/$K2/guardians/6/ | cut -c1-12; echo "restored: $(ch par)"
for p in people/students/$K2/ people/students/5/ people/students/5/guardians/ people/parents/6/children/ people/families/ contracts/ people/tags/; do api par qa GET $p; echo "par GET $p -> $CODE"; done
echo "p1 children: $(ch p1)  (disjoint from par: 5)"
$DC exec -T django python manage.py set_features qa --off parents 2>&1 | tail -1; echo "par me with parents off: $(api par qa GET identity/me/; echo $CODE)"; $DC exec -T django python manage.py set_features qa --on parents 2>&1 | tail -1
login par qa qa-parent@qa.etqan.test 'QA-People-2026!' | cut -c1-12; login p1 qa f05-par1@qa.etqan.test 'QA-Par1-2026!' | cut -c1-12
echo "== TC-018"
SNAP(){ Q "select u.id,u.role,u.is_active,u.email,u.is_staff,u.is_superuser,u.full_name,u.phone,u.preferred_language,u.timezone,sp.notes,sp.xp,sp.status,sp.family_id,tp.pay_currency from academy_qa.identity_user u left join academy_qa.identity_studentprofile sp on sp.user_id=u.id left join academy_qa.identity_teacherprofile tp on tp.user_id=u.id where u.id=$1"; }
for jp in "s1:$S1" "tch:7" "p1:$P1" "sf:$SF"; do j=${jp%%:*}; id=${jp#*:}
 r $j qa PATCH identity/me/ '{"full_name":"QA5 New Name","phone":"+201005550303","preferred_language":"en","timezone":"Africa/Cairo"}' | cut -c1-14
 B=$(SNAP $id); W=200 r $j qa PATCH identity/me/ '{"role":"admin","is_active":false,"email":"x@qa.etqan.test","is_staff":true,"is_superuser":true,"profile":{"notes":"hacked","xp":999999,"status":"active"},"pay_currency":"USD","family":1}'
 A=$(SNAP $id); echo "  $j mass-assign diff: $([ "$B" = "$A" ] && echo none || echo "CHANGED $B -> $A")"; echo "  $j row: $A"
done
for b in '{"phone":"12345"}' '{"timezone":"Mars/Phobos"}' '{"full_name":"   "}' '{"preferred_language":"es"}' "{\"full_name\":\"$(python3 -c 'print("x"*256)')\"}"; do W=140 r s1 qa PATCH identity/me/ "$b"; done
echo "s1 row after invalid: $(SNAP $S1)"
login imp qa qa-admin@qa.etqan.test 'QA-Admin-2026!' | cut -c1-12; r imp qa POST people/students/$S1/quick-login/ | cut -c1-30
W=200 r imp qa PATCH identity/me/ '{"phone":"+201005550404"}'; W=120 r imp qa PATCH identity/me/ '{"full_name":"QA5 Imp Name"}'
W=200 r s1 qa POST identity/me/emails/ '{"email":"f05-s1-new@qa.etqan.test"}'; W=200 r s1 qa POST identity/me/emails/ '{"email":"f05-s1-new@qa.etqan.test","current_password":"wrong-pass"}'
r adm qa PATCH people/students/$S1/ '{"user":{"full_name":"QA5 Sami"}}' | cut -c1-12
echo "== TC-019"
r adm qa PATCH people/students/$S1/ '{"profile":{"notes":"internal QA5-NOTE","nationality":"foreign"}}' | cut -c1-12
r adm qa PATCH people/teachers/7/ '{"profile":{"gender":"male","payout_method":"bank_account","payout_details":"IBAN QA5-SECRET"}}' | cut -c1-12
r adm qa PATCH people/parents/$P1/ '{"profile":{"notes":"internal QA5-NOTE"}}' | cut -c1-40
r adm qa POST people/students/$S1/guardians/ "{\"parent_id\":$P1}" | cut -c1-12
chk(){ api $1 qa GET "$2"; echo "$1 GET $2 [$CODE] notes:$(echo "$RESP"|grep -c QA5-NOTE) iban:$(echo "$RESP"|grep -c QA5-SECRET) nationality:$(echo "$RESP"|grep -c '"nationality"') ip:$(echo "$RESP"|grep -c last_login_ip)"; }
chk s1 identity/me/; chk p1 identity/me/; chk tch identity/me/; chk tb identity/me/; chk tb people/teachers/7/; chk stu identity/me/
chk sup people/teachers/7/; chk sup people/students/$S1/; chk sup people/parents/$P1/; chk codes people/students/$S1/; chk codes people/teachers/7/
chk tb contracts/; chk p1 people/students/$S1/
curl -s -b $J/adm "http://qa.etqan.localhost/api/v1/people/teachers/?format=csv" > "$EV/teachers.csv"; head -1 "$EV/teachers.csv"; echo "teachers.csv has IBAN: $(grep -c QA5-SECRET "$EV/teachers.csv")"
curl -s -b $J/sup "http://qa.etqan.localhost/api/v1/people/teachers/?format=csv" | grep -c QA5-SECRET
Q "select payout_details from academy_qa.identity_teacherprofile where user_id=7"
