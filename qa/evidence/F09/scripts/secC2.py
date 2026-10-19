from qa import *
st = st_load(); a = S(); a.login(*PW["admin"])
log("== TC-013", datetime.datetime.now().isoformat())
INV1=st["INV1"]; INV_P3=st["INV_P3"]; INV_S2=q(f"select min(id) from billing_invoice where student_id=(select id from identity_studentprofile where user_id={st['S2']})")
INV_S3=a.post("/billing/invoices/",{"student":st["S3"],"amount_minor":1000,"due_on":d(7),"description":"S3 inv"})[1]["id"]
INV_P6=a.post("/billing/invoices/",{"student":5,"amount_minor":1000,"due_on":d(7),"description":"payer P1","payer":6})[1]["id"]
prof=lambda u: q(f"select id from identity_studentprofile where user_id={u}")
def allids(s):
    ids=[]; p="/billing/invoices/?page_size=200"
    c,j=s.get(p); 
    if c!=200: return c,None,None
    return c,set(r["id"] for r in j["results"]), j["count"]
exp={"student":f"select id from billing_invoice where student_id={prof(5)} or payer_id=5",
     "parent":f"select id from billing_invoice where payer_id=6 or student_id in ({prof(5)})",
     "parent3":f"select id from billing_invoice where payer_id={st['P3']} or student_id in ({prof(st['S3'])})",
     "parent2":f"select id from billing_invoice where payer_id={st['P2']} or student_id in ({prof(st['S2'])})",
     "student2":f"select id from billing_invoice where payer_id={st['S2']} or student_id in ({prof(st['S2'])})"}
for r in ["student","parent","parent3","parent2","student2","teacher"]:
    s=S(); s.login(*PW[r]); c,ids,cnt=allids(s)
    if r=="teacher": chk("TC013 teacher list 403", c==403, str(c)); continue
    e=set(int(x) for x in q(exp[r]).split("\n") if x)
    log(r,"list",c,"n",len(ids),"count",cnt,"expected",len(e)); chk(f"TC013 {r} list == scoped SQL set and count", ids==e and cnt==len(e), f"extra {sorted(ids-e)[:5]} missing {sorted(e-ids)[:5]}")
    for iid in [INV1,INV_P3,int(INV_S2),INV_S3,INV_P6]:
        c,j=s.get(f"/billing/invoices/{iid}/"); vis = iid in e
        ok = (c==200) if vis else (c==404)
        chk(f"TC013 {r} detail {iid} {'200' if vis else '404'}", ok, str(c))
        if c==200:
            keys=json.dumps(j); chk(f"TC013 {r} no notes/created_by in family payload", '"notes"' not in keys and '"created_by"' not in keys and '"recorded_by"' not in keys)
    c,j=s.patch(f"/billing/invoices/{INV1}/",{"description":"x"}); chk(f"TC013 {r} PATCH 403/404", c in(403,404), str(c))
    c,j=s.post(f"/billing/invoices/{INV1}/void/",{}); chk(f"TC013 {r} void 403/404", c in(403,404), str(c))
    c,j=s.post(f"/billing/invoices/{INV1}/payments/",{"amount_minor":1,"method":"cash","paid_on":d(0)}); chk(f"TC013 {r} payment 403/404", c in(403,404), str(c))
    c,j=s.get("/billing/invoices/?format=csv",raw=True); chk(f"TC013 {r} csv 403", c in (403,404,406), str(c))
    c,j=s.get(f"/billing/invoices/?student=5&page_size=200"); 
    if c==200: chk(f"TC013 {r} filter student=5 does not widen", set(x["id"] for x in j["results"])<=e)
    c,j=s.get(f"/billing/invoices/?payer=6&page_size=200")
    if c==200: chk(f"TC013 {r} filter payer=6 does not widen", set(x["id"] for x in j["results"])<=e)
    c,j=s.get("/billing/payers/?student=5"); chk(f"TC013 {r} payers 403", c in (403,404), str(c))
    c,j=s.get(f"/billing/payments/{st['PS']}/"); chk(f"TC013 {r} payment detail 403/404", c in(403,404,405), str(c))
st_save(st); save("tc013.txt")
