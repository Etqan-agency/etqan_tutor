. ./lib.sh; . ./ids.env; . ./bulk.env
V=$(echo $BULK|cut -d, -f50); U0=$(Q "select count(*) from academy_qa.identity_user")
SN(){ Q "select u.full_name,u.phone,u.preferred_language,sp.xp,sp.date_of_birth,sp.country,sp.status,sp.gender from academy_qa.identity_user u join academy_qa.identity_studentprofile sp on sp.user_id=u.id where u.id=$V"; }
B=$(SN); echo "== TC-024 student $V before: $B"
for p in '"xp":1000001' '"xp":-1' '"date_of_birth":"0001-01-01"' '"date_of_birth":"2012-02-30"' '"country":"egy"' '"country":"e"' '"status":"nope"' '"gender":"x"' '"notes":null' '"bogus":1'; do api adm qa PATCH people/students/$V/ "{\"profile\":{$p}}"; echo "profile $p -> $CODE ${RESP:0:110}"; done
api adm qa PATCH people/students/$V/ '{"profile":{"date_of_birth":"2030-01-01"}}'; echo "future DOB -> $CODE age_group=$(jq_ "d['profile']['age_group']" 2>/dev/null)"
api adm qa PATCH people/students/$V/ '{"profile":{"country":" eg "}}'; echo "country ' eg ' -> $CODE $(jq_ "d['profile']['country']" 2>/dev/null) ${RESP:0:80}"
for u in '"phone":"+201 005 550 505"' '"phone":"+2010055505051234"' '"phone":"+20100555050512345"' '"timezone":"UTC+2"' '"full_name":"   QA5 Spaced  "' '"full_name":"QA5 عربي 🌟"' '"bogus":1' '"full_name":null'; do api adm qa PATCH people/students/$V/ "{\"user\":{$u}}"; echo "user $u -> $CODE $(echo "${RESP:0:200}" | grep -o '"full_name":"[^"]*","email[^,]*,"phone":"[^"]*"\|{"user[^}]*}\|"detail[^}]*')"; done
api adm qa PATCH people/students/$V/ "{\"user\":{\"full_name\":\"$(python3 -c 'print("x"*255)')\"}}"; echo "255 -> $CODE"; api adm qa PATCH people/students/$V/ "{\"user\":{\"full_name\":\"$(python3 -c 'print("x"*256)')\"}}"; echo "256 -> $CODE"
$DC exec -T django python manage.py set_features qa --off spanish 2>&1 | tail -1
api adm qa PATCH people/students/$V/ '{"user":{"preferred_language":"es"}}'; echo "es spanish-off -> $CODE ${RESP:0:100}"; api s1 qa PATCH identity/me/ '{"preferred_language":"es"}'; echo "me es off -> $CODE ${RESP:0:100}"
api s1 qa GET identity/me/; echo "s1 stored es, effective_language with spanish off: $(jq_ "(d['preferred_language'],d['effective_language'])")"
$DC exec -T django python manage.py set_features qa --on spanish 2>&1 | tail -1; api adm qa PATCH people/students/$V/ '{"user":{"preferred_language":"es"}}'; echo "es spanish-on -> $CODE"
api adm qa PATCH people/students/$S1/ '{"user":{"preferred_language":"ar"}}' >/dev/null
echo "-- teacher fields (TG=$TG)"
for p in '"default_meeting_url":"javascript:alert(1)"' "\"default_meeting_url\":\"https://x.test/$(python3 -c 'print("a"*2000)')\"" '"payout_method":"nope"' '"pay_currency":"XXX"' '"pay_currency":"eg"' '"pay_currency":"EGPP"' '"pay_currency":""' '"pay_currency":"EGB"' '"pay_currency":"123"'; do api adm qa PATCH people/teachers/$TG/ "{\"profile\":{\"gender\":\"female\",$p}}"; echo "teacher ${p:0:45} -> $CODE ${RESP:0:100} | stored=$(Q "select pay_currency from academy_qa.identity_teacherprofile where user_id=$TG")"; done
api adm qa PATCH people/teachers/$TG/ '{"profile":{"gender":"female","pay_currency":"USD"}}' >/dev/null
api adm qa PATCH people/admins/1/ '{"profile":{"notes":"x"}}'; echo "admin profile -> $CODE ${RESP:0:100}"
echo "after: $(SN)"; echo "users $U0 -> $(Q "select count(*) from academy_qa.identity_user")"
$DC logs --since 3m django 2>&1 | grep -c "Internal Server Error"
echo "== TC-025"
TD=$(Q "select (now() at time zone 'Africa/Cairo')::date"); echo "academy today=$TD"
mk(){ api adm qa POST people/students/ "{\"user\":{\"full_name\":\"QA5 Age $1\"},\"profile\":{\"date_of_birth\":\"$2\"}}"; echo "$1 dob=$2 -> $(jq_ "d['profile']['age_group']")"; }
mk 13today $(python3 -c "import datetime as d;t=d.date.fromisoformat('$TD');print(t.replace(year=t.year-13))"); mk 13tomorrow $(python3 -c "import datetime as d;t=d.date.fromisoformat('$TD')+d.timedelta(days=1);print(t.replace(year=t.year-13))")
mk 18today $(python3 -c "import datetime as d;t=d.date.fromisoformat('$TD');print(t.replace(year=t.year-18))"); mk 18tomorrow $(python3 -c "import datetime as d;t=d.date.fromisoformat('$TD')+d.timedelta(days=1);print(t.replace(year=t.year-18))")
for g in child teen adult minor; do api adm qa GET "people/students/?age_group=$g&page_size=100"; echo "$g api=$(jq_ "d['count']")"; done
echo "SQL child=$(Q "select count(*) from academy_qa.identity_studentprofile where date_of_birth > '$TD'::date - interval '13 years'") teen=$(Q "select count(*) from academy_qa.identity_studentprofile where date_of_birth <= '$TD'::date - interval '13 years' and date_of_birth > '$TD'::date - interval '18 years'") adult=$(Q "select count(*) from academy_qa.identity_studentprofile where date_of_birth <= '$TD'::date - interval '18 years'")"
