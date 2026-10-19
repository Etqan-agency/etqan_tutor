DC=/Users/khaledsakr/.etqan-qa-tools/dc.sh
J=/private/tmp/claude-501/-Users-khaledsakr-Documents-Etqan-tutor/55afddca-abb7-4698-b08b-38df7f0acb0e/scratchpad/f05/jars; mkdir -p $J
EV="/Users/khaledsakr/Documents/Etqan tutor/etqan_tutor/qa/evidence/F05"
Q(){ PGPASSWORD=etqan psql -h localhost -p 5433 -U etqan -d etqan -tAF'|' -c "$1"; }
# api <jar> <sub> <METHOD> <path> [body]  -> RESP, CODE
api(){ local jar=$J/$1 sub=$2 m=$3 p=$4 b=${5:-}; local extra=(); [ -n "$b" ] && extra=(--data-binary "$b"); local tok=$(awk '$6=="csrftoken"{print $7}' $jar 2>/dev/null|tail -1)
 CODE=$(curl -s -o $J/.out -w '%{http_code}' -b $jar -c $jar -X $m -H 'Content-Type: application/json' -H "X-CSRFToken: $tok" -H "Referer: http://$sub.etqan.localhost/app/" "${extra[@]}" "http://$sub.etqan.localhost/api/v1/$p"); RESP=$(cat $J/.out); }
r(){ api "$@"; echo "[$CODE] $3 $4 :: ${RESP:0:${W:-300}}"; }
login(){ rm -f $J/$1; api $1 $2 GET identity/csrf/; api $1 $2 POST identity/login/ "{\"identifier\":\"$3\",\"password\":\"$4\"}"; echo "login $1 $CODE ${RESP:0:120}"; }
jq_(){ python3 -c "import sys,json;d=json.loads(sys.argv[1]);print(eval(sys.argv[2]))" "$RESP" "$1"; }
mails(){ curl -s "http://localhost:8025/api/v1/search?query=to:$1" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['messages_count'], [m['Subject'] for m in d['messages']])"; }
link(){ local id=$(curl -s "http://localhost:8025/api/v1/search?query=to:$1" | python3 -c "import sys,json;print(json.load(sys.stdin)['messages'][${2:-0}]['ID'])"); curl -s http://localhost:8025/api/v1/message/$id | python3 -c "import sys,json,re;t=json.load(sys.stdin)['Text'];print(re.findall(r'https?://\S+',t)[0])"; }
# accept <email> <jar> <password>
accept(){ local L=$(link $1); local up=$(python3 -c "import sys,urllib.parse as u;p=u.urlparse(sys.argv[1]);q=dict(u.parse_qsl(p.query or p.fragment));print(q.get('uid'),q.get('token'))" "$L"); set -- $1 $2 $3 $up; rm -f $J/anon; api anon qa GET identity/csrf/; api anon qa POST identity/password/reset/confirm/ "{\"uid\":\"$4\",\"token\":\"$5\",\"new_password\":\"$3\"}"; echo "accept $CODE ${RESP:0:120}"; login $2 qa $1 "$3"; }
