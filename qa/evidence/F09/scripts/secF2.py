from qa import *
st = st_load(); a = S(); a.login(*PW["admin"])
def inv(amount, desc, cur=None, student=5, payer=None):
    b = {"student":student,"amount_minor":amount,"due_on":d(7),"description":desc}
    if cur: b["currency"]=cur
    if payer: b["payer"]=payer
    c, j = a.post("/billing/invoices/", b); assert c==201, (c,j); return j["id"]
par_=S(); par_.login(*PW["parent"])
def start(ref, sess=par_, prov="stripe", purpose="invoice"):
    c,j=sess.post("/gateways/checkouts/start/",{"purpose":purpose,"reference_id":ref,"provider":prov}); assert c==201,(c,j); return j["id"]
def evt(eid, typ, ck, total, cur, pi, live=False, ref=None):
    return {"id":eid,"type":typ,"livemode":live,"data":{"object":{"id":ref or f"cs_{ck[:8]}","object":"checkout.session","client_reference_id":ck,"metadata":{"checkout":ck},"payment_status":"paid","amount_total":total,"currency":cur,"payment_intent":pi}}}
def whsend(ev, secret="whsec_qa_f09", ts=None, tamper=False, header=True, host=QA):
    raw=json.dumps(ev).encode(); ts=ts or int(time.time())
    sig=hmac.new(secret.encode(), str(ts).encode()+b"."+raw, hashlib.sha256).hexdigest()
    if tamper: raw=raw.replace(b'"paid"', b'"PAID"')
    s=S(host); h={"Stripe-Signature":f"t={ts},v1={sig}"} if header else {}
    return s.req("POST","/gateways/webhooks/stripe/",raw,headers=h)
log("== TC-023", datetime.datetime.now().isoformat())
I=[inv(50000,f"WH{i}") for i in range(1,8)]; K=[start(i) for i in I]
st["WH_I"]=I; st["WH_K"]=K
e1=evt("evt_f09_1","checkout.session.completed",K[0],52500,"egp","pi_f09_1")
r1=whsend(e1); r2=whsend(e1); log("C1 x2", r1, r2)
chk("TC023 duplicate delivery one payment", q("select count(*) from billing_payment where transaction_number='pi_f09_1'")=="1" and q(f"select status from billing_invoice where id={I[0]}")=="paid")
log("C1 payment", q("select amount_minor,fee_minor,method from billing_payment where transaction_number='pi_f09_1'"))
r=whsend(evt("evt_f09_1b","checkout.session.async_payment_succeeded",K[0],52500,"egp","pi_f09_1")); log("C1 second event id", r)
chk("TC023 still one payment after 2nd event id", q(f"select count(*) from billing_payment where invoice_id={I[0]}")=="1")
log("C2 mismatch", whsend(evt("evt_f09_2","checkout.session.completed",K[1],52499,"egp","pi_f09_2")))
log("C3 currency", whsend(evt("evt_f09_3","checkout.session.completed",K[2],52500,"usd","pi_f09_3")))
log("C4 livemode", whsend(evt("evt_f09_4","checkout.session.completed",K[3],52500,"egp","pi_f09_4",live=True)))
log("C5 unknown", whsend(evt("evt_f09_5","checkout.session.completed","00000000-0000-4000-8000-000000000000",52500,"egp","pi_f09_5")))
n_ev=q("select count(*) from gateways_webhookevent")
bad=[("tampered",dict(tamper=True)),("old ts",dict(ts=int(time.time())-400)),("wrong secret",dict(secret="whsec_wrong")),("no header",dict(header=False))]
for lbl,kw in bad:
    c,j=whsend(evt(f"evt_f09_6_{lbl[:3]}","checkout.session.completed",K[4],52500,"egp","pi_f09_6"),**kw); log(lbl,c,short(j)); chk(f"TC023 {lbl} 400", c==400)
chk("TC023 bad signatures add no webhook row", q("select count(*) from gateways_webhookevent")==n_ev)
log("C1..C5 DB", q(f"select reference_id,status,applied,attention,transaction_number from gateways_checkout where id in ({','.join(repr(k) for k in K[:5])}) order by reference_id"))
for i in (1,2,3):
    chk(f"TC023 C{i+1} not applied, no payment, invoice unpaid", q(f"select applied::text||'|'||(attention<>'')::text from gateways_checkout where id='{K[i]}'")=="false|true" and q(f"select count(*) from billing_payment where invoice_id={I[i]}")=="0" and q(f"select status from billing_invoice where id={I[i]}")=="unpaid")
c,j=a.post(f"/gateways/checkouts/{K[1]}/resolve/",{}); log("resolve C2",c,short(j,n=200)); chk("TC023 resolve 200", c==200)
c,j=a.post(f"/gateways/checkouts/{K[1]}/resolve/",{}); chk("TC023 resolve again 409 nothing_to_resolve", c==409 and j.get("code")=="gateways.nothing_to_resolve", short(j))
c,j=a.post(f"/gateways/checkouts/{K[0]}/resolve/",{}); chk("TC023 resolve C1 409", c==409, short(j))
r=whsend(evt("evt_f09_7","checkout.session.completed",K[6],52500,"egp","pi_f09_1")); log("C7 reused payment_intent", r)
log("C7 DB", q(f"select status,applied,attention from gateways_checkout where id='{K[6]}'"))
chk("TC023 C7 already_recorded, no second payment", q("select count(*) from billing_payment where transaction_number='pi_f09_1'")=="1" and q(f"select attention from gateways_checkout where id='{K[6]}'")!="" )
# feature off delivery on C5 (K[4], still pending)
log(features("qa", off=["online_payments"]))
r=whsend(evt("evt_f09_8","checkout.session.completed",K[4],52500,"egp","pi_f09_8")); log("feature off delivery", r)
log(features("qa", on=["online_payments"]))
chk("TC023 feature off: webhook still records payment", q(f"select count(*) from billing_payment where invoice_id={I[4]} and transaction_number='pi_f09_8'")=="1")
c,j=a.get("/gateways/checkouts/?attention=open"); log("attention open", c, [(r["reference_id"], r.get("attention")) for r in j.get("results",[])] if isinstance(j,dict) else j)
log("webhookevent", q("select event_id,type,checkout_id is not null from gateways_webhookevent where event_id like 'evt_f09%' order by id"))
log("5xx in log", dc("logs","--since","5m","django").count(" 500 "))
st_save(st); save("tc023.txt")
