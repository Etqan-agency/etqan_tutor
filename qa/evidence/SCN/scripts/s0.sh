. ./lib.sh
echo "== features"
$DC exec -T django python manage.py set_features qa --on families parents invoices payment_receipts balances system_codes supervision session_reports teacher_attendance manual_sessions extra_sessions activity_log payroll_rules salary_projections report_deductions salary_expenses payslip_acknowledgement weekly_schedules postponement auto_notifications notification_preferences 2>&1 | tail -5
Q "select features from public.tenants_academy where subdomain='qa'"
echo "== logins"
login adm qa qa-admin@qa.etqan.test 'QA-Admin-2026!'
login sup qa qa-supervisor@qa.etqan.test 'QA-People-2026!'
login tea qa qa-teacher@qa.etqan.test 'QA-People-2026!'
login par qa qa-parent@qa.etqan.test 'QA-People-2026!'
login oadm qaother qaother-admin@qa.etqan.test 'QA-Other-2026!'
echo "== settings before"
W=3000 r adm qa GET academy/settings/
W=2000 r adm qa GET payroll/settings/
W=2000 r adm qa GET billing/settings/
echo "== snapshot"
QQ "select 'invoice',count(*) from billing_invoice union all select 'payment',count(*) from billing_payment union all select 'walletentry',count(*) from wallet_walletentry union all select 'session',count(*) from scheduling_session union all select 'payslip',count(*) from payroll_payslip union all select 'expense',count(*) from finance_expense union all select 'notif',count(*) from notifications_notification"
QQ "select last_number from billing_invoicecounter"
QQ "select coalesce(sum(amount_minor),0) from finance_expense where source='payroll.payslip'"
QQ "select currency, sum(amount_minor+fee_minor) from billing_payment where status in ('completed','credited') and method not in ('wallet','code') and paid_on >= date_trunc('month', now() at time zone 'Africa/Cairo') group by 1"
W=3000 r adm qa GET billing/summary/
W=3000 r adm qa GET finance/summary/
QQ "select id,email,role from identity_user where email in ('qa-teacher@qa.etqan.test','qa-supervisor@qa.etqan.test','qa-parent@qa.etqan.test')"
