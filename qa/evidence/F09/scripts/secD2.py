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
log("== TC-018 step 3a (reverse MAX top-up first)", datetime.datetime.now().isoformat())
c,j=a.post("/wallet/payments/19/reverse/",{}); log("reverse PT=19",c,short(j,n=300)); chk("TC018 reverse top-up ok", c in (200,201) and q("select status from billing_payment where id=19")=="refunded")
c,j=a.post("/wallet/payments/19/reverse/",{}); log("reverse again (balance now < amount) -> S8 probe",c,short(j)); st["S8_code"]=j.get("code") if isinstance(j,dict) else None
log("== TC-016 overdraw retry", datetime.datetime.now().isoformat())
b=bal(); c,j=a.post("/wallet/students/5/adjustments/",{"amount_minor":-(b+1),"currency":"EGP","reason":"over"}); chk("TC016 overdraw 409 insufficient, balance unchanged", c==409 and j.get("code")=="wallet.insufficient_balance" and bal()==b, short(j)+f" bal {b}")
save("tc016.txt")
log("== TC-017", datetime.datetime.now().isoformat())
log("start EGP", bal(), "USD", bal("USD"))
W1=inv(30000,"W1"); W2=inv(80000,"W2"); W3=inv(4000,"W3",cur="USD"); WV=inv(1000,"WV"); a.post(f"/billing/invoices/{WV}/void/",{}); WP=inv(1000,"WP"); a.post(f"/billing/invoices/{WP}/payments/",{"amount_minor":1000,"method":"cash","paid_on":d(0)})
S2I=inv(5000,"S2 inv",student=st["S2"])
par_=S(); par_.login(*PW["parent"]); stu=S(); stu.login(*PW["student"]); p3=S(); p3.login(*PW["parent3"])
b0=bal(); c,j=par_.post(f"/wallet/invoices/{W1}/pay/",{}); log("parent W1 default",c,short(j,IK) if c in(200,201) else short(j))
chk("TC017 W1 paid by wallet, spent 30000", c in (200,201) and j.get("status")=="paid" and bal()==b0-30000, f"bal {b0}->{bal()}")
log("W1 payment", q(f"select id,method,amount_minor,fee_minor,status from billing_payment where invoice_id={W1}"))
b0=bal(); c,j=stu.post(f"/wallet/invoices/{W2}/pay/",{"amount_minor":10000}); chk("TC017 W2 partial 10000", c in (200,201) and j.get("status")=="partial" and bal()==b0-10000, short(j,IK))
for v in [9999999999, 0, 1.5, 9223372036854775807, 99999999999999999999]:
    c,j=stu.post(f"/wallet/invoices/{W2}/pay/",{"amount_minor":v}); log("W2 amt",v,c,short(j,n=150)); chk(f"TC017 W2 amt {v} 4xx", c in (400,409))
c,j=stu.post(f"/wallet/invoices/{W3}/pay/",{}); log("W3 USD",c,short(j,IK) if c in(200,201) else short(j)); chk("TC017 W3 spends 2500 USD partial", c in(200,201) and j.get("paid_minor")==2500 and j.get("status")=="partial")
c,j=stu.post(f"/wallet/invoices/{W3}/pay/",{}); chk("TC017 W3 no USD funds 409", c==409, short(j))
c,j=stu.post(f"/wallet/invoices/{WV}/pay/",{}); chk("TC017 void 409", c==409, short(j))
c,j=stu.post(f"/wallet/invoices/{WP}/pay/",{}); chk("TC017 paid 409", c==409, short(j))
c,j=par_.post(f"/wallet/invoices/{S2I}/pay/",{}); chk("TC017 other family (parent) 404", c==404, short(j,n=100))
c,j=stu.post(f"/wallet/invoices/{S2I}/pay/",{}); chk("TC017 other family (student) 404", c==404, short(j,n=100))
INV_P3=inv(2000,"INV_P3",payer=st["P3"]); st["INV_P3"]=INV_P3
c,j=p3.get(f"/billing/invoices/{INV_P3}/"); log("P3 sees INV_P3", c)
c,j=p3.post(f"/wallet/invoices/{INV_P3}/pay/",{}); log("P3 wallet pay",c,short(j,IK) if c in(200,201) else short(j)); chk("TC017 sibling payer wallet pay 404", c==404)
# races
a.post("/wallet/students/5/top-ups/",{"amount_minor":10000,"currency":"EGP","method":"cash"})
# bring balance to exactly 10000 via adjustment
b=bal(); 
if b>10000: a.post("/wallet/students/5/adjustments/",{"amount_minor":-(b-10000),"currency":"EGP","reason":"race prep"})
log("race prep bal", bal())
R1i=inv(10000,"race1"); R2i=inv(10000,"race2")
res=par([lambda: stu.post(f"/wallet/invoices/{R1i}/pay/",{}), lambda: par_.post(f"/wallet/invoices/{R2i}/pay/",{})])
log("race diff invoices", [(r[0], short(r[1],IK) if r[0] in (200,201) else short(r[1])) for r in res]); chk("TC017 race two invoices: balance never negative, spent<=10000", bal()>=0 and bal()==10000-sum(r[1].get("paid_minor",0) for r in res if r[0] in(200,201)), f"bal {bal()}")
a.post("/wallet/students/5/top-ups/",{"amount_minor":20000,"currency":"EGP","method":"cash"})
R3i=inv(10000,"race3")
res=par([lambda: stu.post(f"/wallet/invoices/{R3i}/pay/",{}), lambda: par_.post(f"/wallet/invoices/{R3i}/pay/",{})])
log("race same invoice", [(r[0], short(r[1],IK) if r[0] in (200,201) else short(r[1])) for r in res])
chk("TC017 race same invoice paid <= amount", q(f"select coalesce(sum(amount_minor),0) from billing_payment where invoice_id={R3i} and status='completed'")=="10000", q(f"select count(*) from billing_payment where invoice_id={R3i}"))
b0=bal(); c,j=a.post(f"/wallet/invoices/{W2}/pay/",{"amount_minor":5000}); log("admin pays W2",c,short(j,IK) if c in(200,201) else short(j)); chk("TC017 admin wallet pay", c in(200,201) and bal()==b0-5000)
log("entries", q("select id,kind,amount_minor,balance_after_minor,payment_id,invoice_id from wallet_walletentry order by id"))
log("spend payments", q("select e.id,p.id,p.method,p.amount_minor from wallet_walletentry e left join billing_payment p on p.id=e.payment_id where e.kind='spend'"))
log("inv", inv_inv())
st.update(W1=W1,W2=W2,W3=W3); st_save(st); save("tc017.txt")
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
