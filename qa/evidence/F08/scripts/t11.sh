. ./lib.sh; . ./ids.env
rm -f $J/anon; api anon qa GET identity/csrf/
echo "DB totals: all=$(Q "select count(*) from academy_qa.scheduling_session where archived_at is null") teacher1=$(Q "select count(*) from academy_qa.scheduling_session where teacher_id=1 and archived_at is null") student1=$(Q "select count(*) from academy_qa.scheduling_session where student_id=1 and archived_at is null")"
for who in adm codes nocode sup tea stu par anon; do
  api $who qa GET "sessions/?page_size=1"; l=$CODE; cnt=$( [ $CODE = 200 ] && jq_ "d['count']" )
  api $who qa GET sessions/$P5/; d1=$CODE; keys=$( [ $CODE = 200 ] && jq_ "','.join(k for k in ['cancel_reason','notes','has_report','payroll_locked','pays_teacher','created_by','disposal_reason','supervisor','meeting_host','postponed_by','compensated'] if k in d)" )
  api $who qa GET sessions/$FO/; d2=$CODE
  curl -s -o $J/csv -w '' -b $J/$who "http://qa.etqan.localhost/api/v1/sessions/?format=csv"; c1=$(curl -s -o $J/csv -w '%{http_code}' -b $J/$who -H 'Accept: text/csv' "http://qa.etqan.localhost/api/v1/sessions/?export=csv"); 
  c2=$(curl -s -o $J/csv2 -w '%{http_code}' -b $J/$who "http://qa.etqan.localhost/api/v1/sessions/?format=csv"); rows=$(wc -l < $J/csv2)
  api $who qa GET sessions/$P5/activity/; a=$CODE
  api $who qa GET reports/missing/; m=$CODE
  echo "$who: list=$l count=$cnt own=$d1 foreign=$d2 csvAccept=$c1 csvFormat=$c2(lines $rows) activity=$a missing=$m | keys: $keys"
done
head -c 300 $J/csv2; echo
