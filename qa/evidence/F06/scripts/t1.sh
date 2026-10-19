. ./lib.sh
W=400
r adm qa POST people/families/ '{"name":"QA6 Family","student_ids":[212,213],"payer_id":6}'
echo "== TC-001"
r adm qa POST catalogue/courses/ '{"name_ar":"قرآن","name_en":"QA6 Quran","language":"ar","teacher_ids":[7,217]}'; C1=$(jq_ "d['id']")
r adm qa POST catalogue/courses/ '{"name_ar":"عربي","name_en":"QA6 Arabic","language":"ar","teacher_ids":[7]}'; C2=$(jq_ "d['id']")
r adm qa POST catalogue/packages/ '{"name_ar":"ب","name_en":"QA6 Pkg 2x1m","sessions_per_week":2,"session_minutes":45,"duration_value":1,"duration_unit":"month","freeze_days_allowed":7,"price_minor":150000,"currency":"EGP"}'; P1=$(jq_ "d['id']")
r adm qa POST catalogue/packages/ '{"name_ar":"ب2","name_en":"QA6 Pkg 3x10d","sessions_per_week":3,"session_minutes":45,"duration_value":10,"duration_unit":"day","freeze_days_allowed":7,"price_minor":99999,"currency":"EGP"}'; P2=$(jq_ "d['id']")
echo "C1=$C1 C2=$C2 P1=$P1 P2=$P2" | tee ids.env
r adm qa GET catalogue/packages/$P1/; echo "sessions_total P1=$(jq_ "d.get('sessions_total')") type=$(jq_ "type(d['price_minor']).__name__")"
r adm qa GET catalogue/packages/$P2/; echo "sessions_total P2=$(jq_ "d.get('sessions_total')")"
r adm qa GET "catalogue/courses/?q=QA6"
r adm qa PATCH catalogue/packages/$P1/ '{"price_minor":160000}'
r adm qa PATCH catalogue/packages/$P1/ '{"sessions_total":99}'; echo "after sessions_total patch: $(jq_ "d.get('sessions_total')")"
Q "select id,price_minor,currency from academy_qa.catalogue_package where id=$P1"
Q "select column_name from information_schema.columns where table_schema='academy_qa' and table_name='catalogue_package' and column_name like '%total%'"
Q "select count(*) from academy_qa.catalogue_course_teachers where course_id=$C1"
r adm qa PATCH catalogue/packages/$P1/ '{"price_minor":150000}'
echo "== TC-002"
base='"name_ar":"x","name_en":"QA6 Bad","sessions_per_week":2,"session_minutes":45,"duration_value":1,"duration_unit":"month","freeze_days_allowed":7'
before=$(Q "select count(*) from academy_qa.catalogue_package")
W=160
for v in 15.5 '"1500"' -1 true null 9223372036854775808 0; do r adm qa POST catalogue/packages/ "{$base,\"price_minor\":$v,\"currency\":\"EGP\"}"; echo "   price=$v"; [ "$CODE" = 201 ] && echo "   created id $(jq_ "d['id']") price=$(jq_ "d['price_minor']")" && echo $(jq_ "d['id']") >> del.ids; done
for c in '"egp"' '"EG"' '"EGPP"' '""' '"XXX"' '"ZZZ"'; do r adm qa POST catalogue/packages/ "{$base,\"price_minor\":100,\"currency\":$c}"; echo "   currency=$c"; [ "$CODE" = 201 ] && echo "   created currency=$(jq_ "d['currency']")" && echo $(jq_ "d['id']") >> del.ids; done
b2='"name_ar":"x","name_en":"QA6 Bad","duration_unit":"month","price_minor":100,"currency":"EGP"'
for f in '"sessions_per_week":0' '"sessions_per_week":15' '"session_minutes":14' '"session_minutes":241' '"duration_value":0' '"duration_value":366' '"freeze_days_allowed":366'; do
 d='"sessions_per_week":2,"session_minutes":45,"duration_value":1,"freeze_days_allowed":7'; k=${f%%:*}; d=$(echo "$d" | sed -E "s/$k:[0-9]+/$f/"); r adm qa POST catalogue/packages/ "{$b2,$d}"; echo "   $f"; [ "$CODE" = 201 ] && echo $(jq_ "d['id']") >> del.ids; done
after=$(Q "select count(*) from academy_qa.catalogue_package"); echo "count before=$before after=$after created=$(cat del.ids 2>/dev/null|wc -l)"
docker logs --since 5m etqan_tutor-django-1 2>&1 | grep -c " 500 " 
