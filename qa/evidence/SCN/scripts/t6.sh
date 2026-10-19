. ./lib.sh; . ./ids.env
echo "== TC-006"
TP1=$(QQ "select id from identity_teacherprofile where user_id=$T1"|tail -1); TP2=$(QQ "select id from identity_teacherprofile where user_id=$T2"|tail -1)
S2X=$(QQ "select id from scheduling_session where subscription_id=$SUB2 order by starts_at limit 1"|tail -1); S1X=354
echo "S2X=$S2X" >> ids.env
for who in "tea $TP1 $S1X $S2X SA2" "t2 $TP2 $S2X $S1X SA1"; do set -- $who
 api $1 qa GET "sessions/?page_size=1000"; n=$(j "d['count'] if isinstance(d,dict) else len(d)"); db=$(QQ "select count(*) from scheduling_session where teacher_id=$2 and archived_at is null"|tail -1)
 ids=$(j "sorted(s['id'] for s in d['results'])"); dbids=$(QQ "select string_agg(id::text,',' order by id) from scheduling_session where teacher_id=$2 and archived_at is null" | tail -1)
 echo "$1 sessions API=$n DB=$db idsets_equal=$(python3 -c "import sys;print(sorted(eval(sys.argv[1]))==sorted(int(x) for x in sys.argv[2].split(',')))" "$ids" "$dbids")"
 W=100 r $1 qa GET sessions/$3/; W=100 r $1 qa GET sessions/$4/
 api $1 qa GET "people/students/?page_size=500"; echo "$1 students: [$CODE] $(j "[s['user']['full_name'] for s in d['results'] if s['user']['full_name'].startswith('SCN')] if isinstance(d,dict) and 'results' in d else d")"
 api $1 qa GET "subscriptions/?page_size=500"; echo "$1 subs: [$CODE] $(j "[ (s['id'],s['student']['full_name']) for s in d['results'] if s['id'] in ($SUB1,$SUB2)] if 'results' in d else d")"
 W=100 r $1 qa GET billing/invoices/
 api $1 qa GET payroll/payslips/; echo "$1 payslips [$CODE] teachers: $(j "sorted(set(p['teacher']['id'] for p in (d['results'] if isinstance(d,dict) else d)))")"
 W=100 r $1 qa GET schedule/today/
done
docker logs etqan_tutor-django-1 --since 3m 2>&1 | grep -c '" 500 \|Traceback'
echo "== TC-007 data: U1..U3 regular yesterday on SUB1, U4 extra"
for n in 1 2 3; do W=200 mk U$n sessions/regular/ "{\"subscription\":$SUB1,\"occurs_on\":\"2026-10-18\",\"start_time\":\"1$((n-1)):00\"}"; done
W=200 mk U4 sessions/extra/ "{\"student\":$SA1,\"course\":$C1,\"teacher\":$T1,\"subscription\":$SUB1,\"occurs_on\":\"2026-10-18\",\"start_time\":\"13:00\",\"minutes\":60,\"pays_teacher\":true}"
. ./ids.env; echo "U1=$U1 U2=$U2 U3=$U3 U4=$U4"
api adm qa GET subscriptions/$SUB1/; echo "R before: $(j "(d['sessions_used'],d['sessions_remaining'])")"
