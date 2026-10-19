. ./lib.sh; . ./ids.env
H1=$J1; H2=$J3; H3=$J9; H4=$J8
r adm qa POST sessions/$H4/cancel/ '{"reason":"h4"}' >/dev/null
mk H5 sessions/extra/ '{"student":5,"course":2,"teacher":36,"occurs_on":"2026-10-20","start_time":"10:00","minutes":30,"meeting_url":"https://example.test/h5"}' >/dev/null
mk H6 sessions/extra/ '{"student":5,"course":2,"teacher":7,"occurs_on":"2026-10-20","start_time":"11:00","minutes":30}' >/dev/null
Q "update academy_qa.scheduling_session set meeting_url='https://zoom.example.test/j/123', meeting_provider='zoom', meeting_ref='123' where id=$H6 returning id,meeting_provider,meeting_ref"
echo "H1..H6=$H1 $H2 $H3 $H4 $H5 $H6"
rm -f $J/anon; api anon qa GET identity/csrf/
for who in tea tea2 adm stu par sup anon; do o=""; for h in H1 H2 H3 H4 H5 H6; do id=$(eval echo \$$h); api $who qa GET sessions/$id/host-link/; o="$o $h=$CODE"; [ $CODE = 200 ] && o="$o${RESP:0:70}"; done; echo "$who:$o"; done
curl -s -D - -o /dev/null -b $J/tea http://qa.etqan.localhost/api/v1/sessions/$H1/host-link/ | grep -i "cache-control"
r tea qa GET sessions/999999/host-link/
echo "-- impersonation"
login imp qa qa-admin@qa.etqan.test 'QA-Admin-2026!' >/dev/null
r imp qa POST people/teachers/7/quick-login/
api imp qa GET identity/me/; echo "me as: $(jq_ "d.get('email')")"
r imp qa GET sessions/$H1/host-link/
r imp qa POST identity/impersonation/stop/
echo "-- start_url leakage"
for who in adm stu tea; do api $who qa GET sessions/$H6/; echo "$who H6 payload start_url? $(echo $RESP | grep -c start_url) meeting_url=$(jq_ "d.get('meeting_url')") host=$(jq_ "d.get('meeting_host')")"; done
api adm qa GET "sessions/?page_size=500"; echo "list contains start_url: $(echo "$RESP" | grep -c start_url)"
docker logs etqan_tutor-django-1 --since 30m 2>&1 | grep -c start_url
Q "select count(*) from academy_qa.scheduling_session where meeting_url ilike '%start%'"
