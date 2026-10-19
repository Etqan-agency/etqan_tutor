. ./lib.sh; . ./ids.env
TP1=$(QQ "select id from identity_teacherprofile where user_id=$T1"|tail -1)
api tea qa GET "sessions/?page_size=1000"; echo "T1 results len=$(j "len(d['results'])") next=$(j "d.get('next')")"
ids=""; p="sessions/?page_size=1000"; all=()
python3 - "$J/tea" "$TP1" <<'PY' > /dev/null
PY
for pg in 1 2 3 4; do api tea qa GET "sessions/?page=$pg"; [ "$CODE" = 200 ] || break; ids="$ids $(j "' '.join(str(s['id']) for s in d['results'])")"; done
dbids=$(QQ "select string_agg(id::text,' ' order by id) from scheduling_session where teacher_id=$TP1 and archived_at is null" | tail -1)
echo "T1 paged union equals DB: $(python3 -c "import sys;print(sorted(map(int,sys.argv[1].split()))==sorted(map(int,sys.argv[2].split())))" "$ids" "$dbids") (n=$(echo $ids | wc -w))"
echo "SA2-owned ids in T1 union: $(python3 -c "import sys;a=set(map(int,sys.argv[1].split()));b=set(map(int,sys.argv[2].split() or []));print(sorted(a&b))" "$ids" "$(QQ "select string_agg(id::text,' ') from scheduling_session where student_id=(select id from identity_studentprofile where user_id=$SA2)"|tail -1)")"
echo "== TC-007 data (today, before now): U1..U3"
for n in 1 2 3; do W=200 mk U$n sessions/regular/ "{\"subscription\":$SUB1,\"occurs_on\":\"2026-10-19\",\"start_time\":\"1$((n-1)):00\"}"; done
. ./ids.env; echo "U1=$U1 U2=$U2 U3=$U3 U4=$U4"
S "$U1,$U2,$U3,$U4"
