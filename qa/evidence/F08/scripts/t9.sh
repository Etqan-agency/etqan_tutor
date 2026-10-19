. ./lib.sh; . ./ids.env
F4=3; echo "F4=3" >> ids.env
T90=$(TZ=Africa/Cairo date -v+90M +%H:%M); echo "now $(TZ=Africa/Cairo date +%H:%M) F5 at $T90"
mk F5 sessions/extra/ "{\"student\":5,\"course\":1,\"teacher\":7,\"occurs_on\":\"2026-10-19\",\"start_time\":\"$T90\",\"minutes\":30}"
echo "== TC-009"
Q "select id,slot_id,occurs_on,starts_at,original_slot_id,original_on,original_starts_at,postponed_at from academy_qa.scheduling_session where id=$F4"
r stu qa POST sessions/$F4/postpone/ '{"occurs_on":"2026-11-10","start_time":"15:00"}'
r stu qa POST sessions/$F4/postpone/ '{"occurs_on":"2026-10-26","start_time":"10:00"}'
r stu qa POST sessions/$F4/postpone/ '{"occurs_on":"2026-10-27","start_time":"15:00"}'
Q "select id,slot_id,occurs_on,starts_at,original_slot_id,original_on,original_starts_at,postponed_at is not null,postponed_by_id from academy_qa.scheduling_session where id=$F4"
r stu qa POST sessions/$F5/postpone/ '{"occurs_on":"2026-10-27","start_time":"18:00"}'
W=600 r adm qa POST sessions/$F5/postpone/ '{"occurs_on":"2026-10-26","start_time":"10:00"}'
r par2 qa POST sessions/$F4/postpone/ '{"occurs_on":"2026-10-28","start_time":"16:00"}'
r par qa POST sessions/$F4/postpone/ '{"occurs_on":"2026-10-31","start_time":"15:00"}'
Q "select id,slot_id,occurs_on,starts_at,original_slot_id,original_on,original_starts_at,postponed_by_id from academy_qa.scheduling_session where id=$F4"
r tea qa POST sessions/$F4/postpone/ '{"occurs_on":"2026-10-22","start_time":"10:00"}'
Q "select id,slot_id,occurs_on,starts_at,original_slot_id,original_on,original_starts_at from academy_qa.scheduling_session where id=$F4"
DC=/Users/khaledsakr/.etqan-qa-tools/dc.sh
$DC exec -T django python manage.py tenant_command shell --schema=academy_qa -c "from etqan.scheduling import tasks; print(tasks.run_daily())" 2>&1 | tail -1
Q "select slot_id,occurs_on,count(*) from academy_qa.scheduling_session where slot_id is not null group by 1,2 having count(*)>1"
Q "select count(*) from academy_qa.scheduling_session where slot_id=2 and occurs_on='2026-10-22'"
act "$F4"
