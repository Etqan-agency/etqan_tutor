from qa import *
st = st_load(); a = S(); a.login(*PW["admin"])
dc("exec","-T","django","python","manage.py","shell","-c","from django.core.cache import cache; cache.clear()")
log("== TC-028 (added by Agent 2, P1): mixed-source race on one invoice never overpays", datetime.datetime.now().isoformat())
stu=S(); stu.login(*PW["student"]); par_=S(); par_.login(*PW["parent"])
a.post("/wallet/students/5/top-ups/",{"amount_minor":30000,"currency":"EGP","method":"cash","reference":"TC028"})
c,j=a.post("/vouchers/batches/",{"kind":"discount","quantity":5,"valid_days":30,"discount_kind":"fixed","discount_value":10000,"currency":"EGP"}); codes=q(f"select code from vouchers_voucher where batch_id={j['id']} order by id").split("\n")
res_all=[]
for rnd in range(5):
    I=a.post("/billing/invoices/",{"student":5,"amount_minor":10000,"due_on":d(7),"description":f"TC028 race {rnd}"})[1]["id"]
    c,ck=par_.post("/gateways/checkouts/start/",{"purpose":"invoice","reference_id":I,"provider":"stripe"}); k=ck["id"]
    code=codes[rnd]
    res=par([lambda: a.post(f"/billing/invoices/{I}/payments/",{"amount_minor":10000,"method":"cash","paid_on":d(0)}),
             lambda: stu.post(f"/wallet/invoices/{I}/pay/",{}),
             lambda: par_.post("/vouchers/redeem/",{"code":code,"invoice":I}),
             lambda: par_.post(f"/gateways/simulate/{k}/",{"outcome":"pay"})])
    paid=q(f"select coalesce(sum(amount_minor),0)||'|'||count(*) from billing_payment where invoice_id={I} and status='completed'")
    stat=q(f"select status from billing_invoice where id={I}")
    att=q(f"select applied::text||'|'||attention from gateways_checkout where id='{k}'")
    log("round",rnd,"codes",[r[0] for r in res],"paid|n",paid,"status",stat,"checkout",att)
    chk(f"TC028 round {rnd}: sum completed == 10000, exactly one payment, paid", paid=="10000|1" and stat=="paid")
    chk(f"TC028 round {rnd}: losing code stays unused", q(f"select status from vouchers_voucher where code='{code}'") in ("unused","used") and (q(f"select status from vouchers_voucher where code='{code}'")=="used")==(q(f"select count(*) from billing_payment where invoice_id={I} and method='code'")=="1"))
log("ledger", q("select w.currency,w.balance_minor,(select sum(amount_minor) from wallet_walletentry e where e.wallet_id=w.id) from wallet_wallet w"))
log("overpay any", q("select i.id from billing_invoice i join billing_payment p on p.invoice_id=i.id and p.status='completed' group by i.id,i.amount_minor having sum(p.amount_minor)>i.amount_minor"))
log("5xx in log", dc("logs","--since","3m","django").count(" 500 "))
save("tc028.txt")
