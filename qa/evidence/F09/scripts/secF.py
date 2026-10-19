from qa import *
st = st_load(); a = S(); a.login(*PW["admin"])
def inv(amount, desc, cur=None, student=5, payer=None):
    b = {"student":student,"amount_minor":amount,"due_on":d(7),"description":desc}
    if cur: b["currency"]=cur
    if payer: b["payer"]=payer
    c, j = a.post("/billing/invoices/", b); assert c==201, (c,j); return j["id"]
IK=["status","paid_minor","balance_minor"]
log("== TC-022", datetime.datetime.now().isoformat())
c,j=a.get("/billing/summary/"); rev0={x["currency"]:x["amount_minor"] for x in j["revenue_this_month"]}
O1=inv(50000,"O1"); O2=inv(10050,"O2"); O3=inv(1,"O3")
par_=S(); par_.login(*PW["parent"])
c,j=par_.get(f"/billing/invoices/{O1}/"); log("can_pay_online", c, j.get("can_pay_online"))
def start(sess, ref, prov="stripe", purpose="invoice"):
    return sess.post("/gateways/checkouts/start/",{"purpose":purpose,"reference_id":ref,"provider":prov})
c,j=start(par_,O1); log("start O1",c,short(j,n=400)); K1=j.get("id")
chk("TC022 start 201 amount 50000 fee 2500 EGP", c==201 and j.get("amount_minor")==50000 and j.get("fee_minor")==2500 and j.get("currency")=="EGP")
c,j2=start(par_,O1); chk("TC022 second start reuses same checkout", j2.get("id")==K1, f"{c} {j2.get('id')}")
c,j=start(par_,O2); log("O2",c,short(j,n=300)); chk("TC022 O2 fee 503", j.get("fee_minor")==503)
c,j=start(par_,O3); log("O3",c,short(j,n=300)); chk("TC022 O3 1 minor fee 0 (half-up of 0.05)", c==201 and j.get("fee_minor")==0)
c,j=par_.get(f"/gateways/checkouts/{K1}/"); log("checkout detail", c, short(j,n=300))
c,j=par_.post(f"/gateways/simulate/{K1}/",{"outcome":"pay"}); log("simulate pay",c,short(j,n=300))
c,j=par_.post(f"/gateways/simulate/{K1}/",{"outcome":"pay"}); log("simulate pay again",c,short(j,n=200))
c,j=par_.post(f"/gateways/simulate/{K1}/",{"outcome":"fail"}); log("simulate fail after paid",c,short(j,n=200))
log("checkout DB", q(f"select purpose,reference_id,provider,simulated,amount_minor,fee_minor,status,applied,attention,transaction_number from gateways_checkout where id='{K1}'"))
log("payment DB", q(f"select id,method,amount_minor,fee_minor,currency,transaction_number,recorded_by_id,paid_on,status from billing_payment where invoice_id={O1}"))
chk("TC022 invoice paid once, payment 50000+2500 stripe, txn matches", q(f"select status from billing_invoice where id={O1}")=="paid" and q(f"select count(*) from billing_payment where invoice_id={O1}")=="1" and q(f"select p.transaction_number=c.transaction_number and p.amount_minor=50000 and p.fee_minor=2500 and p.recorded_by_id is null and p.paid_on=date '{d(0)}' from billing_payment p, gateways_checkout c where p.invoice_id={O1} and c.id='{K1}'")=="t")
chk("TC022 checkout completed applied", q(f"select status||applied::text||attention from gateways_checkout where id='{K1}'")=="completedtrue")
c,j=a.get("/gateways/checkouts/"); log("admin checkouts", c, j.get("count") if isinstance(j,dict) else j)
c,j=a.get("/billing/payments/?method=stripe"); log("payments stripe", c, j.get("count") if isinstance(j,dict) else short(j))
c,j=a.get("/billing/summary/"); rev1={x["currency"]:x["amount_minor"] for x in j["revenue_this_month"]}; chk("TC022 revenue +52500", rev1["EGP"]-rev0["EGP"]==52500, f"{rev0['EGP']}->{rev1['EGP']}")
# fee variations on fresh invoices (reuse would keep old fee)
for fee,exp in [({"enabled":False},0),({"enabled":True,"basis_points":2000},2010),({"enabled":True,"basis_points":0},0)]:
    a.patch("/gateways/settings/",{"fee":fee}); Ox=inv(10050,f"fee {fee}")
    c,j=start(par_,Ox); log("fee",fee,c,short(j,["amount_minor","fee_minor"])); chk(f"TC022 fee {fee} -> {exp}", j.get("fee_minor")==exp)
c,j=a.patch("/gateways/settings/",{"fee":{"enabled":True,"basis_points":500}}); log("fee restored", c, short(j.get("fee")))
# refusals
S2I=inv(5000,"S2 online",student=st["S2"]); V=inv(5000,"void online"); a.post(f"/billing/invoices/{V}/void/",{})
for lbl,args,sess in [("other family",(S2I,),par_),("void",(V,),par_),("paid",(O1,),par_),("paypal EGP",(O2,"paypal"),par_),("purpose nope",(O2,"stripe","nope"),par_),("ref 0",(0,),par_)]:
    c,j=start(sess,*args); log(lbl,c,short(j,n=200)); chk(f"TC022 refuse {lbl} 4xx", 400<=c<500)
sn=S(); sn.login(*PW["staffno"]); c,j=start(sn,O2); chk("TC022 staff without invoice.view refused", c in (403,404), f"{c} {short(j)}")
st.update(O1=O1,K1=K1,PS=int(q(f"select id from billing_payment where invoice_id={O1}")))
st_save(st); save("tc022.txt")
