. ./lib.sh; . ./ids.env
echo "== TC-018 (snapshot from s0: revenue EGP 747856, expenses EGP 939065, payroll.payslip expense 967065, invoices 145, payments 67, wallet entries 28, payslips 38)"
W=800 r adm qa GET billing/summary/
W=800 r adm qa GET finance/summary/
echo "-- 1 revenue (DB)"; QQ "select currency, sum(amount_minor+fee_minor) from billing_payment where status in ('completed','credited') and method not in ('wallet','code') and paid_on >= date_trunc('month', now() at time zone 'Africa/Cairo') group by 1 order by 1"
QQ "select method, sum(amount_minor), count(*) from billing_payment where id>74 group by 1"
echo "-- 2 receivables"
QQ "select id,number,amount_minor,status,due_on from billing_invoice where id>145 order by id"
QQ "select count(*), sum(i.amount_minor - coalesce((select sum(amount_minor) from billing_payment p where p.invoice_id=i.id and p.status in ('completed','credited')),0)) from billing_invoice i where i.id>145 and i.status<>'void' and i.amount_minor > coalesce((select sum(amount_minor) from billing_payment p where p.invoice_id=i.id and p.status in ('completed','credited')),0)"
QQ "select count(*) from billing_invoice i where i.status in ('paid') and i.amount_minor <> (select coalesce(sum(amount_minor),0) from billing_payment p where p.invoice_id=i.id and p.status in ('completed','credited'))"
QQ "select count(*) from billing_invoice i where i.status in ('unpaid','partial') and i.amount_minor <= (select coalesce(sum(amount_minor),0) from billing_payment p where p.invoice_id=i.id and p.status in ('completed','credited'))"
echo "-- 3 payroll/finance"
QQ "select sum(amount_minor) from finance_expense where source='payroll.payslip'"
QQ "select currency,sum(amount_minor) from finance_expense where spent_on >= date_trunc('month', now() at time zone 'Africa/Cairo') group by 1"
QQ "select sum(gross_minor), count(*) from payroll_payslip where year=2026 and month=9"
QQ "select p.id, p.gross_minor, (select sum(amount_minor) from payroll_payslipline l where l.payslip_id=p.id and kind='session') from payroll_payslip p where id=$PS3"
echo "-- 4 attendance"
QQ "select subscription_id, count(*) filter (where status='completed' and student_attendance='present' and teacher_attendance<>'absent' and kind in ('regular','compensation') and compensated=false) from scheduling_session where subscription_id in ($SUB1,$SUB3) group by 1"
api adm qa GET subscriptions/$SUB1/; echo "SUB1 used $(j "d['sessions_used']")"; api adm qa GET subscriptions/$SUB3/; echo "SUB3 used $(j "d['sessions_used']")"
echo "-- wallet"
QQ "select (select sum(balance_minor) from wallet_wallet), (select sum(amount_minor) from wallet_walletentry)"
QQ "select count(*) from wallet_wallet w where w.balance_minor <> (select coalesce(sum(amount_minor),0) from wallet_walletentry e where e.wallet_id=w.id)"
echo "-- 5 CSV"
for p in "billing/invoices/?format=csv" "billing/payments/?format=csv" "sessions/?format=csv"; do
  curl -s -b $J/adm "http://qa.etqan.localhost/api/v1/$p" -o $J/x.csv -w "[%{http_code}] $p %{content_type}\n"; echo "rows=$(($(wc -l < $J/x.csv)-1)) head: $(head -1 $J/x.csv | cut -c1-200)"; sed -n 2p $J/x.csv | cut -c1-250; cp $J/x.csv "../$(echo $p | tr '/?=' '___').csv"
done
api adm qa GET "billing/invoices/?page_size=1"; echo "invoices API count $(j "d['count']")"
api adm qa GET "billing/payments/?page_size=1"; echo "payments API count $(j "d['count']")"
api adm qa GET "sessions/?page_size=1"; echo "sessions API count $(j "d['count']")"
echo "-- 6 projection"
W=1500 r adm qa GET payroll/payslips/projection/
