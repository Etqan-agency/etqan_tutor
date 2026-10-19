. ./lib.sh; . ./ids.env
QQ "update account_emailaddress set verified=true where user_id in ($SA1,$SA2,$PA,$SB1,$PB,$T2,$T3)"
for x in "pa scn-parent-a" "pb scn-parent-b" "sa1 scn-a1" "sa2 scn-a2" "sb1 scn-b1" "t2 scn-teacher2" "t3 scn-teacher3"; do set -- $x; login $1 qa $2@qa.etqan.test "QA-People-2026!"; done
