. ./lib.sh; . ./ids.env
echo "== TC-006 (P8 on Sub B)"
echo "remB0 $(rem $B)"
r tea qa POST sessions/$P8/attendance/ '{"student_attendance":"present"}'
r tea qa POST sessions/$P8/attendance/ '{"student_attendance":"present"}'
act "$P8"; echo "remB after 2 identical $(rem $B)"
tok=$(awk '$6=="csrftoken"{print $7}' $J/tea|tail -1)
for v in present absent present absent present; do
 curl -s -o $J/race_$v_$RANDOM -w "%{http_code}\n" -b $J/tea -X POST -H 'Content-Type: application/json' -H "X-CSRFToken: $tok" -H "Referer: http://qa.etqan.localhost/app/" --data-binary "{\"student_attendance\":\"$v\"}" http://qa.etqan.localhost/api/v1/sessions/$P8/attendance/ &
done; wait
S "$P8"; act "$P8"; echo "remB after race $(rem $B)"
r tea qa POST sessions/$P8/attendance/ '{"student_attendance":"not_set"}'
r adm qa POST sessions/$P8/attendance/ '{"student_attendance":"present"}'
r adm qa POST sessions/$P8/attendance/ '{"student_attendance":"not_set"}'
S "$P8"; echo "remB end $(rem $B)"
docker logs etqan_tutor-django-1 --since 3m 2>&1 | grep -c " 500 \|Traceback"
echo "== TC-007 (P9, F2)"
DC=/Users/khaledsakr/.etqan-qa-tools/dc.sh
$DC exec -T django python manage.py set_features qa --off disposal_status 2>&1 | tail -1
r adm qa POST sessions/$P9/disposal/ '{"reason":"no teacher"}'
$DC exec -T django python manage.py set_features qa --on disposal_status 2>&1 | tail -1
echo "remB0 $(rem $B)"
r adm qa POST sessions/$P9/disposal/ '{"reason":"no teacher"}'
r adm qa POST sessions/$P9/attendance/ '{"student_attendance":"present"}'
r tea qa POST sessions/$P9/attendance/ '{"teacher_attendance":"present"}'
S "$P9"; echo "remB $(rem $B)"
r adm qa POST sessions/$P9/restore/
Q "select status,disposal_reason,teacher_attendance from academy_qa.scheduling_session where id=$P9"
r adm qa POST sessions/$P7/disposal/ '{"reason":"on completed"}'
r adm qa POST sessions/$F2/disposal/ '{"reason":"future no teacher"}'
r adm qa POST sessions/$F2/cancel/ '{"reason":"cancel at disposal"}'
Q "select status,disposal_reason,cancel_reason from academy_qa.scheduling_session where id=$F2"
r adm qa POST sessions/$F2/restore/
r adm qa POST sessions/$P9/disposal/ '{"reason":"again"}'
echo "remB $(rem $B)"
$DC exec -T django python manage.py tenant_command shell --schema=academy_qa -c "from etqan.scheduling import tasks; import inspect; print([n for n in dir(tasks) if not n.startswith('_')])" 2>&1 | tail -1
