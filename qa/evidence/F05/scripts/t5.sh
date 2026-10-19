. ./lib.sh; . ./ids.env
api adm qa GET "people/students/?country=EG"; echo "country=EG -> $(jq_ "d['count']")"
for n in '=HYPERLINK(\"http://x\")' '+cmd' '-5 days' '@SUM(1)'; do r adm qa POST people/students/ "{\"user\":{\"full_name\":\"$n\",\"phone\":\"+201005559999\"},\"profile\":{}}" | cut -c1-60; done
curl -s -D $J/h.txt -o "$EV/students.csv" -b $J/adm "http://qa.etqan.localhost/api/v1/people/students/?format=csv"; grep -i "content-type\|disposition" $J/h.txt
head -c3 "$EV/students.csv" | xxd | head -1; head -1 "$EV/students.csv"; echo "rows=$(($(python3 -c "import csv,sys;print(sum(1 for _ in csv.reader(open(sys.argv[1],encoding='utf-8-sig'))))" "$EV/students.csv")-1))  count=$(Q "select count(*) from academy_qa.identity_user where role='student'")"
grep -E "HYPERLINK|cmd|5 days|SUM\(1" "$EV/students.csv"; grep -c "+201005559999" "$EV/students.csv"
curl -s -o $J/f.csv -b $J/adm "http://qa.etqan.localhost/api/v1/people/students/?format=csv&status=trial"; echo "filtered rows=$(($(python3 -c "import csv,sys;print(sum(1 for _ in csv.reader(open(sys.argv[1],encoding='utf-8-sig'))))" $J/f.csv)-1)) SQL=$(Q "select count(*) from academy_qa.identity_studentprofile where status='trial'")"
