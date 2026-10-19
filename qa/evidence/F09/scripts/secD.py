from qa import *
st = st_load(); a = S(); a.login(*PW["admin"])
def inv(amount, desc, cur=None, student=5, payer=None):
    b = {"student":student,"amount_minor":amount,"due_on":d(7),"description":desc}
    if cur: b["currency"]=cur
    if payer: b["payer"]=payer
    c, j = a.post("/billing/invoices/", b); assert c==201, (c,j); return j["id"]
def inv_inv():
    return q("select w.id,w.currency,w.balance_minor,(select coalesce(sum(amount_minor),0) from wallet_walletentry e where e.wallet_id=w.id) from wallet_wallet w order by id")
log("== TC-015", datetime.datetime.now().isoformat())
T="/wallet/students/5/top-ups/"
c,j=a.post(T,{"amount_minor":50000,"currency":"EGP","method":"cash","reference":"T1"}); log("T1",c,short(j,n=400)); 
chk("TC015 T1 201", c==201)
c,j=a.post(T,{"amount_minor":2500,"currency":"USD","method":"zelle"}); log("T2",c,short(j,n=300)); chk("TC015 T2 USD 201", c==201)
c,j=a.post(T,{"amount_minor":100000000,"currency":"EGP","method":"cash"}); chk("TC015 MAX 201", c==201, short(j,n=150))
for v in [100000001,0,-1,1.5,True,"5"]:
    c,j=a.post(T,{"amount_minor":v,"currency":"EGP","method":"cash"}); log("amt",repr(v),c,short(j,n=150)); chk(f"TC015 amt {v!r} 400", c==400)
for k,v in [("method","stripe"),("method","wallet"),("method","code"),("currency","E"),("currency",123),("paid_on",d(1))]:
    b={"amount_minor":100,"currency":"EGP","method":"cash"}; b[k]=v
    c,j=a.post(T,b); log(k,v,c,short(j,n=150)); chk(f"TC015 {k}={v} 400", c==400)
c,j=a.get("/wallet/students/5/"); log("wallet",c,short(j,n=400))
c,j=a.get("/wallet/students/5/entries/?currency=EGP"); log("entries",c,short(j,n=300))
c,j=a.get("/wallet/students/999999/"); chk("TC015 unknown 404", c==404, str(c))
stu=S(); stu.login(*PW["student"]); c,j=stu.get("/wallet/mine/"); log("mine",c,short(j,n=300)); chk("TC015 mine 200", c==200)
p2=S(); p2.login(*PW["parent2"]); c,j=p2.get("/wallet/students/5/"); chk("TC015 parent2 403/404", c in (403,404), str(c))
log("inv", inv_inv())
log("chain", q("select e.wallet_id,e.id,e.kind,e.amount_minor,e.balance_after_minor, sum(e.amount_minor) over (partition by e.wallet_id order by e.id) from wallet_walletentry e order by e.wallet_id,e.id"))
log("topup payments", q("select id,amount_minor,currency,method,wallet_topup,invoice_id,customer_type,student_id,status from billing_payment where wallet_topup order by id"))
c,j=a.get("/billing/summary/"); log("summary",short(j))
save("tc015.txt")
log("== TC-016", datetime.datetime.now().isoformat())
ADJ="/wallet/students/5/adjustments/"
np0=q("select count(*) from billing_payment")
c,j=a.post(ADJ,{"amount_minor":-1000,"currency":"EGP","reason":"fix"}); chk("TC016 -1000 201", c==201, short(j,n=200))
c,j=a.post(ADJ,{"amount_minor":500,"currency":"EGP","reason":"gift"}); chk("TC016 +500 201", c==201, short(j,n=200))
bal=int(q("select balance_minor from wallet_wallet where currency='EGP' and student_id=1"))
c,j=a.post(ADJ,{"amount_minor":-(bal+1),"currency":"EGP","reason":"over"}); chk("TC016 overdraw 409 insufficient", c==409 and j.get("code")=="wallet.insufficient_balance", short(j))
for b in [{"amount_minor":0,"currency":"EGP","reason":"z"},{"amount_minor":5,"currency":"EGP","reason":""},{"amount_minor":5,"currency":"EGP","reason":"   "},{"amount_minor":5,"currency":"EGP","reason":"x"*501},{"amount_minor":100000001,"currency":"EGP","reason":"x"},{"amount_minor":-100000001,"currency":"EGP","reason":"x"}]:
    c,j=a.post(ADJ,b); chk(f"TC016 {str(b)[:60]} 400", c==400, short(j,n=120))
c,j=a.post(ADJ,{"amount_minor":-5,"currency":"JPY","reason":"x"}); chk("TC016 negative no wallet 409", c==409, short(j))
chk("TC016 no JPY wallet created", q("select count(*) from wallet_wallet where student_id=1 and currency='JPY'")=="0")
chk("TC016 no billing_payment added", q("select count(*) from billing_payment")==np0)
log("adj entries", q("select id,kind,amount_minor,payment_id from wallet_walletentry where kind='adjustment'"))
# limited roles
cw=a.post("/access/roles/",{"name_ar":"محفظة1","name_en":"QA Wallet Create","permissions":["wallet.view_any","wallet.create","student.view","student.view_any"]})[1]["id"]
uw=a.post("/access/roles/",{"name_ar":"محفظة2","name_en":"QA Wallet Update","permissions":["wallet.view_any","wallet.update","student.view","student.view_any"]})[1]["id"]
st.update(R_WC=cw,R_WU=uw)
a.patch("/access/staff/3/",{"role_ids":[uw]}); sc=S(); sc.login(*PW["staffc"])
c,j=sc.post(ADJ,{"amount_minor":100,"currency":"EGP","reason":"x"}); log("update-only positive",c,short(j)); chk("TC016 positive with wallet.update only 403", c==403)
c,j=sc.post(ADJ,{"amount_minor":-100,"currency":"EGP","reason":"x"}); log("update-only negative",c,short(j,n=150))
a.patch("/access/staff/3/",{"role_ids":[cw]}); sc=S(); sc.login(*PW["staffc"])
c,j=sc.post(ADJ,{"amount_minor":-100,"currency":"EGP","reason":"x"}); log("create-only negative",c,short(j)); chk("TC016 negative with wallet.create only 403", c==403)
c,j=sc.post(ADJ,{"amount_minor":100,"currency":"EGP","reason":"x"}); log("create-only positive",c,short(j,n=150))
a.patch("/access/staff/3/",{"role_ids":[3,st["R_BILL"]]})
log("inv", inv_inv())
st_save(st); save("tc016.txt")
