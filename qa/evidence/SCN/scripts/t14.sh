. ./lib.sh; . ./ids.env
echo "== TC-014 fixture SCN-MONTH"
W=300 mk SUB3 subscriptions/ "{\"student\":$SA1,\"course\":$C1,\"teacher\":$T3,\"package\":$PKG,\"starts_on\":\"2026-09-01\"}"
. ./ids.env
INVS3=$(QQ "select id from billing_invoice where subscription_id=$SUB3"|tail -1); echo "INVS3=$INVS3" >> ids.env
QQ "select id,amount_minor,status,issued_on,due_on from billing_invoice where subscription_id=$SUB3"
QQ "select count(*) from scheduling_session where subscription_id=$SUB3"
i=0
for row in "02 60" "04 60" "09 60" "11 60" "16 60" "18 60" "23 45" "25 60" "28 60" "29 60" "30 60"; do set -- $row; i=$((i+1))
  W=160 mk M$i sessions/regular/ "{\"subscription\":$SUB3,\"occurs_on\":\"2026-09-$1\",\"start_time\":\"16:00\",\"minutes\":$2}"
done
. ./ids.env
mark(){ W=140 r adm qa POST sessions/$1/attendance/ "{\"student_attendance\":\"$2\",\"teacher_attendance\":\"$3\"}"; }
for k in 1 2 3 4 5 6 7; do eval mark \$M$k present present; done
mark $M8 absent present; mark $M9 excused present; mark $M10 present absent
W=200 r adm qa POST sessions/$M11/cancel/ '{"reason":"SCN M11 teacher sick"}'
echo "-- checks"
api adm qa GET "sessions/?teacher=$T3&from=2026-09-01&to=2026-09-30&page_size=100"; echo "admin filtered list [$CODE] count=$(j "d['count']") statuses=$(j "sorted(__import__('collections').Counter(s['status'] for s in d['results']).items())")"
api adm qa GET subscriptions/$SUB3/; echo "SUB3 used/remaining/extra: $(j "(d['sessions_total'],d['sessions_used'],d['sessions_remaining'],d['extra_sessions'])")"
api t3 qa GET "sessions/?page_size=100"; echo "T3 list count=$(j "d['count']") ids==M: $(j "sorted(s['id'] for s in d['results'])==sorted([$M1,$M2,$M3,$M4,$M5,$M6,$M7,$M8,$M9,$M10,$M11])")"
api t3 qa GET reports/missing/; echo "T3 missing: $(j "sorted(x['id'] for x in d['results'])")"
QQ "select status, student_attendance, teacher_attendance, minutes, count(*) from scheduling_session where subscription_id=$SUB3 group by 1,2,3,4 order by 1,2,3,4"
QQ "select count(*) from scheduling_session where subscription_id=$SUB3 and status='completed' and student_attendance='present' and teacher_attendance<>'absent' and kind in ('regular','compensation') and compensated=false"
QQ "select count(*) filter (where payroll_locked) from scheduling_session where subscription_id=$SUB3"
