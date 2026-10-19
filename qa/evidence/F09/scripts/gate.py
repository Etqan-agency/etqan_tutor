import sys; sys.path.insert(0, "/Users/khaledsakr/Documents/Etqan tutor/etqan_tutor/qa/evidence/F09/scripts")
from qa import *
import datetime
log("== F09 gate cheap P1 checks", datetime.datetime.utcnow().isoformat())
ss = sessions(["admin", "parent2", "student2", "student", "parent"])
A = ss["admin"]
def counts():
    return q("select (select count(*) from billing_invoice),(select count(*) from billing_payment),(select count(*) from wallet_walletentry),(select count(*) from vouchers_voucherbatch)")
# G1: cross-family wallet reads/writes
log("-- G1 cross-family wallet (S1 = 5)")
c0 = counts()
for who in ["parent2", "student2"]:
    s = ss[who]
    for m, p, b in [("GET", "/wallet/students/5/", None), ("GET", "/wallet/students/5/entries/", None),
                    ("POST", "/wallet/students/5/top-ups/", {"amount_minor": 100, "currency": "EGP"})]:
        c, j = s.req(m, p, b); log(who, m, p, c); chk(f"G1 {who} {m} {p} refused", c in (403, 404))
    c, j = s.get("/wallet/mine/"); ids = json.dumps(j)
    chk(f"G1 {who} mine has no S1 wallet", '"student": 5' not in ids and "'student': 5" not in ids, ids[:200])
c, j = ss["parent"].get("/wallet/mine/"); log("parent mine", c, short(j, n=300))
chk("G1 DB unchanged", counts() == c0, c0 + " vs " + counts())
# G2: feature switches off -> 404 for admin, DB unchanged, then restore
log("-- G2 feature off")
for feat, paths in [("balances", ["/wallet/students/5/", "/wallet/compensations/"]),
                    ("system_codes", ["/vouchers/batches/", "/vouchers/codes/"]),
                    ("invoices", ["/billing/invoices/", "/billing/summary/"])]:
    log("set off", feat, features("qa", off=[feat])); dc("exec", "-T", "django", "python", "manage.py", "shell", "-c", "from django.core.cache import cache; cache.clear()")
    for p in paths:
        c, j = A.get(p); log(feat, "off GET", p, c); chk(f"G2 {feat} off {p} 404", c == 404)
    if feat == "invoices":
        c, j = A.post("/billing/invoices/", {"student": 5, "amount_minor": 1000, "currency": "EGP", "description": "gate off"}); chk("G2 invoices off POST 404", c == 404, str(c))
    if feat == "system_codes":
        c, j = ss["student"].post("/vouchers/redeem/", {"code": "XB0YF46DWY"}); chk("G2 codes off redeem 404", c == 404, str(c))
    log("set on", feat, features("qa", on=[feat])); dc("exec", "-T", "django", "python", "manage.py", "shell", "-c", "from django.core.cache import cache; cache.clear()")
    c, j = A.get(paths[0]); chk(f"G2 {feat} back on {paths[0]} 200", c == 200, str(c))
chk("G2 DB unchanged", counts() == c0, c0 + " vs " + counts())
save("gate/gate-checks.txt")
