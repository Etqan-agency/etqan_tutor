. ./lib.sh; . ./ids.env
W=300 r pa qa PATCH notifications/preferences/ '{"categories":[{"category":"sessions","enabled":false}]}'
ST=$(TZ=Africa/Cairo date -v-45M +%H:%M)
W=150 mk AB2 sessions/extra/ "{\"student\":$SA2,\"course\":$C1,\"teacher\":$T1,\"occurs_on\":\"2026-10-19\",\"start_time\":\"$ST\",\"minutes\":30}"
. ./ids.env
W=150 r adm qa POST sessions/$AB2/attendance/ '{"student_attendance":"absent"}'
$DC exec -T django python manage.py scan_notifications 2>&1 | tail -1
sleep 8
QQ "select id,recipient_id,email_status from notifications_notification where type='session.student_absent' and target_id='$AB2'"
echo "PA mails: $(mails scn-parent-a@qa.etqan.test | cut -c1-5)"
W=300 r pa qa PATCH notifications/preferences/ '{"categories":[{"category":"sessions","enabled":true}]}'
