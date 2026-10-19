. ./lib.sh; . ./ids.env
proj(){ api adm qa GET payroll/payslips/projection/; j "[r['paid_so_far_minor'] for r in d['rows'] if r['teacher']['id']==$T1][0]"; }
echo "(PATCH pays_teacher is not a PATCH field - ignored, as DRF does; the route is POST sessions/<id>/pays-teacher/)"
P0=$(proj); echo "P0 $P0"
W=150 r adm qa POST sessions/$U4/pays-teacher/ '{"pays_teacher":false}'; P1=$(proj); echo "U4 off: $P1 delta $((P0-P1))"
W=150 r adm qa POST sessions/$U4/pays-teacher/ '{"pays_teacher":true}'; P2=$(proj); echo "U4 on: $P2"
W=150 r adm qa POST sessions/$U1/pays-teacher/ '{"pays_teacher":false}'; P3=$(proj); echo "U1 off: $P3 delta $((P2-P3))"
W=150 r adm qa POST sessions/$U1/pays-teacher/ '{"pays_teacher":true}'; P4=$(proj); echo "U1 on: $P4"
QQ "select id,pays_teacher from scheduling_session where id in ($U1,$U4)"
