from qa import *
st = st_load(); a = S(); a.login(*PW["admin"])
log("== TC-009", datetime.datetime.now().isoformat())
a.post(f"/billing/invoices/{st['INV_USD']}/payments/",{"amount_minor":5050,"method":"cash","paid_on":d(0)})
J=a.post("/billing/invoices/",{"student":5,"amount_minor":1500,"due_on":d(7),"description":"JPY","currency":"JPY"})[1]["id"]
c,j=a.post(f"/billing/invoices/{st['KW']}/payments/",{"amount_minor":12345,"method":"cash","paid_on":d(0)}); log("KWD pay",c,short(j,["status","paid_minor"]))
c,j=a.post("/billing/invoices/",{"student":5,"amount_minor":100,"due_on":d(7),"description":'=HYPERLINK("http://x","y")'}); log("injection invoice",c)
# overdue: an invoice due today is not overdue; we can't create past due (due>=issued). use existing ones
c,j=a.get("/billing/summary/"); log("summary", short(j,n=600)); api={x["currency"]:x["amount_minor"] for x in j["revenue_this_month"]}
sql=q("select currency,sum(amount_minor+fee_minor) from billing_payment where status in ('completed','credited') and method not in ('wallet','code') and paid_on >= date_trunc('month',(now() at time zone 'Africa/Cairo')::date) group by 1 order by 1")
log("SQL revenue", sql); sqld={l.split("|")[0]:int(l.split("|")[1]) for l in sql.split("\n") if l}
chk("TC009 revenue per currency == SQL", api==sqld, f"api {api} sql {sqld}")
chk("TC009 revenue is a list per currency", isinstance(j["revenue_this_month"],list))
log("paid_minor consistency (should be empty)", q("select i.id from billing_invoice i left join (select invoice_id,sum(amount_minor) s from billing_payment where status='completed' group by 1) p on p.invoice_id=i.id where i.status<>'void' and i.status <> case when coalesce(s,0)=0 then 'unpaid' when s<i.amount_minor then 'partial' else 'paid' end"))
# API balance sum vs SQL
c,j=a.get("/billing/invoices/?page_size=500"); res=j["results"]; log("invoice count", j["count"], len(res))
apib={}
for r in res:
    if r["status"]!="void": apib[r["currency"]]=apib.get(r["currency"],0)+r["balance_minor"]
sqlb=q("select i.currency,sum(i.amount_minor-coalesce(p.s,0)) from billing_invoice i left join (select invoice_id,sum(amount_minor) s from billing_payment where status='completed' group by 1) p on p.invoice_id=i.id where i.status<>'void' group by 1 order by 1")
log("open balance API", apib, "SQL", sqlb); chk("TC009 open balance per currency API == SQL", apib=={l.split('|')[0]:int(l.split('|')[1]) for l in sqlb.split("\n") if l})
c,txt=a.get("/billing/invoices/?format=csv",raw=True); lines=txt.splitlines(); log("inv csv",c,lines[0][:200]); 
for l in lines:
    if "JPY" in l or "KWD" in l or "HYPERLINK" in l: log("  ", l[:220])
chk("TC009 CSV injection defused", any("HYPERLINK" in l for l in lines) and not any(l.split(",")[i].startswith("=") for l in lines for i in range(len(l.split(","))) if "HYPERLINK" in l))
c,txt=a.get("/billing/payments/?format=csv",raw=True); pl=txt.splitlines(); log("pay csv",c,pl[0][:200], "rows", len(pl)-1)
for l in pl:
    if "KWD" in l: log("  ", l[:200])
c,j=a.get("/billing/payments/?currency=USD&page_size=200"); log("payments USD", c, j.get("count"), set(r["currency"] for r in j["results"]))
chk("TC009 currency filter only USD", set(r["currency"] for r in j["results"])=={"USD"})
log("S7: refunded payments excluded from revenue regardless of refund date; revenue bucket = paid_on (code: summary.py)")
st_save(st); save("tc009.txt")
