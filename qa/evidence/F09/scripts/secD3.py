from qa import *
st = st_load(); a = S(); a.login(*PW["admin"])
def inv(amount, desc, cur=None, student=5, payer=None):
    b = {"student":student,"amount_minor":amount,"due_on":d(7),"description":desc}
    if cur: b["currency"]=cur
    if payer: b["payer"]=payer
    c, j = a.post("/billing/invoices/", b); assert c==201, (c,j); return j["id"]
def bal(cur="EGP"): return int(q(f"select coalesce(max(balance_minor),0) from wallet_wallet where student_id=1 and currency='{cur}'"))
def inv_inv(): return q("select w.id,w.currency,w.balance_minor,(select coalesce(sum(amount_minor),0) from wallet_walletentry e where e.wallet_id=w.id) from wallet_wallet w order by id")
IK=["status","paid_minor","balance_minor"]
log("== TC-017 DB verification of statuses (pay endpoint returns the wallet entry, not the invoice)")
st=st_load()
log(q(f"select id,description,amount_minor,currency,status from billing_invoice where id in ({st['W1']},{st['W2']},{st['W3']}) or description like 'race%' order by id"))
chk("TC017 W1 paid W2 partial(15000) W3 partial(2500)", q(f"select string_agg(status,',' order by id) from billing_invoice where id in ({st['W1']},{st['W2']},{st['W3']})")=="paid,partial,partial")
chk("TC017 race1/race2 exactly one paid", q("select string_agg(status,',' order by id) from billing_invoice where description in ('race1','race2')") in ("paid,unpaid","unpaid,paid"))
save("tc017.txt")
stu=S(); stu.login(*PW["student"])
a.post("/wallet/students/5/top-ups/",{"amount_minor":20000,"currency":"EGP","method":"cash","reference":"TC018 prep"})
W1=st["W1"]
log("== TC-018", datetime.datetime.now().isoformat())
c,j=a.get("/billing/summary/"); rev0=[x for x in j["revenue_this_month"] if x["currency"]=="EGP"][0]["amount_minor"]
M=inv(20000,"M"); a.post(f"/billing/invoices/{M}/payments/",{"amount_minor":10000,"method":"cash","paid_on":d(0)})
PM=int(q(f"select id from billing_payment where invoice_id={M} and method='cash'"))
c,j=stu.post(f"/wallet/invoices/{M}/pay/",{"amount_minor":10000}); PW=int(q(f"select id from billing_payment where invoice_id={M} and method='wallet'"))
b0=bal(); c,j=a.post(f"/wallet/payments/{PM}/move/",{}); log("move PM",c,short(j,n=250)); chk("TC018 move credited, wallet +10000, invoice partial", c in(200,201) and q(f"select status from billing_payment where id={PM}")=="credited" and bal()==b0+10000 and q(f"select status from billing_invoice where id={M}")=="partial")
c,j=a.post(f"/wallet/payments/{PM}/move/",{}); chk("TC018 move again 409 payment_not_completed", c==409 and j.get("code")=="billing.payment_not_completed", short(j))
c,j=a.post(f"/billing/payments/{PM}/refund/",{}); chk("TC018 refund credited 409 payment_credited", c==409 and j.get("code")=="billing.payment_credited", short(j))
c,j=a.delete(f"/billing/payments/{PM}/"); chk("TC018 delete credited 409 payment_credited", c==409 and j.get("code")=="billing.payment_credited", short(j))
b0=bal(); c,j=a.post(f"/wallet/payments/{PW}/move/",{}); log("move PW",c,short(j,n=200)); chk("TC018 move wallet payment credits back", c in(200,201) and bal()==b0+10000)
c,j=a.get("/billing/summary/"); rev1=[x for x in j["revenue_this_month"] if x["currency"]=="EGP"][0]["amount_minor"]; log("revenue EGP", rev0, "->", rev1, "(cash 10000 recorded then moved: expect +10000)")
c,j=a.post(f"/billing/invoices/{M}/void/",{}); chk("TC018 void M after moves", c==200, short(j,["status","code"]))
c,j=a.post(f"/wallet/payments/17/reverse/",{}); b=bal(); log("reverse 17 (50000) with balance",b,c,short(j)); chk("TC018 short balance 409 insufficient" if b<50000 else "TC018 reverse ok", (c==409 and j.get("code")=="wallet.insufficient_balance") if b<50000 else c in(200,201))
inv_pay=q("select id from billing_payment where invoice_id is not null and status='completed' and method='cash' limit 1")
c,j=a.post(f"/wallet/payments/{inv_pay}/reverse/",{}); chk("TC018 reverse invoice payment 409 not_topup", c==409 and j.get("code")=="wallet.not_topup", short(j))
for verb,path in [("POST","/billing/payments/17/refund/"),("DELETE","/billing/payments/17/"),("PATCH","/billing/payments/17/")]:
    c,j=a.req(verb,path,{"notes":"x"} if verb=="PATCH" else ({} if verb=="POST" else None)); log(verb,path,c,short(j)); chk(f"TC018 {verb} topup refused 409", c==409)
W1pay=int(q(f"select id from billing_payment where invoice_id={W1} and method='wallet'"))
for verb,path in [("POST",f"/billing/payments/{W1pay}/refund/"),("DELETE",f"/billing/payments/{W1pay}/")]:
    c,j=a.req(verb,path,{} if verb=="POST" else None); log(verb,path,c,short(j)); chk(f"TC018 {verb} wallet payment 409 billing.wallet_payment", c==409 and j.get("code")=="billing.wallet_payment")
log("dup kind,payment", q("select kind,payment_id,count(*) from wallet_walletentry where payment_id is not null group by 1,2 having count(*)>1"))
log("inv", inv_inv())
st.update(M=M,PM=PM,PW=PW); st_save(st); save("tc018.txt")
