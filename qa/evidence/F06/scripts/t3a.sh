. ./lib.sh
for i in $(cat del.ids); do api adm qa DELETE catalogue/packages/$i/; echo -n "del $i $CODE; "; done; echo
W=3000 r adm qa GET access/roles/
W=800 r adm qa GET people/staff/3/ 
