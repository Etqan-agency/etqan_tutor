. ./lib.sh
W=500 r adm qa GET "people/tags/?kind=student"
api adm qa GET "people/tags/"; python3 -c "import json,sys,collections;d=json.loads(sys.argv[1]);d=d.get('results',d);print(len(d),collections.Counter((t['kind'],t['is_active']) for t in d))" "$RESP"
for i in $(seq -w 1 60); do st=$([ $((10#$i % 5)) -eq 0 ] && echo trial || echo active); api adm qa POST people/students/ "{\"user\":{\"full_name\":\"QA5 Bulk $i\",\"phone\":\"+2010000${i}00\"},\"profile\":{\"status\":\"$st\",\"country\":\"EG\",\"date_of_birth\":\"$((2005 + 10#$i % 12))-06-15\"}}"; echo -n "$CODE "; done; echo
W=400 r adm qa POST access/roles/ '{"name_ar":"QA5 تحرير","name_en":"QA5 Student Edit","permissions":["student.view","student.view_any","student.create","student.update"]}'
W=300 r oth qaother POST people/students/ '{"user":{"full_name":"QA5 Other Student","email":"f05-other-stu@qa.etqan.test"},"profile":{}}'
Q "select count(*) from academy_qa.identity_user where full_name like 'QA5 Bulk%'"
