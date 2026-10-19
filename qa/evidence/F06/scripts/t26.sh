. ./lib.sh; . ./ids.env
rm -f $J/anon; api anon qa GET identity/csrf/
DBS(){ Q "select count(*)||'/'||coalesce(max(updated_at)::text,'') from academy_qa.scheduling_subscription"; }
body="{\"student\":215,\"course\":$C2,\"teacher\":7,\"package\":$P2,\"starts_on\":\"2026-10-21\",\"slots\":[{\"weekdays\":[5],\"start_time\":\"20:00\"}]}"
OWN=11; NOT=$S10
for who in adm codes nocode sup tea stu par anon; do
 d0=$(DBS); P0=$(Q "select count(*) from academy_qa.scheduling_subscriptionpause")
 api $who qa GET subscriptions/; L=$CODE; ids=$( [ $CODE = 200 ] && python3 -c "import json,sys;d=json.loads(sys.argv[1]);r=d.get('results',d);print(d.get('count',len(r)),sorted({x['student']['full_name'][:12] for x in r})[:4],'price' if any('price_minor' in x for x in r) else 'noprice')" "$RESP")
 api $who qa GET subscriptions/$OWN/; G1=$CODE; api $who qa GET subscriptions/$NOT/; G2=$CODE
 api $who qa GET "subscriptions/?format=csv"; CSV=$CODE
 api $who qa POST subscriptions/ "$body"; PO=$CODE; [ $CODE = 201 ] && { NEWID=$(jq_ "d['id']"); echo "   created $NEWID"; echo $NEWID >> t26.created; }
 api $who qa PATCH subscriptions/$NOT/ '{"notes":"x"}'; PA=$CODE
 api $who qa POST subscriptions/$NOT/pauses/ '{"from_date":"2026-11-10","to_date":"2026-11-10"}'; PZ=$CODE
 api $who qa POST subscriptions/$OWN/renew/ '{}'; RN=$CODE
 api $who qa POST subscriptions/99999/cancel/ '{}'; CA=$CODE
 api $who qa POST schedule/generate/ '{"from":"2026-10-19","to":"2026-10-20"}'; GE=$CODE
 api $who qa GET schedule/today/; TD=$CODE
 api $who qa GET bundles/; BU=$CODE; api $who qa GET trials/; TR=$CODE; api $who qa GET schedules/; SC=$CODE
 echo "$who: list=$L [$ids] own=$G1 not=$G2 csv=$CSV POST=$PO PATCH=$PA pause=$PZ renew=$RN cancel404?=$CA gen=$GE today=$TD bundles=$BU trials=$TR schedules=$SC | db $d0 -> $(DBS) pauses $P0->$(Q "select count(*) from academy_qa.scheduling_subscriptionpause")"
done
echo "-- teacher list ids vs DB"; api tea qa GET "subscriptions/?page_size=200"; python3 -c "import json,sys;d=json.loads(sys.argv[1]);r=d.get('results',d);print(sorted(x['id'] for x in r))" "$RESP"
Q "select string_agg(s.id::text,',' order by s.id) from academy_qa.scheduling_subscription s join academy_qa.identity_teacherprofile t on t.id=s.teacher_id where t.user_id=7"
api stu qa GET subscriptions/; python3 -c "import json,sys;d=json.loads(sys.argv[1]);r=d.get('results',d);print('student ids',sorted(x['id'] for x in r))" "$RESP"
api par qa GET subscriptions/; python3 -c "import json,sys;d=json.loads(sys.argv[1]);r=d.get('results',d);print('parent ids',sorted(x['id'] for x in r), 'keys sample', sorted(r[0].keys())[:40] if r else '')" "$RESP"
Q "select string_agg(s.id::text,',') from academy_qa.scheduling_subscription s join academy_qa.identity_studentprofile p on p.id=s.student_id where p.user_id=5"
