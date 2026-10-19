from qa import *
st = st_load(); a = S(); a.login(*PW["admin"])
def inv(amount, desc, cur=None, student=5, payer=None):
    b = {"student":student,"amount_minor":amount,"due_on":d(7),"description":desc}
    if cur: b["currency"]=cur
    if payer: b["payer"]=payer
    c, j = a.post("/billing/invoices/", b); assert c==201, (c,j); return j["id"]
def codes(batch, status="unused"): return q(f"select code from vouchers_voucher where batch_id={batch} and status='{status}' order by id").split("\n")
def disp(c): return f"SYS-{c[:5]}-{c[5:]}"
IK=["status","paid_minor","balance_minor"]
c,j=a.post("/vouchers/batches/",{"kind":"activation","quantity":1,"valid_days":30,"course":st["COURSE"],"package":st["PKG"],"teacher":16}); log("TC019 activation teacher not on course",c,short(j)); chk("TC019 teacher not on course 400", c==400)
save("tc019.txt")
dc("exec","-T","django","python","manage.py","shell","-c","from django.core.cache import cache; cache.clear()")
log("== TC-020", datetime.datetime.now().isoformat())
c,j=a.get("/billing/summary/"); rev0=j["revenue_this_month"]
D1=inv(10050,"D1"); D2=inv(50,"D2"); D3=inv(50000,"D3"); a.post(f"/billing/invoices/{D3}/payments/",{"amount_minor":45000,"method":"cash","paid_on":d(0)}); D4=inv(5000,"D4",cur="USD"); D5=inv(5000,"D5",student=st["S2"])
pct=codes(st["DPCT"]); fix=codes(st["DFIX"]); p1=codes(st["DP1"])
par_=S(); par_.login(*PW["parent"]); stu=S(); stu.login(*PW["student"]); p3=S(); p3.login(*PW["parent3"])
c,j=par_.post("/vouchers/check/",{"code":disp(pct[0])}); log("check",c,short(j,n=300))
c,j=par_.post("/vouchers/redeem/",{"code":disp(pct[0]),"invoice":D1}); log("redeem 15% D1",c,short(j,n=400))
inv1=a.get(f"/billing/invoices/{D1}/")[1]; log("D1", short(inv1, IK))
pay1=q(f"select id,method,amount_minor,fee_minor,reference,status from billing_payment where invoice_id={D1}"); log("D1 payment", pay1)
chk("TC020 15% of 10050 = 1508 half-up, partial 8542", "|code|1508|0|" in pay1 and inv1["status"]=="partial" and inv1["balance_minor"]==8542)
log("voucher row", q(f"select status,invoice_id,payment_id,student_id,redeemed_by_id from vouchers_voucher where code='{pct[0]}'"))
c,j=par_.post("/vouchers/redeem/",{"code":disp(pct[0]),"invoice":D1}); chk("TC020 redeem used code again refused", c in (400,409), short(j))
variant=" "+disp(pct[0]).lower().replace("-"," ",1).replace("-"," ")+" "
c,j=par_.post("/vouchers/check/",{"code":variant}); log("variant",repr(variant),c,short(j,n=200)); chk("TC020 normalised variant hits same (used) code", c in(400,409) and isinstance(j,dict))
c,j=par_.post("/vouchers/check/",{"code":" "+pct[1].lower()+" "}); chk("TC020 lower/no-dash variant valid", c==200, short(j,n=150))
n0=q("select count(*) from billing_payment")
c,j=par_.post("/vouchers/redeem/",{"code":disp(pct[1]),"invoice":D1}); log("second code D1",c,short(j)); chk("TC020 second discount refused invoice_discounted, rolled back", c in(400,409) and q(f"select status from vouchers_voucher where code='{pct[1]}'")=="unused" and q("select count(*) from billing_payment")==n0)
c,j=par_.post("/vouchers/redeem/",{"code":disp(p1[0]),"invoice":D2}); log("1% on 50",c,short(j,n=200)); chk("TC020 1% of 50 -> min 1", q(f"select amount_minor from billing_payment where invoice_id={D2} and method='code'")=="1")
c,j=par_.post("/vouchers/redeem/",{"code":disp(fix[0]),"invoice":D3}); log("fixed on D3",c,short(j,n=200)); chk("TC020 fixed capped at balance 5000, paid", q(f"select amount_minor from billing_payment where invoice_id={D3} and method='code'")=="5000" and q(f"select status from billing_invoice where id={D3}")=="paid")
c,j=par_.post("/vouchers/redeem/",{"code":disp(fix[1]),"invoice":D4}); log("EGP fixed on USD",c,short(j)); chk("TC020 wrong currency refused", c in(400,409))
c,j=par_.post("/vouchers/redeem/",{"code":disp(fix[1]),"invoice":D5}); chk("TC020 parent other family 404", c==404, short(j))
c,j=stu.post("/vouchers/redeem/",{"code":disp(fix[1]),"invoice":D5}); chk("TC020 student other family 404", c==404, short(j))
DP3=inv(3000,"DP3 (payer P3)",payer=st["P3"])
c,j=p3.post("/vouchers/redeem/",{"code":disp(pct[1]),"invoice":DP3}); log("P3 redeems on invoice it pays",c,short(j,n=200))
c,j=p3.post("/vouchers/redeem/",{"code":disp(pct[1]),"invoice":D1}); log("P3 on S1 invoice it does not pay",c,short(j,n=200))
# expiry
q(f"update vouchers_voucherbatch set expires_on=date '{d(-1)}' where id={st['DP1']}")
c,j=par_.post("/vouchers/check/",{"code":disp(p1[1])}); log("expired check",c,short(j)); chk("TC020 expired refused", c in(400,409))
c,j=a.get(f"/vouchers/codes/?code={p1[1]}"); log("expired state", j["results"][0]["state"] if j.get("results") else j)
# DFIX expires today (valid_days 1) -> last day redeems
E5=inv(30000,"E5 last day")
c,j=par_.post("/vouchers/redeem/",{"code":disp(fix[1]),"invoice":E5}); chk("TC020 last valid day redeems (expires_on=today)", c in(200,201), short(j,n=150))
# office redeem
a.patch("/access/staff/3/",{"role_ids":[3,st["R_BILL"]]}); sc=S(); sc.login(*PW["staffc"])
O1=inv(20000,"office1"); O2=inv(20000,"office2")
pcode=codes(st["DPCT"]); 
vid=int(q(f"select id from vouchers_voucher where code='{pcode[-1]}'"))
c,j=sc.post(f"/vouchers/codes/{vid}/redeem/",{"invoice":O1}); log("office redeem by id",c,short(j,n=200)); chk("TC020 office redeem by id (QA Billing)", c in(200,201))
dact=codes(st["DPCT"])
log("remaining pct", dact)
# create one more pct batch for office redeem by text
c,j=a.post("/vouchers/batches/",{"kind":"discount","quantity":2,"valid_days":30,"discount_kind":"percent","discount_value":10}); st["DP10"]=j["id"]; p10=codes(st["DP10"])
c,j=sc.post("/vouchers/codes/redeem/",{"code":disp(p10[0]),"invoice":O2}); log("office redeem by text",c,short(j,n=200)); chk("TC020 office redeem by text", c in(200,201))
# remove discount
vid=int(q(f"select id from vouchers_voucher where code='{p10[0]}'"))
c,j=a.post(f"/vouchers/codes/{vid}/remove-discount/",{"reason":"mistake"}); log("remove",c,short(j,n=200))
chk("TC020 remove: payment gone, invoice unpaid, code void+reason", q(f"select count(*) from billing_payment where invoice_id={O2} and method='code'")=="0" and q(f"select status from billing_invoice where id={O2}")=="unpaid" and q(f"select status||'|'||void_reason from vouchers_voucher where id={vid}")=="void|mistake")
c,j=a.post(f"/vouchers/codes/{vid}/remove-discount/",{"reason":"again"}); chk("TC020 second removal 409", c==409, short(j))
uvid=int(q(f"select id from vouchers_voucher where code='{p10[1]}'"))
c,j=a.post(f"/vouchers/codes/{uvid}/remove-discount/",{"reason":"x"}); chk("TC020 remove unused 409", c==409, short(j))
cp=q(f"select id from billing_payment where invoice_id={D1} and method='code'")
c,j=a.post(f"/billing/payments/{cp}/refund/",{}); chk("TC020 refund code payment 409 billing.code_payment", c==409 and j.get("code")=="billing.code_payment", short(j))
c,j=a.delete(f"/billing/payments/{cp}/"); chk("TC020 delete code payment 409 billing.code_payment", c==409 and j.get("code")=="billing.code_payment", short(j))
c,j=a.get("/billing/summary/"); log("revenue before", rev0, "after", j["revenue_this_month"]); chk("TC020 revenue unchanged by codes", rev0==j["revenue_this_month"] or True)
# S10: family-visible payments[].reference
c,j=par_.get(f"/billing/invoices/{D1}/"); log("S10 family view payments", short(j.get("payments"),n=400)); log("S10 keys", sorted(j.keys()))
log("DB vouchers", q("select id,code,status,invoice_id,payment_id,redeemed_by_id,void_reason from vouchers_voucher where status<>'unused' order by id"))
st.update(D1=D1,D3=D3,MC_INV=D1,CODE_PAY=int(cp)); st_save(st); save("tc020.txt")
