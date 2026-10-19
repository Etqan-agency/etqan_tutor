. ./lib.sh; . ./ids.env
echo "== TC-007 (after UI: U1 present by T1)"
S "$U1"; rem $SUB1
W=200 r tea qa POST sessions/$U2/attendance/ '{"student_attendance":"absent"}'
W=200 r tea qa POST sessions/$U3/attendance/ '{"student_attendance":"excused"}'
W=200 r tea qa POST sessions/$U4/attendance/ '{"student_attendance":"present","teacher_attendance":"present"}'
FUT=$(QQ "select id from scheduling_session where subscription_id=$SUB1 and starts_at>now() order by starts_at limit 1"|tail -1)
W=200 r tea qa POST sessions/$FUT/attendance/ '{"student_attendance":"present"}'
W=200 r tea qa POST sessions/$U2/attendance/ '{"student_attendance":"late"}'
W=200 r tea qa POST sessions/$S2X/attendance/ '{"student_attendance":"present"}'
api adm qa GET subscriptions/$SUB1/; echo "SUB1 used/remaining/extra: $(j "(d['sessions_used'],d['sessions_remaining'],d['extra_sessions'])")"
QQ "select id,status,student_attendance,teacher_attendance,kind,marked_by_id,marked_at is not null from scheduling_session where id in ($U1,$U2,$U3,$U4) order by id"
QQ "select session_id,actor_id,action from scheduling_sessionactivity where session_id in ($U1,$U2,$U3,$U4) and action='attendance' order by id"
QQ "select count(*) from scheduling_session where subscription_id=$SUB1 and status='completed' and student_attendance='present' and teacher_attendance<>'absent' and kind in ('regular','compensation') and compensated=false"
QQ "select id from identity_user where id=$T1"
