. ./lib.sh; . ./ids.env
TP1=$(QQ "select id from identity_teacherprofile where user_id=$T1"|tail -1)
ids=""; for pg in 1 2 3; do api tea qa GET "sessions/?page=$pg&page_size=100"; echo "page $pg [$CODE] n=$(j "len(d.get('results',[]))")"; [ "$CODE" = 200 ] || break; ids="$ids $(j "' '.join(str(s['id']) for s in d['results'])")"; done
dbids=$(QQ "select string_agg(id::text,' ' order by id) from scheduling_session where teacher_id=$TP1 and archived_at is null" | tail -1)
echo "T1 paged union equals DB: $(python3 -c "import sys;print(sorted(map(int,sys.argv[1].split()))==sorted(map(int,sys.argv[2].split())))" "$ids" "$dbids") (n=$(echo $ids | wc -w))"
