from qa import *
st = st_load(); a = S(); a.login(*PW["admin"])
log("== TC-010", datetime.datetime.now().isoformat())
RK=["id","customer","amount_minor","currency","method","status","editable","refundable","transaction_number"]
c,j=a.post("/billing/payments/",{"customer_type":"student","student":5,"amount_minor":15000,"method":"cash","transaction_number":"TN-F09-1","paid_on":d(0)}); log("R1",c,short(j,RK,500)); R1=j.get("id")
chk("TC010 R1 201 editable refundable", c==201 and j.get("editable") is True and j.get("refundable") is True)
c,j=a.post("/billing/payments/",{"customer_type":"unregistered","customer_name":"Walk In","customer_email":"walk@qa.etqan.test","amount_minor":8000,"currency":"USD","method":"western_union","paid_on":d(0)}); log("R2",c,short(j,RK,500)); R2=j.get("id")
chk("TC010 R2 201 USD", c==201 and j.get("currency")=="USD")
bad = [("unreg no name",{"customer_type":"unregistered","amount_minor":100,"method":"cash","paid_on":d(0)}),
 ("unreg with student",{"customer_type":"unregistered","customer_name":"X","student":5,"amount_minor":100,"method":"cash","paid_on":d(0)}),
 ("student none",{"customer_type":"student","amount_minor":100,"method":"cash","paid_on":d(0)}),
 ("method stripe",{"customer_type":"student","student":5,"amount_minor":100,"method":"stripe","paid_on":d(0)}),
 ("dup txn",{"customer_type":"student","student":5,"amount_minor":100,"method":"cash","transaction_number":"TN-F09-1","paid_on":d(0)}),
 ("amount 0",{"customer_type":"student","student":5,"amount_minor":0,"method":"cash","paid_on":d(0)}),
 ("future",{"customer_type":"student","student":5,"amount_minor":100,"method":"cash","paid_on":d(1)}),
 ("bad email",{"customer_type":"unregistered","customer_name":"X","customer_email":"not-an-email","amount_minor":100,"method":"cash","paid_on":d(0)})]
for n,b in bad:
    c,j=a.post("/billing/payments/",b); log(n,c,short(j,n=200)); chk(f"TC010 {n} 400", c==400)
c,j=a.patch(f"/billing/payments/{R1}/",{"amount_minor":16000,"notes":"corrected"}); chk("TC010 patch R1 200", c==200 and j.get("amount_minor")==16000, short(j,RK))
c,j=a.patch(f"/billing/payments/{st['P_b']}/",{"notes":"x"}); chk("TC010 patch refunded 409 not_editable", c==409 and j.get("code")=="billing.payment_not_editable", short(j))
c,j=a.patch(f"/billing/payments/{st['P_b']+0}/",{"notes":"x"})
inv_pay = q(f"select id from billing_payment where invoice_id={st['F']} and status='completed' limit 1")
c,j=a.patch(f"/billing/payments/{inv_pay}/",{"notes":"x"}); chk("TC010 patch invoice payment 409", c==409 and j.get("code")=="billing.payment_not_editable", short(j))
c,j=a.post(f"/billing/payments/{R1}/refund/",{}); chk("TC010 refund R1", c==200 and q(f"select status from billing_payment where id={R1}")=="refunded", short(j,RK))
c,j=a.patch(f"/billing/payments/{R1}/",{"notes":"y"}); chk("TC010 patch refunded R1 409", c==409, short(j))
c,j=a.delete(f"/billing/payments/{R2}/"); chk("TC010 delete R2 204", c==204, str(c))
c,j=a.post("/billing/payments/",{"customer_type":"unregistered","customer_name":"Walk In 2","amount_minor":8000,"currency":"USD","method":"western_union","paid_on":d(0)}); R3=j.get("id"); log("R3 USD kept",c)
log(features("qa", off=["payment_receipts"]))
c,j=a.get("/billing/payments/"); chk("TC010 list off 404", c==404, str(c))
c,j=a.post("/billing/payments/",{"customer_type":"student","student":5,"amount_minor":100,"method":"cash","paid_on":d(0)}); chk("TC010 post off 404", c==404, str(c))
c,j=a.delete(f"/billing/payments/{inv_pay}/"); log("delete invoice payment with receipts off", c, short(j)); chk("TC010 delete invoice payment still works", c==204)
log(features("qa", on=["payment_receipts"]))
log("DB standalone", q("select id,invoice_id,customer_type,student_id,customer_name,amount_minor,currency,method,transaction_number,status from billing_payment where invoice_id is null order by id"))
log("dup (method,txn)", q("select method,transaction_number,count(*) from billing_payment where transaction_number<>'' group by 1,2 having count(*)>1"))
c,j=a.get("/billing/summary/"); log("summary", short(j))
st.update(R1=R1,R3=R3); st_save(st); save("tc010.txt")
log("== TC-011", datetime.datetime.now().isoformat())
c,j=a.put("/billing/local-countries/EG/",{"enabled":True}); log("EG",c,short(j))
c,j=a.put("/billing/local-countries/XX1/",{"enabled":True}); log("XX1",c,short(j,n=100))
c,j=a.put("/billing/local-countries/eg/",{"enabled":True}); log("eg",c,short(j,n=150))
import uuid
def mp(fields):
    bnd = uuid.uuid4().hex; body = b""
    for k,v in fields.items(): body += f"--{bnd}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n{v}\r\n".encode()
    body += f"--{bnd}--\r\n".encode()
    return a.req("POST","/billing/local-methods/",body,headers={"Content-Type":f"multipart/form-data; boundary={bnd}"})
c,j=mp({"country":"EG","name":"Vodafone Cash","instructions":"Send to 0100 <script>alert(1)</script>","currency":"EGP"}); log("m1",c,short(j,n=300)); M1=j.get("id") if isinstance(j,dict) else None
c,j=mp({"country":"EG","name":"USD Method","instructions":"usd","currency":"USD"}); log("m2",c,short(j,n=200)); M2=j.get("id") if isinstance(j,dict) else None
c,j=mp({"country":"EG","name":"","instructions":"x","currency":"EGP"}); chk("TC011 empty name 400", c==400, short(j))
stu=S(); stu.login(*PW["student"])
I=st["INV1"]
c,j=stu.get(f"/billing/invoices/{I}/"); lm=j.get("local_methods"); log("student sees local_methods", c, short(lm,n=400))
chk("TC011 EGP method shown, USD not", isinstance(lm,list) and any(m.get("name")=="Vodafone Cash" for m in lm) and not any(m.get("name")=="USD Method" for m in lm))
chk("TC011 instructions plain text", isinstance(lm,list) and any("<script>" in (m.get("instructions") or "") for m in lm))
a.patch("/billing/settings/",{"local_payment_enabled":False}); c,j=stu.get(f"/billing/invoices/{I}/"); chk("TC011 setting off -> none", j.get("local_methods")==[], short(j.get("local_methods")))
a.patch("/billing/settings/",{"local_payment_enabled":True}); a.put("/billing/local-countries/EG/",{"enabled":False}); c,j=stu.get(f"/billing/invoices/{I}/"); chk("TC011 country off -> none", j.get("local_methods")==[], short(j.get("local_methods")))
a.put("/billing/local-countries/EG/",{"enabled":True})
c,j=stu.get(f"/billing/invoices/{st['A']}/"); chk("TC011 paid invoice -> none", j.get("local_methods")==[], short(j.get("local_methods")))
log("DB", q("select id,country,name,currency from billing_localpaymentmethod"), q("select * from billing_localpaymentcountry"))
for m in [M1,M2]:
    if m: log("delete method", m, a.delete(f"/billing/local-methods/{m}/")[0])
st_save(st); save("tc011.txt")
