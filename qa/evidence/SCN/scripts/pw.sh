. ./lib.sh
api rst qa GET identity/csrf/
for e in scn-parent-a scn-parent-b scn-a1 scn-a2 scn-b1 scn-teacher2 scn-teacher3; do api rst qa POST identity/password/reset/ "{\"email\":\"$e@qa.etqan.test\"}"; echo "reset $e $CODE"; done
sleep 4
for x in "pa scn-parent-a" "pb scn-parent-b" "sa1 scn-a1" "sa2 scn-a2" "sb1 scn-b1" "t2 scn-teacher2" "t3 scn-teacher3"; do set -- $x; accept $2@qa.etqan.test $1 "QA-People-2026!"; done
