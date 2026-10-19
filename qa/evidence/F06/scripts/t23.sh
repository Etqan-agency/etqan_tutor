. ./lib.sh; . ./ids.env
echo "== TC-021 bundle actions"
W=300 r adm qa POST bundles/$BM/pause/ '{"from_date":"2026-11-01","to_date":"2026-11-02"}'
Q "select count(*) from academy_qa.scheduling_subscriptionpause where subscription_id in (select id from academy_qa.scheduling_subscription where bundle_id=$BM)"
r adm qa POST bundles/$BM/renew/ '{}'
Q "select id,renewed_from_id,bundle_id,price_minor,currency from academy_qa.scheduling_subscription where renewed_from_id in (select id from academy_qa.scheduling_subscription where bundle_id=$BM and renewed_from_id is null)"
echo "== TC-022 extra: same student + same course twice"
r adm qa POST bundles/family/ "{\"family_id\":$FAM,\"starts_on\":\"2026-10-19\",\"rows\":[{\"student\":212,\"course\":$C1,\"teacher\":7,\"package\":$P1},{\"student\":212,\"course\":$C1,\"teacher\":217,\"package\":$P1}]}"
echo "== TC-023"
r adm qa POST groups/ '{"name":"QA6 Group API","student_ids":[213,216]}'; G=$(jq_ "d['id']"); echo "G=$G" >> ids.env
r adm qa POST groups/ '{"name":"QA6 Group Dup","student_ids":[213]}'
r adm qa POST bundles/group/ "{\"group_id\":$G,\"starts_on\":\"2026-10-19\",\"rows\":[{\"course\":$C1,\"teacher\":217,\"package\":$P1,\"price_minor\":100000,\"slots\":[{\"weekdays\":[2],\"start_time\":\"19:00\"}]}]}"
r adm qa POST bundles/group/ "{\"group_id\":$G,\"starts_on\":\"2026-10-19\",\"rows\":[{\"course\":$C1,\"teacher\":217,\"package\":$P1,\"slots\":[{\"weekdays\":[2],\"start_time\":\"19:00\"}]}]}"; BG=$(jq_ "d.get('id')"); echo "BG=$BG" >> ids.env
python3 -c "import json,sys;d=json.loads(sys.argv[1]);print('conflicts in create:',len(d.get('conflicts',[])) if 'conflicts' in d else 'no key')" "$RESP"
Q "select s.id,s.bundle_id,u.full_name,s.price_minor,s.currency,s.status from academy_qa.scheduling_subscription s join academy_qa.identity_studentprofile p on p.id=s.student_id join academy_qa.identity_user u on u.id=p.user_id where bundle_id=$BG order by s.id"
r adm qa POST bundles/$BG/members/ '{"student_id":214,"starts_on":"2026-10-19"}'
Q "select s.id,u.full_name,s.price_minor,s.currency,s.status,(select count(*) from academy_qa.scheduling_scheduleslot sl where sl.subscription_id=s.id) from academy_qa.scheduling_subscription s join academy_qa.identity_studentprofile p on p.id=s.student_id join academy_qa.identity_user u on u.id=p.user_id where bundle_id=$BG order by s.id"
r adm qa DELETE bundles/$BG/members/214/
Q "select s.id,u.full_name,s.status from academy_qa.scheduling_subscription s join academy_qa.identity_studentprofile p on p.id=s.student_id join academy_qa.identity_user u on u.id=p.user_id where bundle_id=$BG order by s.id"
r adm qa DELETE groups/$G/
Q "select g.id,count(m.*) from academy_qa.scheduling_studygroup g left join academy_qa.scheduling_studygroupmember m on m.group_id=g.id where g.id=$G group by 1"
