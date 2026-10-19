. ./lib.sh
W=200
for n in B C; do r adm qa POST people/teachers/ "{\"user\":{\"full_name\":\"QA6 Teacher $n\",\"email\":\"qa6-teacher-$(echo $n|tr A-Z a-z)@qa.etqan.test\"},\"profile\":{\"gender\":\"male\"}}"; done
r adm qa POST people/parents/6/children/ '{"student_id":212}'
r adm qa GET people/parents/6/children/
