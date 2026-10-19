. ./lib.sh; . ./ids.env
echo "== TC-010"
# FAM-B session: give SB1 an extra session
W=150 mk SB1X sessions/extra/ "{\"student\":$SB1,\"course\":$C1,\"teacher\":$T2,\"occurs_on\":\"2026-10-21\",\"start_time\":\"09:00\",\"minutes\":30}"
. ./ids.env
QPS=$(QQ "select s.id from scheduling_session s join identity_studentprofile p on p.id=s.student_id where p.user_id=5 order by s.id desc limit 1"|tail -1); echo "qa-parent child (user 5) session: $QPS"
allids(){ local ids=""; for pg in 1 2 3 4 5; do api $1 qa GET "sessions/?page=$pg&page_size=100"; [ "$CODE" = 200 ] || break; ids="$ids $(j "' '.join(str(s['id']) for s in d['results'])")"; done; echo $ids; }
for who in pa pb par sa1; do
 ids=$(allids $who)
 echo "-- $who session ids n=$(echo $ids | wc -w)"
 case $who in pa) users="$SA1,$SA2,$SA3";; pb) users="$SB1";; par) users="5";; sa1) users="$SA1";; esac
 db=$(QQ "select string_agg(s.id::text,' ') from scheduling_session s join identity_studentprofile p on p.id=s.student_id where p.user_id in ($users) and s.archived_at is null"|tail -1)
 echo "$who API==DB(students $users): $(python3 -c "import sys;print(sorted(map(int,sys.argv[1].split()))==sorted(map(int,(sys.argv[2] or '').split())))" "$ids" "$db")"
 for s in $U1 $U2 $S2X $SB1X $QPS; do api $who qa GET sessions/$s/; echo "  $who GET $s [$CODE] $( [ $CODE = 200 ] && j "(d['status'],d['student_attendance'],d['student']['full_name'])")"; done
 api $who qa GET "subscriptions/?page_size=200"; echo "  $who subs [$CODE] $(j "sorted(s['student']['full_name'] for s in d['results'])" 2>/dev/null)"
 api $who qa GET "people/students/?page_size=200"; echo "  $who students [$CODE] $(j "sorted(s['user']['full_name'] for s in d['results'])" 2>/dev/null || echo ${RESP:0:100})"
 api $who qa GET "people/families/"; echo "  $who families [$CODE] ${RESP:0:200}"
done
echo "-- PA payload keys for U1 (internal fields?)"
api pa qa GET sessions/$U1/; j "{k:d[k] for k in ('cancel_reason','marked_by','notes','meeting_host','meeting_url','has_report','supervisor','activity') if k in d}"
api adm qa GET sessions/$U1/; echo "admin keys extra vs parent: $(j "sorted(d.keys())")"
