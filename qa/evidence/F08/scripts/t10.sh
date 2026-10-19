. ./lib.sh; . ./ids.env
echo "== TC-009 admin conflicts body (F5 moved over teacher's 07:00Z session 1)"
api adm qa GET sessions/$F5/; echo "F5 starts_at $(jq_ "d['starts_at']")"
W=200 r adm qa POST sessions/$F5/postpone/ '{"occurs_on":"2026-10-26","start_time":"10:05"}'; jq_ "d.get('conflicts')"
echo "== TC-010"
r adm qa POST sessions/$P8/times/ '{"teacher_in_at":"2026-10-08T05:01:00Z"}'
P="{\"occurs_on\":\"2026-10-28\",\"start_time\":\"18:00\"}"
for x in "completed:$P5" "cancelled:$P7x" "at_disposal:$P9" "compensated_orig:$C2" "cancelled_compensated:$C1" "teacher_in:$P8" "expired_sub:226"; do
  n=${x%%:*}; id=${x##*:}; [ -z "$id" ] && continue
  echo -n "$n($id) "; r adm qa POST sessions/$id/postpone/ "$P"
done
echo "-- cancelled plain session"; mk K1 sessions/extra/ '{"student":5,"course":2,"teacher":7,"occurs_on":"2026-10-26","start_time":"20:00","minutes":30}'
r adm qa POST sessions/$K1/cancel/ '{"reason":"k"}'; r adm qa POST sessions/$K1/postpone/ "$P"
echo "-- archived future session (S1/TC-021 probe)"
mk K2 sessions/extra/ '{"student":5,"course":2,"teacher":7,"occurs_on":"2026-10-27","start_time":"20:00","minutes":30}'
W=400 r adm qa POST sessions/archive/ "{\"ids\":[$K2]}"
r adm qa POST sessions/$K2/postpone/ "$P"
echo "-- regular session outside term / sub B term ends 10-31"
r adm qa POST sessions/$F2/postpone/ '{"occurs_on":"2026-11-03","start_time":"10:00"}'
S "$P5,$P9,$C1,$C2,$P8,226,$K1,$K2"
