. ./lib.sh; . ./bulk.env
for k in 1 2 3; do E=f05-racec$k@qa.etqan.test; echo "-- create race $k"; bash race.sh 5 POST people/students/ "{\"user\":{\"full_name\":\"QA5 RaceC @N@\",\"email\":\"$E\"},\"profile\":{}}" | awk '{print $2}' | sort | uniq -c | tr '\n' ' '; echo " rows=$(Q "select count(*) from academy_qa.identity_user where lower(email)='$E'")"; done
for k in 1 2 3; do E=f05-racep$k@qa.etqan.test; echo "-- patch race $k"; ids=($(echo $BULK | tr , ' ' | cut -d' ' -f$((43+k*2))-$((44+k*2)))); bash race.sh 2 PATCH "people/students/@N@/" "{\"user\":{\"email\":\"$E\"}}" >/dev/null 2>&1
 for i in 0 1; do (api adm qa PATCH people/students/${ids[$i]}/ "{\"user\":{\"email\":\"$E\"}}"; echo -n "$CODE ") & done; wait; echo " rows=$(Q "select count(*) from academy_qa.identity_user where lower(email)='$E'")"; done
$DC logs --since 5m django 2>&1 | grep -B2 -A2 "IntegrityError" | grep -v "^\s*$" | tail -12
