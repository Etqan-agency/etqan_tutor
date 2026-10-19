from qa import *
st = st_load(); a = S(); a.login(*PW["admin"])
log("== UI smoke DB check", datetime.datetime.now().isoformat())
log(q("select id,number,amount_minor,currency,status,payer_id,description from billing_invoice where description like 'F09 UI%' order by id"))
log(q("select p.invoice_id,p.method,p.amount_minor,p.fee_minor,p.currency,p.status from billing_payment p join billing_invoice i on i.id=p.invoice_id where i.description like 'F09 UI%' order by 1"))
save("pw-db.txt")
log("== cleanup", datetime.datetime.now().isoformat())
log("staff3 roles", a.patch("/access/staff/3/",{"role_ids":[3]})[0])
for r in ["R_WC","R_WU","R_VONLY"]:
    if st.get(r): log("retire", r, a.patch(f"/access/roles/{st[r]}/",{"is_active":False})[0])
c,j=a.get("/gateways/checkouts/?attention=open&page_size=100")
for r in j.get("results",[]):
    log("resolve", r["id"], r.get("attention"), a.post(f"/gateways/checkouts/{r['id']}/resolve/",{})[0])
log("open links", q("select id,status from gateways_paymentlink where status='open'"))
log("settings", short(a.get("/gateways/settings/")[1].get("fee")), short(a.get("/billing/settings/")[1]))
log("features qa", q("select features from public.tenants_academy where subdomain='qa'","public"))
dc("exec","-T","django","python","manage.py","shell","-c","from django.core.cache import cache; cache.clear()")
for n in ["admin","staffc","student","parent"]:
    s=S(); log("login", n, s.login(*PW[n]))
log("final counts", [ (t, q(f"select count(*) from {t}")) for t in ["billing_invoice","billing_payment","wallet_walletentry","vouchers_voucher","gateways_checkout"]])
save("cleanup.txt")
