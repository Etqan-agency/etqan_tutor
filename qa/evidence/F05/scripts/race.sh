# race.sh <n> <METHOD> <path> <body-template with @N@>
. ./lib.sh; TOKV=$(awk '$6=="csrftoken"{print $7}' $J/adm|tail -1)
for i in $(seq $1); do b=${4//@N@/$i}; p=${3//@N@/$i}; ( c=$(curl -s -o $J/race.$i -w '%{http_code}' -b $J/adm -X $2 -H 'Content-Type: application/json' -H "X-CSRFToken: $TOKV" -H "Referer: http://qa.etqan.localhost/app/" --data-binary "$b" "http://qa.etqan.localhost/api/v1/$p"); echo "$i $c $(head -c 90 $J/race.$i | tr '\n' ' ')" ) & done; wait
