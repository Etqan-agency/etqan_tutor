. ./lib.sh; . ./ids.env
proj(){ api adm qa GET payroll/payslips/projection/; j "[r['paid_so_far_minor'] for r in d['rows'] if r['teacher']['id']==$T1][0]"; }
echo "P0 $(proj)"
W=300 r adm qa PATCH sessions/$U4/ '{"pays_teacher":false}'
echo "DB pays_teacher after PATCH false: $(QQ "select pays_teacher from scheduling_session where id=$U4"|tail -1)"
echo "P1 $(proj)"
$DC exec -T django python manage.py shell -c "from django.core.cache import cache; cache.clear()" >/dev/null 2>&1
echo "P1 after cache clear $(proj)"
grep -rn "pays_teacher" "/Users/khaledsakr/Documents/Etqan tutor/etqan_tutor/backend/etqan/scheduling/api/serializers.py" | head -5
