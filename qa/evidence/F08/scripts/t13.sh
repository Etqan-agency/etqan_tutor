. ./lib.sh; . ./ids.env
snap(){ for s in qa qaother; do echo -n "$s: $(Q "select count(*)||'/'||max(updated_at) from academy_$s.scheduling_session") act=$(Q "select count(*) from academy_$s.scheduling_sessionactivity") rep=$(Q "select count(*) from academy_$s.scheduling_sessionreport"); "; done; echo; }
MKJ=oth MKS=qaother mk Q1 sessions/extra/ '{"student":3,"course":1,"teacher":4,"occurs_on":"2026-10-18","start_time":"10:00","minutes":30}'
echo "Q1=$Q1"; snap
T=$P2   # qa completed session id 236, absent in qaother
AE=$(Q "select id from academy_qa.scheduling_sessionactivity where session_id=$T limit 1")
echo "-- qaother admin on its own host against qa ids ($T, activity $AE)"
o=""
for step in "GET sessions/$T/:" "POST sessions/$T/attendance/:{\"student_attendance\":\"absent\"}" "POST sessions/$T/cancel/:{\"reason\":\"x\"}" "POST sessions/$T/restore/:" "POST sessions/$T/postpone/:{\"occurs_on\":\"2026-10-28\",\"start_time\":\"10:00\"}" "PUT sessions/$T/report/:{\"behaviour\":1,\"participation\":1}" "GET sessions/$T/report/:" "GET sessions/$T/activity/:" "POST sessions/$T/activity/$AE/revert/:" "GET sessions/$T/host-link/:" "POST supervision/$T/open/:" "POST sessions/$T/times/:{\"actual_minutes\":5}" "POST sessions/$T/disposal/:{}" "POST sessions/$T/pays-teacher/:{\"pays_teacher\":false}" "PATCH sessions/$T/:{\"supervisor_attendance\":\"present\"}" "DELETE sessions/$T/:"; do
  mp=${step%%:*}; body=${step#*:}; api oth qaother ${mp%% *} "${mp#* }" "$body"; o="$o ${mp#* }=$CODE"; done; echo "$o"
W=300 r oth qaother POST sessions/bulk/ "{\"ids\":[$Q1,$T],\"action\":\"present\"}"
W=300 r oth qaother POST sessions/archive/ "{\"ids\":[$T]}"
W=200 r oth qaother POST sessions/unarchive/ "{\"ids\":[$T]}"
W=200 r oth qaother POST sessions/compensation/ "{\"compensates\":$C1,\"occurs_on\":\"2026-10-28\",\"start_time\":\"10:00\"}"
api oth qaother GET "sessions/?page_size=500"; echo "qaother list count=$(jq_ "d['count']") ids=$(jq_ "sorted(x['id'] for x in d['results'])")"
curl -s -b $J/oth "http://qaother.etqan.localhost/api/v1/sessions/?format=csv" | head -5
echo "-- cookies across hosts"
r oth qa GET sessions/$T/
r oth qa POST sessions/$T/attendance/ '{"student_attendance":"absent"}'
r adm qaother GET sessions/$Q1/
r adm qaother POST sessions/$Q1/attendance/ '{"student_attendance":"absent"}'
echo "-- qa admin on qa host with Q1's id ($Q1) resolves to qa's own row:"
Q "select id,student_id,teacher_id,occurs_on from academy_qa.scheduling_session where id=$Q1"
snap
Q "select id,status,student_attendance from academy_qaother.scheduling_session order by id"
S "$T"
