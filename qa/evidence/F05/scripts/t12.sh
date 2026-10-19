. ./lib.sh; . ./ids.env
F=$PWD/files; TOK(){ awk '$6=="csrftoken"{print $7}' $J/$1|tail -1; }
mp(){ local jar=$1 m=$2 p=$3; shift 3; CODE=$(curl -s -o $J/.out -w '%{http_code}' -b $J/$jar -c $J/$jar -X $m -H "X-CSRFToken: $(TOK $jar)" -H "Referer: http://qa.etqan.localhost/app/" "$@" "http://qa.etqan.localhost/api/v1/$p"); RESP=$(cat $J/.out); echo "[$CODE] $m $p :: ${RESP:0:250}"; }
FS(){ $DC exec -T django sh -c 'ls $DJANGO_PRIVATE_MEDIA_ROOT/tenants/academy_qa/employment 2>/dev/null | wc -l'; }
echo "== TC-021"; echo "files before: $(FS)"
mp adm POST contracts/ -F teacher=7 -F reference=EMP-1 -F details= -F file=@$F/sample.pdf; CT=$(python3 -c "import json,sys;print(json.loads(sys.argv[1])['id'])" "$RESP"); echo "CT=$CT" >> ids.env
echo "$RESP" | grep -ci "http\|/media\|tenants/" 
r adm qa GET contracts/ | cut -c1-200; api adm qa GET "contracts/?teacher=7"; echo "teacher=7: $(jq_ "[x['id'] for x in d.get('results',d)]")"; api adm qa GET "contracts/?q=EMP"; echo "q=EMP: $(jq_ "[x['id'] for x in d.get('results',d)]")"
curl -s -D $J/fh -o $J/dl.pdf -b $J/adm http://qa.etqan.localhost/api/v1/contracts/$CT/file/; grep -i "^HTTP\|cache-control\|nosniff\|disposition\|content-type" $J/fh; echo "sha upload=$(shasum -a256 < $F/sample.pdf|cut -c1-16) dl=$(shasum -a256 < $J/dl.pdf|cut -c1-16)"
curl -s -o $J/dlt.pdf -w "teacher dl %{http_code}\n" -b $J/tch http://qa.etqan.localhost/api/v1/contracts/$CT/file/; echo "teacher sha=$(shasum -a256 < $J/dlt.pdf|cut -c1-16)"
Q "select id,teacher_id,reference,file from academy_qa.employment_contract where id=$CT"; OLD=$(Q "select file from academy_qa.employment_contract where id=$CT")
mp adm PATCH contracts/$CT/ -F file=@$F/sample.docx; NEW=$(Q "select file from academy_qa.employment_contract where id=$CT"); sleep 1
$DC exec -T django sh -c "test -e \$DJANGO_PRIVATE_MEDIA_ROOT/$OLD && echo old-still-exists || echo old-removed; test -e \$DJANGO_PRIVATE_MEDIA_ROOT/$NEW && echo new-exists"
mp adm PATCH contracts/$CT/ -F remove_file=true -F details=
mp adm PATCH contracts/$CT/ -F remove_file=true -F details=Signed-on-paper
mp adm PATCH contracts/$CT/ -F file=@$F/sample.pdf -F remove_file=false >/dev/null; echo "re-attach $CODE"
B0=$(FS); C0=$(Q "select count(*) from academy_qa.employment_contract")
mp adm POST contracts/ -F teacher=7 -F reference=BAD1 -F file=@$F/evil.exe
mp adm POST contracts/ -F teacher=7 -F reference=BAD2 -F file=@$F/big.pdf
mp adm POST contracts/ -F teacher=7 -F reference=BAD3 -F file=@$F/fake.pdf
mp adm POST contracts/ -F teacher=$K1 -F reference=BAD4 -F file=@$F/sample.pdf
mp adm POST contracts/ -F teacher=7 -F reference=BAD5
mp adm POST contracts/ -F teacher=7 -F reference=$(python3 -c 'print("R"*61)') -F details=x
echo "rows $C0 -> $(Q "select count(*) from academy_qa.employment_contract")  files $B0 -> $(FS)"
mp adm POST contracts/ -F teacher=7 -F reference=LONG -F "file=@$F/$(python3 -c 'print("n"*296)').pdf"; LC=$(python3 -c "import json,sys;print(json.loads(sys.argv[1]).get('id'))" "$RESP")
Q "select length(file), right(file,4), file_name from academy_qa.employment_contract where id=$LC" 2>&1 | head -2
echo "-- S8 non-docx zip as .docx"; mp adm POST contracts/ -F teacher=7 -F reference=S8 -F file=@$F/notdocx.docx; S8=$(python3 -c "import json,sys;print(json.loads(sys.argv[1]).get('id'))" "$RESP")
mp adm DELETE contracts/$S8/; mp adm DELETE contracts/$LC/
Q "select pg_get_constraintdef(oid) from pg_constraint where conname like 'employment_contract_details_or_file'"
