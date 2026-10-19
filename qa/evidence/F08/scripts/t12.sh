. ./lib.sh; . ./ids.env
rm -f $J/anon; api anon qa GET identity/csrf/
d=1
for who in adm codes nocode sup tea stu par anon; do
  d=$((d+1)); day=$(printf "2026-10-%02d" $((d)))
  MKJ=adm mk W_$who sessions/extra/ "{\"student\":5,\"course\":2,\"teacher\":7,\"occurs_on\":\"$day\",\"start_time\":\"21:00\",\"minutes\":30}" >/dev/null
  MKJ=adm mk W2_$who sessions/extra/ "{\"student\":5,\"course\":2,\"teacher\":36,\"occurs_on\":\"$day\",\"start_time\":\"22:00\",\"minutes\":30}" >/dev/null
  s=$(eval echo \$W_$who); s2=$(eval echo \$W2_$who); o=""
  for step in "disp:POST sessions/$s/disposal/:{\"reason\":\"p\"}" "rest:POST sessions/$s/restore/:" "pays:POST sessions/$s/pays-teacher/:{\"pays_teacher\":false}" "times:POST sessions/$s/times/:{\"teacher_in_at\":\"${day}T18:01:00Z\"}" \
     "att:POST sessions/$s/attendance/:{\"student_attendance\":\"present\"}" "attS2:POST sessions/$s2/attendance/:{\"student_attendance\":\"present\"}" "rep:PUT sessions/$s/report/:{\"behaviour\":4,\"participation\":4}" \
     "bulk:POST sessions/bulk/:{\"ids\":[$s],\"action\":\"present\"}" "cancel:POST sessions/$s/cancel/:{\"reason\":\"p\"}" "arch:POST sessions/archive/:{\"ids\":[$s2]}" "del:DELETE sessions/$s2/:" \
     "extra:POST sessions/extra/:{\"student\":5,\"course\":2,\"teacher\":7,\"occurs_on\":\"2026-10-30\",\"start_time\":\"23:00\",\"minutes\":15}"; do
    n=${step%%:*}; rest=${step#*:}; mp=${rest%%:*}; body=${rest#*:}; m=${mp%% *}; p=${mp#* }
    api $who qa $m "$p" "$body"; extra=""; [ $n = bulk ] && extra="$(echo $RESP | head -c 80)"; [ $n = arch ] && extra="$(echo $RESP | head -c 80)"
    [ $n = extra ] && [ $CODE = 201 ] && { nid=$(jq_ "d['session']['id']"); api adm qa DELETE sessions/$nid/; extra="(deleted $nid: $CODE)"; }
    o="$o $n=$CODE$extra"
  done
  echo "$who S=$s S2=$s2:$o"
  Q "select id,status,student_attendance,teacher_in_at is not null tin,pays_teacher,marked_by_id,archived_at is not null from academy_qa.scheduling_session where id in ($s,$s2) order by id" | tr '\n' ' '; echo
done
