from qa import *
st = st_load(); a = S(); a.login(*PW["admin"])
IK = ["status","paid_minor","balance_minor"]
def inv(amount, desc, cur=None, student=5, payer=None):
    b = {"student":student,"amount_minor":amount,"due_on":d(7),"description":desc}
    if cur: b["currency"]=cur
    if payer: b["payer"]=payer
    c, j = a.post("/billing/invoices/", b); assert c==201, (c,j); return j["id"]
def pay(i, amt, method="cash", paid_on=None, **kw):
    b = {"amount_minor":amt,"method":method,"paid_on":paid_on or d(0)}; b.update(kw)
    return a.post(f"/billing/invoices/{i}/payments/", b)
log("== TC-005", datetime.datetime.now().isoformat())
A = inv(50000, "TC005"); st["A"]=A
for amt, m, po, exp in [(20000,"cash",d(0),("partial",20000,30000)),(29999,"bank_transfer",d(-30),("partial",49999,1)),(1,"instapay",d(0),("paid",50000,0))]:
    c, j = pay(A, amt, m, po, reference="R1")
    log("pay", amt, m, c, short(j, IK) if isinstance(j, dict) else j)
    chk(f"TC005 after {amt}", c==201 and (j["status"],j["paid_minor"],j["balance_minor"])==exp)
c, j = a.get("/billing/invoices/?status=partial"); chk("TC005 paid not under partial", A not in [r["id"] for r in j["results"]])
log("DB", q(f"select id,amount_minor,currency,fee_minor,recorded_by_id,status,method from billing_payment where invoice_id={A}"))
chk("TC005 sum==paid", q(f"select sum(amount_minor) filter (where status='completed') from billing_payment where invoice_id={A}")=="50000")
save("tc005.txt")
log("== TC-006", datetime.datetime.now().isoformat())
B = inv(10000, "TC006 B"); V = inv(10000, "TC006 V"); st["B"]=B
for amt in [10001,0,-1,2.5,"abc"]:
    c, j = pay(B, amt); log("amount", repr(amt), c, short(j)); chk(f"TC006 amt {amt!r} 400", c==400)
for m in ["stripe","paypal","wallet","code","bitcoin"]:
    c, j = pay(B, 100, m); log("method", m, c, short(j)); chk(f"TC006 method {m} 400", c==400)
for po in [d(1), "31/12/2026"]:
    c, j = pay(B, 100, paid_on=po); log("paid_on", po, c, short(j)); chk(f"TC006 paid_on {po} 400", c==400)
c, j = pay(B, 4000); log("pay 4000", c, short(j, IK))
c, j = pay(B, 6001); log("pay 6001", c, short(j)); chk("TC006 over balance 400", c==400)
res = par([lambda: pay(B, 6000), lambda: pay(B, 6000)]); log("race", [(r[0], short(r[1], IK) if r[0]==201 else short(r[1])) for r in res])
chk("TC006 race exactly one 201", sorted(r[0] for r in res)==[201,400] or sorted(r[0] for r in res)==[201,409], str([r[0] for r in res]))
log("B DB", q(f"select sum(amount_minor),count(*) from billing_payment where invoice_id={B} and status='completed'"), q(f"select status,amount_minor from billing_invoice where id={B}"))
c, j = a.post(f"/billing/invoices/{V}/void/", {}); log("void V", c)
c, j = pay(V, 1000); log("pay void", c, short(j)); chk("TC006 void 409 billing.invoice_void", c==409 and j.get("code")=="billing.invoice_void")
chk("TC006 no payment on V", q(f"select count(*) from billing_payment where invoice_id={V}")=="0")
save("tc006.txt")
log("== TC-007", datetime.datetime.now().isoformat())
E1=inv(50000,"E1"); E2=inv(50000,"E2"); E3=inv(5000,"E3"); E4=inv(5000,"E4")
pay(E2,1000); pay(E3,5000); c,j=pay(E4,5000)
pid = q(f"select id from billing_payment where invoice_id={E4}"); c,j=a.post(f"/billing/payments/{pid}/refund/",{}); log("E4 refund", c, short(j, n=200))
c,j=a.patch(f"/billing/invoices/{E1}/",{"amount_minor":65000,"description":"edited","notes":"n","due_on":d(14)}); log("E1 edit", c, short(j,["amount_minor","description","due_on"])); chk("TC007 E1 edit 200", c==200 and j["amount_minor"]==65000)
c,j=a.patch(f"/billing/invoices/{E1}/",{"due_on":d(-1)}); log("E1 due yesterday", c, short(j)); chk("TC007 due before issue 400", c==400)
c,j=a.patch(f"/billing/invoices/{E1}/",{"amount_minor":0}); chk("TC007 amount 0 400", c==400, short(j))
c,j=a.patch(f"/billing/invoices/{E2}/",{"amount_minor":9999}); chk("TC007 E2 amount 409 has_payments", c==409 and j.get("code")=="billing.has_payments", short(j))
c,j=a.patch(f"/billing/invoices/{E2}/",{"amount_minor":50000}); chk("TC007 E2 same amount 200", c==200, short(j)[:150])
c,j=a.patch(f"/billing/invoices/{E2}/",{"description":"ok"}); chk("TC007 E2 desc 200", c==200)
for e,exp in [(E2,409),(E3,409),(E4,"?"),(E1,200)]:
    c,j=a.post(f"/billing/invoices/{e}/void/",{}); log("void",e,c,short(j,["status","code","detail"]) if isinstance(j,dict) else j)
    if exp!="?": chk(f"TC007 void {e} {exp}", c==exp)
    else: st["S1_E4_void"]=c
c,j=a.patch(f"/billing/invoices/{E1}/",{"description":"again"}); chk("TC007 edit void 409", c==409 and j.get("code")=="billing.invoice_void", short(j))
c,j=a.post(f"/billing/invoices/{E1}/void/",{}); chk("TC007 second void 409", c==409, short(j))
c,j=pay(E1,100); chk("TC007 pay void 409", c==409, short(j))
c,j=a.get("/billing/invoices/?status=void"); chk("TC007 void list has E1", E1 in [r["id"] for r in j["results"]])
c,j=a.get(f"/billing/invoices/{E1}/"); log("E1 detail", short(j, ["status","balance_minor","is_overdue"]))
log("DB", q(f"select id,status,voided_at is not null,voided_by_id,amount_minor from billing_invoice where id in ({E1},{E2},{E3},{E4})"))
st.update(E1=E1,E4=E4); save("tc007.txt")
log("== TC-008", datetime.datetime.now().isoformat())
F=inv(30000,"TC008 F"); c,j=pay(F,10000); c,j=pay(F,20000,"instapay",reference="IP-1")
Pa,Pb = q(f"select id from billing_payment where invoice_id={F} order by id").split("\n"); st.update(F=F,P_a=int(Pa),P_b=int(Pb))
c,j=a.post(f"/billing/payments/{Pb}/refund/",{}); log("refund Pb", c, short(j, n=300))
log("F", q(f"select status from billing_invoice where id={F}"), q(f"select id,status,refunded_at is not null,refunded_by_id from billing_payment where invoice_id={F}"))
chk("TC008 F partial after refund", q(f"select status from billing_invoice where id={F}")=="partial")
c,j=a.post(f"/billing/payments/{Pb}/refund/",{}); chk("TC008 second refund 409 already_refunded", c==409 and j.get("code")=="billing.already_refunded", short(j))
c,j=pay(F,20000); chk("TC008 repay 201 paid", c==201 and j["status"]=="paid", short(j,IK))
c,j=a.delete(f"/billing/payments/{Pa}/"); log("delete Pa", c); chk("TC008 delete 204 and partial", c==204 and q(f"select status from billing_invoice where id={F}")=="partial")
c,j=a.delete(f"/billing/payments/{Pa}/"); chk("TC008 delete again 404", c==404, str(c))
c,j=a.get("/billing/payments/?status=refunded"); chk("TC008 refunded list has Pb", int(Pb) in [r["id"] for r in j["results"]], str(c))
c,j=a.get("/billing/summary/"); log("summary", short(j))
st_save(st); save("tc008.txt")
