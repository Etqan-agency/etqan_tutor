. ./lib.sh
grep -v '^\(T2\|T3\|TG\|C1\)=' ids.env > ids.tmp; mv ids.tmp ids.env
W=300 mk T2 people/teachers/ '{"user":{"full_name":"SCN Teacher Two","email":"scn-teacher2@qa.etqan.test"},"profile":{"gender":"male"}}'
W=300 mk T3 people/teachers/ '{"user":{"full_name":"SCN Payroll Teacher","email":"scn-teacher3@qa.etqan.test"},"profile":{"gender":"male"}}'
W=300 mk TG people/teachers/ '{"user":{"full_name":"SCN Teacher Gone","email":"scn-teacher-gone@qa.etqan.test"},"profile":{"gender":"female"}}'
. ./ids.env
W=500 mk C1 catalogue/courses/ "{\"name_ar\":\"scn\",\"name_en\":\"SCN Quran\",\"teacher_ids\":[$T1,$T2,$T3,$TG]}"
. ./ids.env
for t in $T2 $T3; do W=400 r adm qa POST payroll/rates/ "{\"teacher\":$t,\"hourly_rate_minor\":6000}"; done
W=1500 r adm qa GET "payroll/rates/?teacher=$T1"
cat ids.env
