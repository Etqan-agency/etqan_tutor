. ./lib.sh; . ./ids.env
DC=/Users/khaledsakr/.etqan-qa-tools/dc.sh
echo "== TC-007 daily job"
$DC exec -T django python manage.py tenant_command shell --schema=academy_qa -c "from etqan.scheduling import tasks; print(tasks.run_daily.__doc__); print(tasks.run_daily())" 2>&1 | tail -3
S "$P9"
echo "== TC-008"
echo "remB0 $(rem $B)"
r adm qa POST sessions/$C1/cancel/ '{"reason":"student travel"}'
r adm qa POST sessions/$C2/attendance/ '{"student_attendance":"excused"}'
echo "remB pre $(rem $B)"
W=400 mk M1 sessions/compensation/ "{\"compensates\":$C1,\"occurs_on\":\"2026-10-23\",\"start_time\":\"10:00\"}"
r adm qa POST sessions/compensation/ "{\"compensates\":$C1,\"occurs_on\":\"2026-10-24\",\"start_time\":\"10:00\"}"
mk M2 sessions/compensation/ "{\"compensates\":$C2,\"occurs_on\":\"2026-10-24\",\"start_time\":\"11:00\"}"
r adm qa POST sessions/compensation/ "{\"compensates\":$X1,\"occurs_on\":\"2026-10-24\",\"start_time\":\"12:00\"}"
r adm qa POST sessions/compensation/ "{\"compensates\":$F1,\"occurs_on\":\"2026-10-24\",\"start_time\":\"13:00\"}"
r adm qa POST sessions/compensation/ "{\"compensates\":$P5,\"occurs_on\":\"2026-10-24\",\"start_time\":\"14:00\"}"
S "$C1,$C2,$M1,$M2"; echo "remB after make-ups $(rem $B)"
r adm qa POST sessions/$C1/attendance/ '{"student_attendance":"present"}'
r adm qa POST sessions/$C1/restore/
r adm qa POST sessions/$C2/cancel/ '{"reason":"x"}'
r adm qa POST sessions/$C2/disposal/ '{"reason":"x"}'
r adm qa POST sessions/$C2/attendance/ '{"student_attendance":"present"}'
r adm qa POST sessions/$M1/cancel/ '{"reason":"makeup cancelled"}'
S "$C1,$M1"
W=300 mk M3 sessions/compensation/ "{\"compensates\":$C1,\"occurs_on\":\"2026-10-25\",\"start_time\":\"10:00\"}"
r adm qa POST sessions/$M1/restore/
S "$C1,$M1,$M3"; echo "remB $(rem $B)"
Q "select compensates_id,count(*) from academy_qa.scheduling_session where compensates_id is not null and status<>'cancelled' group by 1 having count(*)>1"
Q "select count(*) from academy_qa.scheduling_session where compensates_id is not null and kind<>'compensation'"
Q "select id,compensated,compensated_by from academy_qa.scheduling_session where id in ($C1,$C2)"
Q "select pg_get_constraintdef(oid), conname from pg_constraint where conrelid='academy_qa.scheduling_session'::regclass and contype='c' and pg_get_constraintdef(oid) like '%compensat%'"
Q "select indexdef from pg_indexes where schemaname='academy_qa' and tablename='scheduling_session' and indexdef like '%compensates%'"
