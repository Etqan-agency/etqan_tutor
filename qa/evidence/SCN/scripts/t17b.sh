. ./lib.sh; . ./ids.env
QQ "select id,type,recipient_id,email_status,dedupe_key,language,created_at from notifications_notification where type='session.student_absent' and target_id='$AB1' order by id"
QQ "select dedupe_key,recipient_id,count(*) from notifications_notification where type='session.student_absent' group by 1,2 having count(*)>1"
echo "-- Mailpit message for PA"
ID=$(curl -s "http://localhost:8025/api/v1/search?query=to:scn-parent-a@qa.etqan.test" | python3 -c "import sys,json;m=json.load(sys.stdin)['messages'][0];print(m['ID'])"); echo "mailpit id $ID"
curl -s http://localhost:8025/api/v1/message/$ID | python3 -c "
import sys,json,re;m=json.load(sys.stdin);t=m['Text'];print('Subject:',m['Subject']);print('To:',[a['Address'] for a in m['To']]);print('links:',re.findall(r'https?://\S+',t)[:3]);print('raw {{ :', '{{' in t or '{{' in m.get('HTML',''));print(t[:300])"
echo "-- edge: PA mutes sessions category"
W=600 r pa qa GET notifications/preferences/
