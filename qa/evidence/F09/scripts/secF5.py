from qa import *
st = st_load(); a = S(); a.login(*PW["admin"])
def inv(amount, desc, cur=None, student=5, payer=None):
    b = {"student":student,"amount_minor":amount,"due_on":d(7),"description":desc}
    if cur: b["currency"]=cur
    c, j = a.post("/billing/invoices/", b); assert c==201, (c,j); return j["id"]
def bal(cur="EGP"): return int(q(f"select coalesce(max(balance_minor),0) from wallet_wallet where student_id=1 and currency='{cur}'"))
def evt(eid, typ, ck, total, cur, pi):
    return {"id":eid,"type":typ,"livemode":False,"data":{"object":{"id":f"cs_{ck[:8]}","object":"checkout.session","client_reference_id":ck,"metadata":{"checkout":ck},"payment_status":"paid","amount_total":total,"currency":cur,"payment_intent":pi}}}
def whsend(ev, secret="whsec_qa_f09"):
    raw=json.dumps(ev).encode(); ts=int(time.time()); sig=hmac.new(secret.encode(), str(ts).encode()+b"."+raw, hashlib.sha256).hexdigest()
    return S().req("POST","/gateways/webhooks/stripe/",raw,headers={"Stripe-Signature":f"t={ts},v1={sig}"})
par_=S(); par_.login(*PW["parent"]); stu=S(); stu.login(*PW["student"]); p2=S(); p2.login(*PW["parent2"])
log("== TC-026", datetime.datetime.now().isoformat())
c,j=a.get("/billing/summary/"); rev0={x["currency"]:x["amount_minor"] for x in j["revenue_this_month"]}
c,j=par_.get("/wallet/top-ups/options/?student=5&currency=EGP&amount_minor=10000"); log("options",c,short(j,n=400))
T={"student":5,"amount_minor":10000,"currency":"EGP","provider":"stripe"}
c,j=par_.post("/wallet/top-ups/",T); log("start",c,short(j,n=300)); k=j.get("id"); chk("TC026 checkout 10000 fee 500", j.get("amount_minor")==10000 and j.get("fee_minor")==500)
c,j2=par_.post("/wallet/top-ups/",T); log("restart",c,short(j2,["id"])); log("reuse?", j2.get("id")==k)
b0=bal(); c,j=par_.post(f"/gateways/simulate/{k}/",{"outcome":"pay"}); log("sim",c,short(j))
txn=q(f"select transaction_number from gateways_checkout where id='{k}'")
log("topup row", q("select id,amount_minor,currency,status from wallet_topup order by id desc limit 2"))
log("payment", q(f"select id,amount_minor,fee_minor,method,wallet_topup,invoice_id from billing_payment where transaction_number='{txn}'"))
log("entry", q(f"select kind,amount_minor from wallet_walletentry where payment_id=(select id from billing_payment where transaction_number='{txn}')"))
chk("TC026 balance +10000 only (fee not credited)", bal()-b0==10000, f"{b0}->{bal()}")
chk("TC026 payment 10000+500 wallet_topup stripe", q(f"select amount_minor||'|'||fee_minor||'|'||method||'|'||wallet_topup from billing_payment where transaction_number='{txn}'")=="10000|500|stripe|true")
b1=bal(); e=evt("evt_f09_tu1","checkout.session.completed",k,10500,"egp",txn); log("dup webhook", whsend(e), whsend(e)); chk("TC026 duplicate delivery no change", bal()==b1 and q(f"select count(*) from billing_payment where transaction_number='{txn}'")=="1")
for lbl,extra,sess in [("amt 0",{"amount_minor":0},par_),("amt max+1",{"amount_minor":100000001},par_),("amt 1.5",{"amount_minor":1.5},par_),("JPY",{"currency":"JPY"},par_),("S2",{"student":st["S2"]},par_),("paypal",{"provider":"paypal"},par_),("unknown provider",{"provider":"nope"},par_),("parent2 for S1",{},p2)]:
    b=dict(T); b.update(extra); c,j=sess.post("/wallet/top-ups/",b); log(lbl,c,short(j,n=150)); chk(f"TC026 refuse {lbl} 4xx", 400<=c<500)
c,j=par_.post("/wallet/top-ups/",dict(T,amount_minor=7000)); k2=j.get("id"); log("pending k2",c)
log(features("qa", off=["balances"]))
b2=bal(); c,j=par_.post(f"/gateways/simulate/{k2}/",{"outcome":"pay"}); log("sim with balances off",c,short(j))
log(features("qa", on=["balances"]))
chk("TC026 balances off: money still credited", bal()-b2==7000, f"{b2}->{bal()}")
c,j=a.get("/billing/summary/"); rev1={x["currency"]:x["amount_minor"] for x in j["revenue_this_month"]}; chk("TC026 revenue +10500+7350", rev1["EGP"]-rev0["EGP"]==17850, f"{rev0['EGP']}->{rev1['EGP']}")
pid=int(q(f"select id from billing_payment where transaction_number='{txn}'"))
c,j=a.post(f"/wallet/payments/{pid}/reverse/",{}); log("reverse online topup",c,short(j,n=150))
c,j=a.get("/billing/summary/"); rev2={x["currency"]:x["amount_minor"] for x in j["revenue_this_month"]}; chk("TC026 reversal removes amount+fee 10500 from revenue", rev1["EGP"]-rev2["EGP"]==10500, f"{rev1['EGP']}->{rev2['EGP']}")
log("ledger inv", q("select w.currency,w.balance_minor,(select sum(amount_minor) from wallet_walletentry e where e.wallet_id=w.id) from wallet_wallet w"))
save("tc026.txt")
log("== TC-027", datetime.datetime.now().isoformat())
c,j=a.patch("/gateways/settings/",{"paypal":{"enabled":True,"mode":"test","client_id":"cid_f09","secret":"sec_f09","webhook_id":"WH-F09","currency":"USD"}}); log("paypal save",c,short(j.get("paypal") if isinstance(j,dict) else j,n=300))
U=inv(5000,"USD pp",cur="USD"); E=inv(5000,"EGP pp")
c,j=par_.get(f"/billing/invoices/{U}/"); log("USD can_pay_online", j.get("can_pay_online")); chk("TC027 USD offers stripe+paypal", set(j.get("can_pay_online") or [])=={"stripe","paypal"})
c,j=par_.get(f"/billing/invoices/{E}/"); log("EGP can_pay_online", j.get("can_pay_online")); chk("TC027 EGP offers stripe only", j.get("can_pay_online")==["stripe"])
c,j=par_.post("/gateways/checkouts/start/",{"purpose":"invoice","reference_id":E,"provider":"paypal"}); chk("TC027 paypal EGP 400", c==400, short(j))
c,j=par_.post("/gateways/checkouts/start/",{"purpose":"invoice","reference_id":U,"provider":"paypal"}); log("paypal start",c,short(j,n=300)); kp=j.get("id")
c,j=par_.post(f"/gateways/simulate/{kp}/",{"outcome":"pay"}); log("sim",c,short(j))
log("pp payment", q(f"select method,amount_minor,fee_minor,currency,transaction_number from billing_payment where invoice_id={U}"))
chk("TC027 paypal payment CAP-SIM, invoice paid", q(f"select status from billing_invoice where id={U}")=="paid" and q(f"select method||'|'||left(transaction_number,8) from billing_payment where invoice_id={U}")=="paypal|CAP-SIM-")
U2=inv(3000,"USD pp2",cur="USD"); c,j=par_.post("/gateways/checkouts/start/",{"purpose":"invoice","reference_id":U2,"provider":"paypal"}); kf=j.get("id")
log("fail", par_.post(f"/gateways/simulate/{kf}/",{"outcome":"fail"}), "expire", par_.post(f"/gateways/simulate/{kf}/",{"outcome":"expire"}), q(f"select status from gateways_checkout where id='{kf}'"))
KW=inv(12345,"KWD",cur="KWD"); c,j=par_.get(f"/billing/invoices/{KW}/"); log("KWD can_pay_online", j.get("can_pay_online"))
c,j=par_.post("/gateways/checkouts/start/",{"purpose":"invoice","reference_id":KW,"provider":"stripe"}); log("KWD start",c,short(j,["amount_minor","fee_minor"])); 
if c==201: chk("TC027 KWD total multiple of 10", (j["amount_minor"]+j["fee_minor"])%10==0, str(j["amount_minor"]+j["fee_minor"]))
a.patch("/gateways/settings/",{"fee":{"enabled":False}})
KW2=inv(12345,"KWD nofee",cur="KWD"); c,j=par_.get(f"/billing/invoices/{KW2}/"); log("S6 KWD fee off can_pay_online", j.get("can_pay_online")); st["S6"]=j.get("can_pay_online")
a.patch("/gateways/settings/",{"fee":{"enabled":True,"basis_points":500}})
c,j=a.patch("/gateways/settings/",{"paypal":{"enabled":False}}); log("paypal disabled",c)
st.update(KW=KW,KW2=KW2); st_save(st); save("tc027.txt")
