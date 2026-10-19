. ./lib.sh; . ./ids.env
echo "== TC-017"
api adm qa GET notifications/settings/; echo "[$CODE] student_absent setting: $(j "[x for x in (d['results'] if isinstance(d,dict) and 'results' in d else d) if 'absent' in str(x.get('type',x.get('code','')))]" 2>/dev/null || echo ${RESP:0:400})"
N0=$(QQ "select count(*) from notifications_notification where type='session.student_absent'"|tail -1)
M0=$(curl -s "http://localhost:8025/api/v1/search?query=to:scn-parent-a@qa.etqan.test" | python3 -c "import sys,json;print(json.load(sys.stdin)['messages_count'])")
echo "absent notifs before $N0, PA mails before $M0"
ST=$(TZ=Africa/Cairo date -v-60M +%H:%M)
W=200 mk AB1 sessions/extra/ "{\"student\":$SA2,\"course\":$C1,\"teacher\":$T1,\"occurs_on\":\"2026-10-19\",\"start_time\":\"$ST\",\"minutes\":30}"
. ./ids.env
W=200 r adm qa POST sessions/$AB1/attendance/ '{"student_attendance":"absent"}'
$DC exec -T django python manage.py scan_notifications 2>&1 | tail -2
$DC exec -T django python manage.py scan_notifications 2>&1 | tail -2
for i in $(seq 1 12); do c=$(curl -s "http://localhost:8025/api/v1/search?query=to:scn-parent-a@qa.etqan.test" | python3 -c "import sys,json;print(json.load(sys.stdin)['messages_count'])"); [ "$c" -gt "$M0" ] && break; sleep 5; done
echo "PA mails now $c"
QQ "select id,type,user_id,email_status,dedupe_key,created_at from notifications_notification where type='session.student_absent' order by id desc limit 6"
api pa qa GET notifications/; echo "PA notifs: $(j "[(n.get('type'),n.get('title','')[:60]) for n in (d['results'] if isinstance(d,dict) else d)][:5]")"
W=200 r pa qa GET notifications/unread-count/
api pb qa GET notifications/; echo "PB absent notifs: $(j "[n for n in (d['results'] if isinstance(d,dict) else d) if n.get('type')=='session.student_absent']")"
api par qa GET notifications/; echo "qa-parent absent notifs for SA2: $(j "[n.get('id') for n in (d['results'] if isinstance(d,dict) else d) if n.get('type')=='session.student_absent' and 'A2' in json.dumps(n)]" 2>/dev/null)"
