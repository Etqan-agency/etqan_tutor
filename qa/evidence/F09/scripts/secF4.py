from qa import *
st = st_load(); a = S(); a.login(*PW["admin"])
log("== TC-025", datetime.datetime.now().isoformat())
c,j=a.get("/billing/summary/"); rev0={x["currency"]:x["amount_minor"] for x in j["revenue_this_month"]}
c,j=a.post("/gateways/links/",{"kind":"payment","title":"Registration fee","student":5,"provider":"stripe","amount_minor":25000,"add_fee":True}); log("L1",c,short(j,n=500)); L1=j
c,j=a.post("/gateways/links/",{"kind":"payment","title":"Walk-in","payer_name":"Walk In","payer_email":"w@qa.etqan.test","payer_phone":"01000000000","provider":"stripe","amount_minor":10050,"add_fee":False}); log("L2",c,short(j,n=400)); L2=j
c,j=a.post("/gateways/links/",{"kind":"donation","title":"Donate","payer_name":"D","provider":"stripe","amount_minor":1000,"add_fee":False}); log("donation off",c,short(j)); chk("TC025 donation off 400/404", c in(400,404))
base={"kind":"payment","title":"x","provider":"stripe","amount_minor":1000,"add_fee":False}
for lbl,extra in [("both",{"student":5,"payer_name":"X"}),("neither",{}),("amount 0",{"student":5,"amount_minor":0}),("bad email",{"payer_name":"X","payer_email":"nope"}),("paypal EGP",{"student":5,"provider":"paypal"})]:
    b=dict(base); b.update(extra); c,j=a.post("/gateways/links/",b); log(lbl,c,short(j,n=150)); chk(f"TC025 refuse {lbl} 400", c==400)
tok1=q(f"select token from gateways_paymentlink where id={L1['id']}"); tok2=q(f"select token from gateways_paymentlink where id={L2['id']}")
log("tokens", len(tok1), tok1[:6]+"…", len(tok2)); chk("TC025 tokens 32+ chars url-safe distinct", len(tok1)>=32 and tok1!=tok2 and all(ch.isalnum() or ch in "-_" for ch in tok1))
an=anon()
c,txt=an.get(f"/gateways/pay/{tok1}/",raw=True); log("public L1",c,txt[:500])
chk("TC025 public page: no email/phone/ids, first name only", c==200 and "qa-student@" not in txt and "QA student" not in txt and '"student_id"' not in txt)
c,txt2=an.get(f"/gateways/pay/{tok2}/",raw=True); log("public L2",c,txt2[:400]); chk("TC025 public L2 no PII", "w@qa.etqan.test" not in txt2 and "01000000000" not in txt2)
for t in ["wrongtoken","A"*33,"abc%00def"]:
    c,_=an.get(f"/gateways/pay/{t}/",raw=True); log("bad token",t[:10],c); chk(f"TC025 bad token {t[:6]} 404", c==404)
codes=[an.get(f"/gateways/pay/{tok2}/",raw=True)[0] for _ in range(65)]; log("throttle 65", codes.count(200), codes.count(429)); chk("TC025 public throttle 429 appears", 429 in codes)
dc("exec","-T","django","python","manage.py","shell","-c","from django.core.cache import cache; cache.clear()")
an2=anon()
c,j=an2.post(f"/gateways/pay/{tok1}/checkout/",{}); log("L1 checkout",c,short(j,n=300)); k1=j.get("id"); chk("TC025 L1 fee 1250", j.get("fee_minor")==1250 and j.get("amount_minor")==25000)
c,j=an2.post(f"/gateways/simulate/{k1}/",{"outcome":"pay"}); log("simulate",c,short(j))
c,j=an2.post(f"/gateways/pay/{tok1}/checkout/",{}); log("pay again",c,short(j)); chk("TC025 paid link 409 link_closed", c==409 and j.get("code")=="gateways.link_closed")
log("L1 DB", q(f"select status,paid_at is not null,checkout_id from gateways_paymentlink where id={L1['id']}"))
log("L1 payment", q(f"select id,invoice_id,customer_type,student_id,customer_name,amount_minor,fee_minor,method,currency,status from billing_payment where transaction_number=(select transaction_number from gateways_checkout where id='{k1}')"))
chk("TC025 standalone payment for L1", q(f"select (invoice_id is null)::text||customer_type||amount_minor||'|'||fee_minor||method from billing_payment where transaction_number=(select transaction_number from gateways_checkout where id='{k1}')")=="truestudent25000|1250stripe")
an3=anon(); c,j=an3.post(f"/gateways/pay/{tok2}/checkout/",{}); k2=j.get("id"); log("L2 checkout",c,short(j,n=200)); chk("TC025 L2 fee 0", j.get("fee_minor")==0)
c,j=a.post(f"/gateways/links/{L2['id']}/cancel/",{}); log("cancel L2",c,short(j,["status"]))
c,j=an3.post(f"/gateways/simulate/{k2}/",{"outcome":"pay"}); log("pay after cancel",c,short(j))
log("k2", q(f"select status,applied,attention from gateways_checkout where id='{k2}'")); chk("TC025 cancelled link money -> attention link_closed", q(f"select attention from gateways_checkout where id='{k2}'")=="link_closed")
c,txt=anon().get(f"/gateways/pay/{tok2}/",raw=True); log("public cancelled",c,txt[:150])
c,j=a.get("/billing/payments/?has_invoice=false"); log("standalone list", c, j.get("count"))
c,j=a.get("/gateways/links/"); log("links", c, [(r["id"],r["status"]) for r in j.get("results",[])])
c,j=a.get("/billing/summary/"); rev1={x["currency"]:x["amount_minor"] for x in j["revenue_this_month"]}; chk("TC025 revenue +26250", rev1["EGP"]-rev0["EGP"]==26250, f"{rev0['EGP']}->{rev1['EGP']}")
st.update(L1=L1["id"],L2=L2["id"],LK1=k1); st_save(st); save("tc025.txt")
