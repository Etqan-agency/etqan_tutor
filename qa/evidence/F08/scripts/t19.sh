. ./lib.sh; . ./ids.env
echo "== S7 probe: own teacher host-link on ended / completed sessions"
r tea qa GET sessions/$V4/host-link/
api adm qa POST sessions/$V3/attendance/ '{"student_attendance":"present"}'; r tea qa GET sessions/$V3/host-link/
echo "== TC-019"
mk B1 sessions/extra/ '{"student":5,"course":2,"teacher":7,"occurs_on":"2026-10-10","start_time":"21:30","minutes":30}' >/dev/null
mk B2 sessions/extra/ '{"student":5,"course":2,"teacher":7,"occurs_on":"2026-10-11","start_time":"21:30","minutes":30}' >/dev/null
N0=$(Q "select count(*) from academy_qa.scheduling_sessionactivity")
W=600 r adm qa POST sessions/bulk/ "{\"ids\":[$B1,$F1,$K1,$P6,999999,$B2,$B1],\"action\":\"present\"}"
echo "activity delta=$(( $(Q "select count(*) from academy_qa.scheduling_sessionactivity") - N0 ))"
r adm qa POST sessions/bulk/ "{\"ids\":[$B1],\"action\":\"cancel\"}"
r adm qa POST sessions/bulk/ "{\"ids\":[$B1],\"action\":\"cancel\",\"reason\":\"  \"}"
r adm qa POST sessions/bulk/ "{\"ids\":[$B1],\"action\":\"late\"}"
r adm qa POST sessions/bulk/ '{"ids":[],"action":"present"}'
ids201=$(python3 -c "print(list(range(1,202)))"); r adm qa POST sessions/bulk/ "{\"ids\":$ids201,\"action\":\"present\"}"
r tea qa POST sessions/bulk/ "{\"ids\":[$B1],\"action\":\"present\"}"
mk B3 sessions/extra/ '{"student":5,"course":2,"teacher":7,"occurs_on":"2026-10-12","start_time":"21:30","minutes":30}' >/dev/null
mk B4 sessions/extra/ '{"student":5,"course":2,"teacher":7,"occurs_on":"2026-10-13","start_time":"21:30","minutes":30}' >/dev/null
tok=$(awk '$6=="csrftoken"{print $7}' $J/adm|tail -1)
for o in "[$B3,$B4]" "[$B4,$B3]"; do curl -s -w " %{http_code}\n" -b $J/adm -X POST -H 'Content-Type: application/json' -H "X-CSRFToken: $tok" -H "Referer: http://qa.etqan.localhost/app/" --data-binary "{\"ids\":$o,\"action\":\"cancel\",\"reason\":\"race\"}" http://qa.etqan.localhost/api/v1/sessions/bulk/ & done; wait
r adm qa POST sessions/bulk/ "{\"ids\":[$B1,$B2],\"action\":\"cancel\",\"reason\":\"bulk c\"}"
S "$B1,$B2,$B3,$B4,$F1,$K1,$P6"
