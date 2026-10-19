. ./lib.sh
login adm qa qa-admin@qa.etqan.test 'QA-Admin-2026!'
login codes qa qa-staff-codes@qa.etqan.test 'QA-People-2026!'
login nocode qa qa-staff-nocode@qa.etqan.test 'QA-People-2026!'
login sup qa qa-supervisor@qa.etqan.test 'QA-People-2026!'
login tea qa qa-teacher@qa.etqan.test 'QA-People-2026!'
login tea2 qa qa-teacher2@qa.etqan.test 'QA-People-2026!'
login stu qa qa-student@qa.etqan.test 'QA-People-2026!'
login par qa qa-parent@qa.etqan.test 'QA-People-2026!'
login oth qaother qaother-admin@qa.etqan.test 'QA-Other-2026!'
Q "select features from public.tenants_academy where schema_name='academy_qa'"
Q "select id,status,student_id,teacher_id,course_id,package_id,starts_on,ends_on from academy_qa.scheduling_subscription where status='active' order by id"
Q "select id,name_en,sessions_per_week,session_minutes,price_minor,currency,is_active from academy_qa.catalogue_package order by id"
Q "select id,name_en from academy_qa.catalogue_course order by id"
Q "select status,count(*) from academy_qa.scheduling_session group by 1"
Q "select id,teacher_id,period_start,status from academy_qa.payroll_payslip order by id" 2>&1 | tail -20
W=600 r adm qa GET "sessions/?page_size=1"
