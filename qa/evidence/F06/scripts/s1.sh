. ./lib.sh
Q "select id,name_en,is_active from academy_qa.catalogue_course order by id"
Q "select id,name_en,price_minor,currency,is_active from academy_qa.catalogue_package order by id"
Q "select count(*),status from academy_qa.scheduling_subscription group by 2"
Q "select count(*) from academy_qa.scheduling_session"
Q "select u.id,u.full_name,u.is_active from academy_qa.identity_user u join academy_qa.identity_teacherprofile t on t.user_id=u.id order by 1" 2>&1|head -20
Q "select table_name from information_schema.tables where table_schema='academy_qa' and table_name like 'identity%'"
Q "select timezone,generation_horizon_days,renewal_grace_days from academy_qa.academy_academysettings" 2>&1
