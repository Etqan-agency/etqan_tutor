. ./lib.sh; . ./ids.env
allids(){ local ids=""; for pg in 1 2 3 4 5; do api $1 qa GET "sessions/?page=$pg&page_size=100"; [ "$CODE" = 200 ] || break; ids="$ids $(j "' '.join(str(s['id']) for s in d['results'])")"; done; echo $ids; }
for who in "pa 224" "par 6"; do set -- $who
 ids=$(allids $1)
 db=$(QQ "select string_agg(s.id::text,' ') from scheduling_session s where s.archived_at is null and s.student_id in (select g.student_id from identity_guardianship g join identity_parentprofile pp on pp.id=g.parent_id where pp.user_id=$2)"|tail -1)
 echo "$1 API==DB(guardianship children): $(python3 -c "import sys;a=set(map(int,sys.argv[1].split()));b=set(map(int,(sys.argv[2] or '').split()));print(a==b,'api-db',sorted(a-b),'db-api',sorted(b-a))" "$ids" "$db")"
done
QQ "select s.id,s.status,s.archived_at,p.user_id from scheduling_session s join identity_studentprofile p on p.id=s.student_id where p.user_id=$SA3"
