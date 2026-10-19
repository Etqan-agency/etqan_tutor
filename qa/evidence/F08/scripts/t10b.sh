. ./lib.sh; . ./ids.env
W=300 r adm qa POST subscriptions/$B/pauses/ '{"from_date":"2026-10-29","to_date":"2026-10-29","reason":"F08 TC-010"}'
PZ=$(jq_ "d.get('id') or d.get('pause',{}).get('id')"); echo "pause $PZ"
r adm qa POST sessions/$F2/postpone/ '{"occurs_on":"2026-10-29","start_time":"10:00"}'
r adm qa DELETE pauses/$PZ/
r adm qa POST sessions/$F2/postpone/ '{"occurs_on":"2026-10-22","start_time":"08:00"}'
