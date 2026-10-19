from qa import *
st = st_load(); a = S(); a.login(*PW["admin"])
def inv(amount, desc, cur=None, student=5, payer=None):
    b = {"student":student,"amount_minor":amount,"due_on":d(7),"description":desc}
    if cur: b["currency"]=cur
    if payer: b["payer"]=payer
    c, j = a.post("/billing/invoices/", b); assert c==201, (c,j); return j["id"]
par_=S(); par_.login(*PW["parent"]); stu=S(); stu.login(*PW["student"])
def start(ref, sess=par_):
    c,j=sess.post("/gateways/checkouts/start/",{"purpose":"invoice","reference_id":ref,"provider":"stripe"}); log("start",ref,c,short(j,["id","amount_minor","fee_minor"])); return j.get("id")
def sim(k, outcome="pay"): c,j=par_.post(f"/gateways/simulate/{k}/",{"outcome":outcome}); return c,j
def ck(k): return q(f"select status,applied,attention,amount_minor from gateways_checkout where id='{k}'")
def ist(i): return q(f"select status,(select coalesce(sum(amount_minor),0) from billing_payment p where p.invoice_id=i.id and p.status='completed') from billing_invoice i where id={i}")
log("== TC-024", datetime.datetime.now().isoformat())
X1=inv(50000,"X1"); K1=start(X1); a.post(f"/billing/invoices/{X1}/payments/",{"amount_minor":20000,"method":"cash","paid_on":d(0)}); log("sim",sim(K1)); log("K1",ck(K1),"X1",ist(X1))
chk("TC024/S3 stale checkout after manual payment: completed, not applied, balance_below_amount, invoice partial 20000", ck(K1)=="completed|f|balance_below_amount|50000" and ist(X1)=="partial|20000")
X2=inv(50000,"X2"); K2=start(X2); a.post(f"/billing/invoices/{X2}/void/",{}); log("sim",sim(K2)); log("K2",ck(K2)); chk("TC024 voided invoice: attention invoice_void, no payment", ck(K2).endswith("|f|invoice_void|50000") and q(f"select count(*) from billing_payment where invoice_id={X2}")=="0")
X3=inv(50000,"X3"); K3=start(X3,par_); K4=start(X3,stu); log("K3==K4?", K3==K4)
log("sim3",sim(K3)); 
c,j=stu.post(f"/gateways/simulate/{K4}/",{"outcome":"pay"}); log("sim4",c,short(j)); log("K3",ck(K3),"K4",ck(K4),"X3",ist(X3))
chk("TC024/S11 two payers: invoice paid exactly once, never overpaid", ist(X3)=="paid|50000")
X4=inv(50000,"X4"); K5=start(X4); a.patch(f"/billing/invoices/{X4}/",{"amount_minor":80000}); log("sim",sim(K5)); log("K5",ck(K5),"X4",ist(X4))
chk("TC024 raised amount: old amount recorded as partial", ist(X4)=="partial|50000")
X5=inv(50000,"X5"); K6=start(X5); a.patch(f"/billing/invoices/{X5}/",{"amount_minor":30000}); log("sim",sim(K6)); log("K6",ck(K6),"X5",ist(X5))
chk("TC024/S3 reduced amount: balance_below_amount, invoice unpaid, money held", ck(K6).startswith("completed|f|balance_below_amount") and ist(X5)=="unpaid|0")
X6=inv(5000,"X6"); K7=start(X6); log("fail",sim(K7,"fail"), ck(K7)); log("pay after fail", sim(K7), ck(K7), ist(X6))
chk("TC024 failed then pay completes (documented)", ck(K7).startswith("completed|t") and ist(X6)=="paid|5000")
X7=inv(5000,"X7"); K8=start(X7); log("expire",sim(K8,"expire"), ck(K8)); chk("TC024 expire -> expired", ck(K8).startswith("expired"))
# online refund S4
PS=st["PS"]; O1=st["O1"]
c,j=a.post(f"/billing/payments/{PS}/refund/",{}); log("refund stripe",c,short(j,["status","paid_minor","balance_minor"]))
chk("TC024/S4 refund stripe marks refunded, invoice reopens", q(f"select status from billing_payment where id={PS}")=="refunded" and ist(O1)=="unpaid|0")
log("django log for provider call (expect none)", [l for l in dc("logs","--since","2m","django").splitlines() if "stripe.com" in l or "api.stripe" in l][:3])
c,j=a.delete(f"/billing/payments/{PS}/"); chk("TC024 delete online payment 409 billing.online_payment", c==409 and j.get("code")=="billing.online_payment", short(j))
K9=start(O1); log("repay", sim(K9), ist(O1)); chk("TC024 re-pay works, original checkout stays completed/applied", ist(O1)=="paid|50000" and ck(st["K1"]).startswith("completed|t"))
c,j=par_.post(f"/gateways/checkouts/{K9}/cancel/",{}); log("cancel stripe checkout (PayPal route)",c,short(j)); chk("TC024 cancel on stripe checkout 4xx not 500", 400<=c<500)
c,j=a.post(f"/gateways/checkouts/{K9}/cancel/",{}); log("cancel as admin",c,short(j))
log("limbo rows", q("select id,reference_id,attention,amount_minor+fee_minor from gateways_checkout where attention<>'' and resolved_at is null"))
log("overpay check", q("select i.id,i.amount_minor,sum(p.amount_minor) from billing_invoice i join billing_payment p on p.invoice_id=i.id and p.status='completed' group by 1,2 having sum(p.amount_minor)>i.amount_minor"))
c,j=a.get("/gateways/checkouts/?attention=open"); log("S2 dashboard list attention open", c, j.get("count"))
st.update(X5=X5,K6=K6); st_save(st); save("tc024.txt")
