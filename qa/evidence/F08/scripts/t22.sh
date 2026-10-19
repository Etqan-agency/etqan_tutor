. ./lib.sh; . ./ids.env
mk D1 sessions/extra/ '{"student":5,"course":2,"teacher":7,"occurs_on":"2026-10-18","start_time":"23:30","minutes":30}' >/dev/null
mk D2 sessions/extra/ '{"student":5,"course":2,"teacher":7,"occurs_on":"2026-10-19","start_time":"00:10","minutes":30}' >/dev/null
mk D3 sessions/extra/ '{"student":5,"course":2,"teacher":7,"occurs_on":"2026-10-19","start_time":"23:50","minutes":30}' >/dev/null
mk D4 sessions/extra/ '{"student":5,"course":2,"teacher":7,"occurs_on":"2026-10-20","start_time":"00:10","minutes":30}' >/dev/null
DD="$D1,$D2,$D3,$D4"; Q "select id,occurs_on,starts_at,(starts_at at time zone 'Africa/Cairo')::date local_date from academy_qa.scheduling_session where id in ($DD) order by id"
has(){ jq_ "[i for i in [$DD] if i in [x['id'] for x in d.get('results',d)]]"; }
for w in today week upcoming past; do for who in adm tea stu; do api $who qa GET "sessions/?when=$w&page_size=500"; echo -n "$w/$who=$CODE $(has) cnt=$(jq_ "d['count']")  "; done; echo; done
r adm qa GET "sessions/?when=bogus"
api adm qa GET "sessions/?status=completed&kind=extra&student_attendance=present&page_size=500"; echo "combo filter ok=$(jq_ "all(x['status']=='completed' and x['kind']=='extra' and x['student_attendance']=='present' for x in d['results'])") count=$(jq_ "d['count']") db=$(Q "select count(*) from academy_qa.scheduling_session where status='completed' and kind='extra' and student_attendance='present' and archived_at is null")"
api adm qa GET "sessions/?q=QA%20student&page_size=1"; echo "q=QA student count=$(jq_ "d['count']")"
api adm qa GET "sessions/?q=Etqan%20QA%20Other&page_size=1"; echo "q other count=$(jq_ "d['count']")"
W=500 r adm qa GET schedule/today/
api tea qa GET schedule/today/; echo "teacher today: $CODE ${RESP:0:200}"
api stu qa GET schedule/today/; echo "student today: $CODE"
for id in $D1 $D2 $D3 $D4; do api adm qa DELETE sessions/$id/; echo -n "del $id=$CODE "; done; echo
