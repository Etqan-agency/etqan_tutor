. ./lib.sh; . ./ids.env
echo "partial rows after 500s: users named QA5 RaceC=$(Q "select count(*) from academy_qa.identity_user where full_name like 'QA5 RaceC%'") profiles=$(Q "select count(*) from academy_qa.identity_studentprofile p join academy_qa.identity_user u on u.id=p.user_id where u.full_name like 'QA5 RaceC%'") emailaddr=$(Q "select count(*) from academy_qa.account_emailaddress where email like 'f05-racec%'")"
sleep 2; for k in 1 2 3; do mails f05-racec$k@qa.etqan.test; done
echo "-- last-admin race: A1 vs A2 deactivate each other, 10 rounds"
r adm qa POST people/admins/$A2/activate/ | cut -c1-12; login a2 qa f05-adm2@qa.etqan.test 'QA-Adm2-2026!' | cut -c1-12
for n in $(seq 10); do
 ( api adm qa POST people/admins/$A2/deactivate/; echo -n "a1->a2:$CODE " ) & ( api a2 qa POST people/admins/1/deactivate/; echo -n "a2->a1:$CODE " ) & wait
 act=$(Q "select count(*) from academy_qa.identity_user where role='admin' and is_active"); echo " active=$act"
 [ "$act" = 0 ] && { echo "INVARIANT BROKEN"; break; }
 # restore: whoever is active reactivates the other, then both re-login
 Q "select is_active from academy_qa.identity_user where id=1" | grep -q t && { login adm qa qa-admin@qa.etqan.test 'QA-Admin-2026!' >/dev/null; api adm qa POST people/admins/$A2/activate/; } || { login a2 qa f05-adm2@qa.etqan.test 'QA-Adm2-2026!' >/dev/null; api a2 qa POST people/admins/1/activate/; }
 login adm qa qa-admin@qa.etqan.test 'QA-Admin-2026!' >/dev/null; login a2 qa f05-adm2@qa.etqan.test 'QA-Adm2-2026!' >/dev/null
done
api adm qa POST people/admins/$A2/deactivate/; echo "final: A2 deactivated $CODE; active admins=$(Q "select count(*) from academy_qa.identity_user where role='admin' and is_active")"
