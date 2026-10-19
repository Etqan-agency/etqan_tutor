from qa import *
st = st_load(); a = S(); a.login(*PW["admin"]); o = oadmin()
QS="academy_qaother"
log("== TC-014", datetime.datetime.now().isoformat())
ex=q("select id from identity_user where email='qo-student@qa.etqan.test'",QS)
if not ex:
    c,j=o.post("/people/students/",{"user":{"full_name":"QO Student","email":"qo-student@qa.etqan.test"}}); log("qo student",c,short(j,n=120)); OS=j["id"]
else: OS=int(ex)
c,j=o.post("/billing/invoices/",{"student":OS,"amount_minor":5000,"due_on":d(7),"description":"OI","currency":"USD"}); log("OI",c,short(j,["id","number","currency"])); OI=j["id"]
c,j=o.post(f"/billing/invoices/{OI}/payments/",{"amount_minor":1000,"method":"cash","paid_on":d(0)}); OP=int(q(f"select max(id) from billing_payment where invoice_id={OI}",QS))
c,j=o.post(f"/wallet/students/{OS}/top-ups/",{"amount_minor":3000,"currency":"USD","method":"cash"}); log("qo topup",c)
c,j=o.post("/vouchers/batches/",{"kind":"discount","quantity":1,"valid_days":30,"discount_kind":"percent","discount_value":10}); OV=int(q("select max(id) from vouchers_voucher",QS)); OVC=q(f"select code from vouchers_voucher where id={OV}",QS)
c,j=o.patch("/gateways/settings/",{"stripe":{"enabled":True,"mode":"test","public_key":"pk_test_qo","secret":"sk_test_qo","webhook_secret":"REDACTED-QA"}}); log("qo gw",c)
OI2=o.post("/billing/invoices/",{"student":OS,"amount_minor":2000,"due_on":d(7),"description":"OI2","currency":"USD"})[1]["id"]
c,j=o.post("/gateways/checkouts/start/",{"purpose":"invoice","reference_id":OI2,"provider":"stripe"}); log("qo checkout (admin start)",c,short(j,n=120)); OK_=j.get("id")
c,j=o.post("/gateways/links/",{"kind":"payment","title":"qo link","student":OS,"provider":"stripe","amount_minor":1000,"add_fee":False}); OL=j.get("id"); log("qo link",c)
cnt=lambda: (q("select count(*) from billing_payment"), q("select count(*) from billing_payment",QS), q("select count(*)||':'||max(status) from gateways_checkout"), q("select count(*) from gateways_webhookevent"))
c0=cnt(); log("counts", c0)
# collisions: some ids exist in both schemas; check what qa's row is for the same id
log("same ids in qa?", q(f"select id,number,currency from billing_invoice where id in ({OI},{OI2})"))
qa_inv_ids=set(q("select id from billing_invoice").split("\n"))
calls=[("GET",f"/billing/invoices/{OI}/",None),("PATCH",f"/billing/invoices/{OI}/",{"description":"hijack"}),("POST",f"/billing/invoices/{OI}/payments/",{"amount_minor":1,"method":"cash","paid_on":d(0)}),
 ("POST",f"/billing/invoices/{OI}/void/",{}),("GET",f"/billing/payments/{OP}/",None),("POST",f"/billing/payments/{OP}/refund/",{}),
 ("GET",f"/wallet/students/{OS}/",None),("POST",f"/wallet/invoices/{OI}/pay/",{}),("POST",f"/vouchers/codes/{OV}/void/",{"reason":"x"}),
 ("GET",f"/gateways/checkouts/{OK_}/",None),("POST",f"/gateways/simulate/{OK_}/",{"outcome":"pay"}),("GET",f"/gateways/links/{OL}/",None)]
log("-- qa admin -> qaother ids (note: an id that also exists in qa resolves to qa's own row)")
for m,p,b in calls:
    c,j=a.req(m,p,b); log(m,p,c,short(j,["number","currency","description","status"],150) if isinstance(j,dict) else "")
    if c==200 and isinstance(j,dict) and j.get("description")=="OI": log("BAD qa sees qaother data")
log("qaother OI unchanged", q(f"select description,status from billing_invoice where id={OI}",QS))
chk("TC014 qaother OI untouched by qa admin", q(f"select description from billing_invoice where id={OI}",QS)=="OI")
chk("TC014 qaother checkout not completed by qa simulate", q(f"select status from gateways_checkout where id='{OK_}'",QS)=="pending")
log("-- qaother admin -> qa ids")
INV1=st["INV1"]; K1=st["K1"]
for m,p,b in [("GET",f"/billing/invoices/{INV1}/",None),("GET",f"/billing/payments/{st['PS']}/",None),("GET",f"/gateways/checkouts/{K1}/",None),("GET","/wallet/students/5/",None),("POST",f"/gateways/simulate/{st['K6']}/",{"outcome":"pay"})]:
    c,j=o.req(m,p,b); log(m,p,c,short(j,["number","description","status"],150) if isinstance(j,dict) else "")
    if c==200 and isinstance(j,dict) and j.get("description") in ("Tajweed - October",): log("BAD qaother sees qa data")
chk("TC014 qa checkout UUID 404 on qaother", o.get(f"/gateways/checkouts/{K1}/")[0]==404)
chk("TC014 qa checkout uuid unknown to qaother simulate", o.post(f"/gateways/simulate/{st['K6']}/",{"outcome":"pay"})[0]==404)
# code redemption across
dc("exec","-T","django","python","manage.py","shell","-c","from django.core.cache import cache; cache.clear()")
qa_code=q("select code from vouchers_voucher where status='unused' limit 1")
c,j=o.post("/vouchers/codes/redeem/",{"code":qa_code,"invoice":OI}); log("qa code on qaother office",c,short(j)); chk("TC014 qa code invalid on qaother", c in(400,404) and "used" not in str(j))
c,j=a.post("/vouchers/codes/redeem/",{"code":OVC,"invoice":INV1}); log("qaother code on qa office",c,short(j)); chk("TC014 qaother code invalid on qa", c in(400,404))
# webhook cross
def whsend(ev, secret, host):
    raw=json.dumps(ev).encode(); ts=int(time.time()); sig=hmac.new(secret.encode(), str(ts).encode()+b"."+raw, hashlib.sha256).hexdigest()
    return S(host).req("POST","/gateways/webhooks/stripe/",raw,headers={"Stripe-Signature":f"t={ts},v1={sig}"})
qk=st["WH_K"][5]  # a pending qa checkout
log("qa pending checkout", qk, q(f"select status from gateways_checkout where id='{qk}'"))
ev={"id":"evt_f09_x1","type":"checkout.session.completed","livemode":False,"data":{"object":{"id":"cs_x","client_reference_id":qk,"metadata":{"checkout":qk},"payment_status":"paid","amount_total":52500,"currency":"egp","payment_intent":"pi_x1"}}}
r1=whsend(ev,"whsec_qa_f09",QO); r2=whsend(dict(ev,id="evt_f09_x2"),"REDACTED-QA",QO); r3=whsend(dict(ev,id="evt_f09_x3"),"REDACTED-QA",QA)
log("qa event w/ qa secret -> qaother", r1, "| qa event w/ qaother secret -> qaother", r2, "| w/ qaother secret -> qa", r3)
chk("TC014 cross webhook never completes qa checkout", q(f"select status from gateways_checkout where id='{qk}'")=="pending" and q("select count(*) from gateways_webhookevent where event_id like 'evt_f09_x%'")=="0")
log("qaother webhookevent rows", q("select event_id,checkout_id from gateways_webhookevent where event_id like 'evt_f09_x%'",QS))
# session reuse
s=S(); s.login(*PW["admin"])
cookie=[c for c in s.cj if c.name=="sessionid"]; log("session cookie domain", [(c.name,c.domain) for c in s.cj])
import urllib.request as U
r=U.Request(f"{QO}/api/v1/billing/invoices/"); r.add_header("Cookie","; ".join(f"{c.name}={c.value}" for c in s.cj))
try: code=U.urlopen(r).status
except Exception as e: code=getattr(e,"code",str(e))
log("qa session on qaother", code); chk("TC014 qa session refused on qaother", code in (401,403))
c,j=a.get("/billing/summary/"); log("qa summary", short(j)); c,j=o.get("/billing/summary/"); log("qaother summary", short(j))
c1=cnt(); log("counts after", c1)
chk("TC014 qa payments unchanged by cross calls", c0[0]==c1[0]); chk("TC014 qaother payments unchanged", c0[1]==c1[1]); chk("TC014 qa webhookevent unchanged", c0[3]==c1[3])
st.update(OI=OI,OS=OS); st_save(st); save("tc014.txt")
