. ./lib.sh; . ./ids.env
echo "== TC-004"
W=200 mk SA3 people/students/ '{"user":{"full_name":"SCN Student A3","email":"scn-a3@qa.etqan.test"},"profile":{"country":"EG","gender":"male"}}'
. ./ids.env
W=400 r adm qa PATCH people/families/$FA/ "{\"student_ids\":[$SA1,$SA2,$SA3]}"
QQ "select count(*) from scheduling_session where subscription_id=$SUB1"; S0=$(QQ "select md5(string_agg(id||starts_at::text||status,',' order by id)) from scheduling_session where subscription_id=$SUB1" | tail -1)
api adm qa POST subscriptions/ "{\"student\":$SA3,\"course\":$C1,\"teacher\":$T1,\"package\":$PKG,\"starts_on\":\"2026-10-19\",\"slots\":[{\"weekdays\":[0],\"start_time\":\"18:00\"}]}"
echo "[$CODE] SA3 sub; conflicts: $(j "[(c['session']['id'],c['session']['occurs_on'],[x.get('id') for x in c.get('with',c.get('conflicts',[]))] if isinstance(c.get('with',c.get('conflicts')),list) else list(c.keys())) for c in d.get('conflicts',[])]")"
SUB_A3=$(j "d['id']"); echo "SUB_A3=$SUB_A3" >> ids.env
echo "conflict entry sample: $(j "d['conflicts'][0] if d.get('conflicts') else None" | cut -c1-700)"
W=500 r adm qa POST schedule/generate/ "{\"from\":\"2026-10-19\",\"to\":\"2026-11-30\",\"subscription\":$SUB_A3}"
echo "-- deactivate Teacher Gone"
W=300 r adm qa POST people/teachers/$TG/deactivate/
W=300 r adm qa POST subscriptions/ "{\"student\":$SA3,\"course\":$C1,\"teacher\":$TG,\"package\":$PKG,\"starts_on\":\"2026-10-20\"}"
QQ "select count(*) from billing_invoice where subscription_id is not null and student_id=(select id from identity_studentprofile where user_id=$SA3)"
S1=$(QQ "select md5(string_agg(id||starts_at::text||status,',' order by id)) from scheduling_session where subscription_id=$SUB1" | tail -1); echo "SUB1 unchanged: $([ "$S0" = "$S1" ] && echo yes || echo NO)"
echo "-- overlap SQL (T1, non-cancelled)"
QQ "select a.id,b.id,a.subscription_id,b.subscription_id,a.starts_at from scheduling_session a join scheduling_session b on a.teacher_id=b.teacher_id and a.id<b.id and a.status<>'cancelled' and b.status<>'cancelled' and tstzrange(a.starts_at,a.starts_at+a.minutes*interval '1 minute') && tstzrange(b.starts_at,b.starts_at+b.minutes*interval '1 minute') where a.teacher_id=(select id from identity_teacherprofile where user_id=$T1) and (a.subscription_id in ($SUB1,$SUB_A3) or b.subscription_id in ($SUB1,$SUB_A3)) order by 1"
echo "-- cancel SA3 sub"
W=400 r adm qa POST subscriptions/$SUB_A3/cancel/ '{"reason":"SCN cleanup"}'
QQ "select id,status,amount_minor,voided_at from billing_invoice where subscription_id=$SUB_A3"
QQ "select status,count(*) from scheduling_session where subscription_id=$SUB_A3 group by 1"
