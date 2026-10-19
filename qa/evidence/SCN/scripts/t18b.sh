. ./lib.sh; . ./ids.env
api adm qa GET payroll/payslips/projection/; echo "T1 row: $(j "[r for r in d['rows'] if r['teacher']['id']==$T1]")"; echo "T3 row: $(j "[r for r in d['rows'] if r['teacher']['id']==$T3]")"
TP1=$(QQ "select id from identity_teacherprofile where user_id=$T1"|tail -1)
echo "-- SQL estimate of T1 October paid-so-far (completed, pays_teacher, teacher not absent, Oct Cairo dates, rate 6000/h, absent 50%, excused 25%, single-student sessions only)"
QQ "select count(*), sum(case student_attendance when 'present' then minutes*100 when 'absent' then minutes*100*5000/10000 when 'excused' then minutes*100*2500/10000 else 0 end) from scheduling_session where teacher_id=$TP1 and status='completed' and pays_teacher and teacher_attendance<>'absent' and occurs_on between '2026-10-01' and '2026-10-31' and archived_at is null"
QQ "select id,occurs_on,minutes,student_attendance,teacher_attendance,kind,pays_teacher,archived_at is not null from scheduling_session where teacher_id=$TP1 and status='completed' and occurs_on between '2026-10-01' and '2026-10-31' order by id"
QQ "select count(*) from scheduling_session where teacher_id=$TP1 and status='scheduled' and occurs_on between '2026-10-01' and '2026-10-31'"
