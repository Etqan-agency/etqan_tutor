. ./lib.sh
DC=/Users/khaledsakr/.etqan-qa-tools/dc.sh
Q "select features from public.tenants_academy where schema_name='academy_qa'" 2>&1 | head -3
$DC exec -T django python manage.py set_features qa --on country_pricing trial_sessions teacher_availability study_groups multi_course_subscriptions families family_subscriptions group_subscriptions weekly_schedules subscription_archive invoices supervision 2>&1 | tail -5
login adm qa qa-admin@qa.etqan.test 'QA-Admin-2026!'
login codes qa qa-staff-codes@qa.etqan.test 'QA-People-2026!'
login nocode qa qa-staff-nocode@qa.etqan.test 'QA-People-2026!'
login sup qa qa-supervisor@qa.etqan.test 'QA-People-2026!'
login tea qa qa-teacher@qa.etqan.test 'QA-People-2026!'
login stu qa qa-student@qa.etqan.test 'QA-People-2026!'
login par qa qa-parent@qa.etqan.test 'QA-People-2026!'
login oth qaother qaother-admin@qa.etqan.test 'QA-Other-2026!'
