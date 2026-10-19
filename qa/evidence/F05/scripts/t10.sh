. ./lib.sh; . ./ids.env
rm -f $J/anon; api anon qa GET identity/csrf/
for j in nocode codes sup tch stu par; do e=$(Q "select email from academy_qa.identity_user where email like 'qa-%${j/nocode/staff-nocode}%' limit 1"); done
login codes qa qa-staff-codes@qa.etqan.test 'QA-People-2026!' >/dev/null; login sup qa qa-supervisor@qa.etqan.test 'QA-People-2026!' >/dev/null; login nocode qa qa-staff-nocode@qa.etqan.test 'QA-People-2026!' >/dev/null
login stu qa qa-student@qa.etqan.test 'QA-People-2026!' >/dev/null; login par qa qa-parent@qa.etqan.test 'QA-People-2026!' >/dev/null
api sup qa GET identity/me/; echo "sup perms: $(jq_ "sorted(d['permissions'])")"; api codes qa GET identity/me/; echo "codes perms: $(jq_ "sorted(d['permissions'])")"
C0=$(Q "select (select count(*) from academy_qa.identity_user)||'/'||(select count(*) from academy_qa.identity_tag)||'/'||(select count(*) from academy_qa.identity_family)")
printf "%-7s" jar; for c in Ls Ds Cs Us Act Bulk Lt Lp La Ltag Ctag Lf Csv Me; do printf "%5s" $c; done; echo
for j in adm nocode codes sup tch stu par anon; do printf "%-7s" $j
 api $j qa GET people/students/; printf "%5s" $CODE; L403="$L403$([ $CODE = 403 ] && echo "$RESP" | grep -c '@' )"
 api $j qa GET people/students/$K2/; printf "%5s" $CODE
 api $j qa POST people/students/ "{\"user\":{\"full_name\":\"QA5 Perm $j\"},\"profile\":{}}"; printf "%5s" $CODE
 api $j qa PATCH people/students/$K2/ '{"user":{"phone":"+201005550777"}}'; printf "%5s" $CODE
 api $j qa POST people/students/$K2/activate/; printf "%5s" $CODE
 api $j qa POST people/students/bulk/ "{\"ids\":[$K2],\"action\":\"set_status\",\"status\":\"active\"}"; printf "%5s" $CODE
 api $j qa GET people/teachers/; printf "%5s" $CODE; api $j qa GET people/parents/; printf "%5s" $CODE; api $j qa GET people/admins/; printf "%5s" $CODE
 api $j qa GET people/tags/; printf "%5s" $CODE; api $j qa POST people/tags/ "{\"kind\":\"student\",\"name_en\":\"QA5 Perm $j\",\"name_ar\":\"ب $j\"}"; printf "%5s" $CODE
 api $j qa GET people/families/; printf "%5s" $CODE; api $j qa GET "people/students/?format=csv"; printf "%5s" $CODE; api $j qa GET identity/me/; printf "%5s" $CODE; echo
done
echo "counts users/tags/families before $C0 after $(Q "select (select count(*) from academy_qa.identity_user)||'/'||(select count(*) from academy_qa.identity_tag)||'/'||(select count(*) from academy_qa.identity_family)") (adm creates 1 user + 1 tag)"
echo "--- 403 bodies with person data (should be empty):"
for j in nocode tch stu par anon; do for p in people/students/ people/students/$K2/ people/teachers/ people/families/ "people/students/?format=csv"; do api $j qa GET "$p"; [ $CODE != 200 ] && echo "$RESP" | grep -l "full_name\|@qa" >/dev/null && echo "LEAK $j $p"; done; done; echo done
echo "--- 404 vs 403 for nonexistent id (non-office):"; for j in tch stu nocode; do api $j qa GET people/students/999999/; a=$CODE; api $j qa GET people/students/$K2/; echo "$j nonexist=$a exist=$CODE"; done
echo "--- 5xx sweep:"; grep -c " 5[0-9][0-9]" /dev/null
