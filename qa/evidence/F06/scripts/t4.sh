. ./lib.sh; . ./ids.env
W=200 r oth qaother POST catalogue/courses/ '{"name_ar":"س","name_en":"QA6OTHER Course","language":"ar","teacher_ids":[]}'; OC=$(jq_ "d['id']")
W=200 r oth qaother POST catalogue/packages/ '{"name_ar":"س","name_en":"QA6OTHER Pkg","sessions_per_week":1,"session_minutes":30,"duration_value":1,"duration_unit":"month","price_minor":777,"currency":"USD"}'; OP=$(jq_ "d['id']")
echo "OC=$OC OP=$OP" >> ids.env
cnt(){ echo "qa=$(Q "select count(*)||'/'||max(updated_at) from academy_qa.catalogue_package") other=$(Q "select count(*)||'/'||max(updated_at) from academy_qaother.catalogue_package")"; }
echo "before: $(cnt)"
for id in $OP 99; do echo "qa admin -> pkg $id"
 W=120 r adm qa GET catalogue/packages/$id/; r adm qa PATCH catalogue/packages/$id/ '{"name_en":"HACK"}'; r adm qa POST catalogue/packages/$id/duplicate/; r adm qa GET catalogue/packages/$id/country-prices/; r adm qa DELETE catalogue/packages/$id/ ; done
echo "qa admin -> course $OC"; W=120 r adm qa GET catalogue/courses/$OC/
echo "qaother admin -> qa P1=$P1 / C1=$C1"
W=160 r oth qaother GET catalogue/packages/$P1/; r oth qaother PATCH catalogue/packages/$P1/ '{"name_en":"HACK"}'; r oth qaother GET catalogue/packages/$P1/country-prices/; r oth qaother POST catalogue/packages/$P1/duplicate/; r oth qaother GET catalogue/courses/$C1/
api oth qaother GET catalogue/packages/; echo "qaother list names: $(jq_ "[x['name_en'] for x in d.get('results',d)]")"
api adm qa GET catalogue/packages/; echo "qa list names: $(jq_ "[x['name_en'] for x in d.get('results',d)]")"
echo "cross-host cookies:"; W=120 r oth qa GET catalogue/packages/; r adm qaother GET catalogue/packages/
echo "after: $(cnt)"
