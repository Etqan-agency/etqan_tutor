from qa import *
st = st_load(); a = S(); a.login(*PW["admin"])
K = ["id","number","student","payer","amount_minor","currency","status","paid_minor","balance_minor","issued_on","due_on","subscription"]
log("== TC-001", datetime.datetime.now().isoformat())
ln0 = 6
c, j = a.get("/billing/payers/?student=5"); log("payers", c, short(j, n=500)); payers = j
c, j = 201, a.get("/billing/invoices/7/")[1]
log("create", c, short(j, K, 600)); st["INV1"] = j["id"]
chk("TC001 201 unpaid 50000 EGP balance", c==201 and j["status"]=="unpaid" and j["amount_minor"]==50000 and j["currency"]=="EGP" and j["paid_minor"]==0 and j["balance_minor"]==50000)
chk("TC001 issued_on Cairo today", j["issued_on"]==d(0), j["issued_on"])
chk("TC001 payer == payers.default (family payer P3)", j["payer"]["id"]==payers["default"]==st["P3"], short(j["payer"]))
c, j2 = a.get(f"/billing/invoices/{st['INV1']}/"); log("detail", c, short(j2, n=900))
c, j3 = a.get("/billing/invoices/?student=5"); log("list student", c, j3.get("count") if isinstance(j3, dict) else j3)
c, j3 = a.get("/billing/invoices/?status=unpaid&q=Tajweed"); log("list q", c, [r["id"] for r in j3["results"]])
c, j = a.post("/billing/invoices/", {"student":5,"amount_minor":10000,"due_on":d(7),"description":"USD lower","currency":"usd"}); log("usd", c, short(j, K)); st["INV_USD"] = j.get("id")
chk("TC001 currency usd->USD", c==201 and j["currency"]=="USD")
c, j = a.post("/billing/invoices/", {"student":5,"amount_minor":10000,"due_on":d(7),"description":"payer self","payer":5}); log("payer=5", c, short(j, K)); st["INV_SELF"] = j.get("id")
chk("TC001 payer=5 accepted", c==201)
log("DB", q(f"select id,number,payer_id,student_id,amount_minor,currency,issued_on,due_on,status,subscription_id,created_by_id from billing_invoice where id>={st['INV1']} order by id"))
ln1 = int(q("select last_number from billing_invoicecounter")); chk("TC001 counter +3 gap free", ln1-ln0==3, f"{ln0}->{ln1}")
nums = q(f"select number from billing_invoice where id>={st['INV1']} order by id").split("\n"); log("numbers", nums)
save("tc001.txt")
log("== TC-002", datetime.datetime.now().isoformat())
ln0 = int(q("select last_number from billing_invoicecounter")); n201 = 0
base = {"student":5,"amount_minor":10000,"due_on":d(0),"description":"x"}
rows = []
for v in [0,-5,1.5,"100",True,None,9223372036854775808,99999999999999999999]: rows.append(("amount_minor", v))
for v in [d(-1),"2026-13-40","__MISSING__"]: rows.append(("due_on", v))
for v in ["__MISSING__",""]: rows.append(("description", v))
for v in ["EG","EGPX","12$","egp","ZZZ"]: rows.append(("currency", v))
for v in [7, 999999]: rows.append(("student", v))
for v in [st["P2"], 7]: rows.append(("payer", v))
for f, v in rows:
    b = dict(base)
    if v == "__MISSING__": b.pop(f)
    else: b[f] = v
    if f=="currency" and v=="ZZZ": b["description"]="S5 zzz"
    c, j = a.post("/billing/invoices/", b)
    if c==201: n201 += 1; st.setdefault("TC002_201", []).append(j["id"])
    log(f"{f}={v!r}", c, short(j, n=200) if c!=201 else short(j, ["id","currency","amount_minor"]))
    if c>=500: log("BAD 5xx")
# subscription rows: S2 subscription id 2 belongs to student profile 2 (user 8)
c, j = a.post("/billing/invoices/", dict(base, subscription=2)); log("subscription of other student", c, short(j, n=200)); n201 += c==201
c, j = a.post("/billing/invoices/", dict(base, subscription=1, currency="USD")); log("USD vs EGP subscription", c, short(j, n=200)); n201 += c==201
if c==201: st.setdefault("TC002_201", []).append(j["id"])
ln1 = int(q("select last_number from billing_invoicecounter")); chk("TC002 counter grows only by 201s", ln1-ln0==n201, f"{ln0}->{ln1} n201={n201}")
log("amount<=0 rows", q("select count(*) from billing_invoice where amount_minor<=0"))
st_save(st); save("tc002.txt")
