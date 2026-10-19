. ./lib.sh; . ./ids.env
F=$PWD/files; TOK(){ awk '$6=="csrftoken"{print $7}' $J/$1|tail -1; }
mp(){ local jar=$1 m=$2 p=$3; shift 3; CODE=$(curl -s -o $J/.out -w '%{http_code}' -b $J/$jar -c $J/$jar -X $m -H "X-CSRFToken: $(TOK $jar)" -H "Referer: http://qa.etqan.localhost/app/" "$@" "http://qa.etqan.localhost/api/v1/$p"); RESP=$(cat $J/.out); echo "[$CODE] $m $p :: ${RESP:0:200}"; }
$DC exec -T django python -c "import os;print('env',os.environ.get('DJANGO_PRIVATE_MEDIA_ROOT'))" 2>/dev/null; ROOT=$($DC exec -T django python manage.py shell -c "from django.conf import settings;print(settings.PRIVATE_MEDIA_ROOT)" 2>/dev/null | tail -1); echo "root=$ROOT"
FS(){ $DC exec -T django sh -c "ls $ROOT/tenants/academy_qa/employment 2>/dev/null | wc -l"; }
echo "files now: $(FS) rows: $(Q "select count(*) from academy_qa.employment_contract where file<>''")"; CUR=$(Q "select file from academy_qa.employment_contract where id=$CT"); $DC exec -T django sh -c "test -e $ROOT/$CUR && echo current-file-on-disk"
B0=$(FS); for f in evil.exe big.pdf fake.pdf; do mp adm POST contracts/ -F teacher=7 -F reference=BADX -F file=@$F/$f | cut -c1-60; done; echo "files after failed uploads $B0 -> $(FS) (orphans=$(( $(FS) - B0 )))"
LN=$(python3 -c 'print("n"*296+".pdf")'); mp adm POST contracts/ -F teacher=7 -F reference=LONG -F "file=@$F/sample.pdf;filename=$LN" | cut -c1-120; LC=$(python3 -c "import json,sys;print(json.loads(sys.argv[1]).get('id'))" "$RESP")
api adm qa GET contracts/$LC/; echo "file_name len=$(jq_ "len(d['file_name'])") ends=$(jq_ "d['file_name'][-4:]")"; mp adm DELETE contracts/$LC/ | cut -c1-20
