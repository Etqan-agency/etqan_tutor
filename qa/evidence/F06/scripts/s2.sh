. ./lib.sh
W=250
for n in B C; do r adm qa POST people/teachers/ "{\"user\":{\"full_name\":\"QA6 Teacher $n\",\"email\":\"qa6-teacher-$(echo $n|tr A-Z a-z)@qa.etqan.test\"},\"profile\":{}}"; done
for n in 1 2 3 4; do r adm qa POST people/students/ "{\"user\":{\"full_name\":\"QA6 Student $n\",\"email\":\"qa6-student-$n@qa.etqan.test\"},\"profile\":{\"country\":\"EG\"}}"; done
r adm qa POST people/students/ '{"user":{"full_name":"QA6 Student SA","email":"qa6-student-sa@qa.etqan.test"},"profile":{"country":"SA"}}'
Q "select id,full_name from academy_qa.identity_user where full_name like 'QA6%' order by id"
Q "select g.*, u.full_name from academy_qa.identity_guardianship g join academy_qa.identity_user u on u.id=g.student_id" 2>&1 | head
