. ./lib.sh; . ./ids.env
echo "== TC-016"
QQ "select id,teacher_id,status,gross_minor,net_minor,md5(row(p.*)::text) from payroll_payslip p where year=2026 and month=9 order by id" > /tmp/../$J/sept_before.txt 2>/dev/null || true
SEPT0=$(QQ "select md5(string_agg(row(p.*)::text,',' order by id)) from payroll_payslip p where year=2026 and month=9 and teacher_id<>(select id from identity_teacherprofile where user_id=$T3)"|tail -1)
PC0=$(QQ "select last_number from payroll_payslipcounter"|tail -1); EX0=$(QQ "select coalesce(sum(amount_minor),0) from finance_expense where source='payroll.payslip'"|tail -1)
echo "payslip counter $PC0, payroll expense sum $EX0"
W=600 r adm qa POST payroll/payslips/generate/ '{"year":2026,"month":9}'
api adm qa GET "payroll/payslips/?year=2026&month=9&teacher=$T3"; PS=$(j "[p['id'] for p in (d['results'] if isinstance(d,dict) else d) if p['teacher']['id']==$T3][0]"); echo "PS3=$PS" >> ids.env; echo "T3 slip $PS"
api adm qa GET payroll/payslips/$PS/; echo "slip: $(j "{k:d.get(k) for k in ('number','status','gross_minor','net_minor','currency')}")"
echo "lines: $(j "[(l.get('kind'),l.get('session_id',l.get('session')),l.get('minutes'),l.get('rate_minor'),l.get('amount_minor')) for l in d.get('lines',[])]")"
W=300 r adm qa POST payroll/payslips/$PS/issue/
W=200 r adm qa POST sessions/$M1/attendance/ '{"student_attendance":"absent"}'
W=200 r adm qa POST payroll/payslips/$PS/mark-paid/ '{"paid_on":"2026-10-19","notes":"scn"}'
api t3 qa GET payroll/payslips/; echo "T3 own list: $(j "[(p['id'],p['teacher']['id'],p['status']) for p in (d['results'] if isinstance(d,dict) else d)]")"
W=200 r t3 qa POST payroll/payslips/$PS/acknowledge/
W=150 r tea qa GET payroll/payslips/$PS/
W=300 r adm qa POST payroll/payslips/generate/ '{"year":2026,"month":9}'
echo "-- DB"
QQ "select id,number,status,gross_minor,net_minor,currency,acknowledged_at is not null from payroll_payslip where id=$PS"
QQ "select kind,count(*),sum(amount_minor) from payroll_payslipline where payslip_id=$PS group by 1"
QQ "select session_id,minutes,rate_minor,amount_minor from payroll_payslipline where payslip_id=$PS order by session_id"
QQ "select id,payroll_locked from scheduling_session where subscription_id=$SUB3 order by id"
QQ "select id,source,source_id,amount_minor,currency,spent_on from finance_expense where source='payroll.payslip' and source_id='$PS'" 2>&1
QQ "select column_name from information_schema.columns where table_schema='academy_qa' and table_name='finance_expense'" | tr '\n' ' '; echo
QQ "select last_number from payroll_payslipcounter"
SEPT1=$(QQ "select md5(string_agg(row(p.*)::text,',' order by id)) from payroll_payslip p where year=2026 and month=9 and teacher_id<>(select id from identity_teacherprofile where user_id=$T3)"|tail -1)
echo "other teachers' Sept payslips unchanged: $([ "$SEPT0" = "$SEPT1" ] && echo yes || echo NO)"
echo "payroll expense delta: $(( $(QQ "select coalesce(sum(amount_minor),0) from finance_expense where source='payroll.payslip'"|tail -1) - EX0 ))"
