from qa import *
st = st_load(); ss = st["sess"]; a = S(); a.login(*PW["admin"])
def slip(t, y, m):
    c, j = a.get(f"/payroll/payslips/?year={y}&month={m}&teacher={ID[t]}"); r = j["results"]; return r[0] if r else None
log("==== TC-022", datetime.datetime.now().isoformat())
t1 = S(); t1.login(*PW["T1"]); t2 = S(); t2.login(*PW["T2"])
# make T2 have an issued+paid payslip: T2 Sept draft -> issue -> paid
p2 = slip("T2", 2026, 9); a.post(f"/payroll/payslips/{p2['id']}/issue/"); a.post(f"/payroll/payslips/{p2['id']}/mark-paid/", {"paid_on": TODAY.isoformat()})
c, w2 = t2.post("/payroll/withdrawals/", {"amount_minor": 100, "currency": "EGP"}); log("T2 withdrawal (no balance)", c, short(w2))
t1_rows = q("select id||':'||status from payroll_payslip where teacher_id=1 order by id"); log("DB T1 payslips", t1_rows)
c, j = t1.get("/payroll/payslips/"); ids = [x["id"] for x in j["results"]]; sts = {x["status"] for x in j["results"]}
allowed = {int(r.split(":")[0]) for r in t1_rows.split() if r.split(":")[1] in ("issued", "paid")}
chk("T1 list = own issued/paid only, no draft", set(ids) == allowed and "draft" not in sts, f"{ids} vs {allowed}")
c, j = t1.get(f"/payroll/payslips/?teacher={ID['T2']}"); chk("?teacher=T2 still own", {x["id"] for x in j["results"]} <= allowed, str([x["id"] for x in j["results"]]))
c, j = t1.get(f"/payroll/payslips/{p2['id']}/"); chk("T2 payslip detail 404", c == 404, str(c))
c, j = t1.get(f"/payroll/payslips/{st['slip_T1_sep']}/"); chk("T1 detail hides notes/issued_by/paid_by", c == 200 and not any(k in j for k in ("notes", "issued_by", "paid_by")), str([k for k in ("notes","issued_by","paid_by") if k in j]))
c, j = t1.get(f"/payroll/payslips/{slip('T1', 2026, 10)['id']}/"); chk("T1 own draft detail 404", c == 404, str(c))
c, j = t1.get("/payroll/payslips/?format=csv", raw=True); chk("teacher CSV 403", c == 403, str(c))
c, j = t1.get("/payroll/payslips/", raw=True, headers={"Accept": "text/csv"}); chk("teacher Accept text/csv 403 or JSON-own", c in (403, 406) or j.startswith("{"), f"{c} {j[:80]}")
c, j = t1.get("/payroll/withdrawals/"); chk("withdrawals own only", all(x["teacher"]["id"] == ID["T1"] for x in j["results"]), str(len(j["results"])))
log("T1 withdrawal keys", list(j["results"][0].keys()) if j["results"] else None)
wid_other = q("select id from payroll_withdrawalrequest where teacher_id<>1 limit 1")
if wid_other: c, j = t1.get(f"/payroll/withdrawals/{wid_other}/"); chk("other teacher withdrawal 404", c == 404, str(c))
c, j = t1.get(f"/payroll/balances/?teacher={ID['T2']}"); chk("balances ?teacher=T2 returns own", c == 200 and "11900" in json.dumps(j), short(j))
for p in ["/payroll/payslips/projection/", "/payroll/settings/", "/payroll/rates/", "/payroll/adjustments/", "/payroll/fixed-salaries/", "/payroll/student-rates/"]:
    c, j = t1.get(p); chk(f"teacher GET {p} 403", c == 403, str(c))
save("tc022.txt")

log("==== TC-023 matrix", datetime.datetime.now().isoformat())
pid = st["slip_T1_sep"]; iss = slip("T3", 2026, 8)["id"]; rid = q("select id from payroll_teacherrate where teacher_id=1 and course_id is null"); aid = st["adj_T1_late"]
wid = q("select id from payroll_withdrawalrequest where teacher_id=1 order by id limit 1")
EP = [("GET","/payroll/rates/",None),("POST","/payroll/rates/",{"teacher":ID["T9"],"course":1,"hourly_rate_minor":1}),("PATCH",f"/payroll/rates/{rid}/",{"hourly_rate_minor":6000}),("DELETE","/payroll/rates/999999/",None),
      ("POST","/payroll/rates/bulk/",{"teachers":[ID["T9"]],"rates":[{"course":None,"hourly_rate_minor":6000}]}),("GET","/payroll/settings/",None),("PATCH","/payroll/settings/",{"group_pay":"per_student"}),
      ("GET","/payroll/adjustments/",None),("POST","/payroll/adjustments/",{"teacher":ID["T9"],"kind":"bonus","amount_minor":1,"effective_on":"2026-12-01","reason":"m"}),("PATCH",f"/payroll/adjustments/{aid}/",{"reason":"late Sept session"}),
      ("GET","/payroll/payslips/",None),("GET",f"/payroll/payslips/{pid}/",None),("POST","/payroll/payslips/generate/",{"year":2026,"month":12}),("POST",f"/payroll/payslips/{pid}/issue/",{}),
      ("POST",f"/payroll/payslips/{iss}/mark-paid/",{"paid_on":"2099-01-01"}),("POST",f"/payroll/payslips/{pid}/pay-to-balance/",{"paid_on":"2099-01-01"}),("GET","/payroll/payslips/projection/",None),("GET","/payroll/payslips/?format=csv",None),
      ("GET",f"/payroll/balances/?teacher={ID['T1']}",None),("GET","/payroll/withdrawals/",None),("POST","/payroll/withdrawals/",{"teacher":ID["T1"],"amount_minor":999999999,"currency":"EGP"}),
      ("POST",f"/payroll/withdrawals/{wid}/approve/",{}),("POST",f"/payroll/withdrawals/{wid}/reject/",{"office_notes":"x"}),("POST",f"/payroll/withdrawals/{wid}/pay/",{"paid_on":"2099-01-01"}),("POST",f"/payroll/withdrawals/{wid}/cancel/",{}),
      ("GET","/payroll/fixed-salaries/",None),("POST","/payroll/fixed-salaries/",{"teacher":ID["T8"],"monthly_minor":1,"starts_on":"2026-09-01"}),("GET","/payroll/student-rates/",None),("POST","/payroll/student-rates/",{"teacher":ID["T4"],"student":ID["S2"],"hourly_rate_minor":1})]
ROLES = ["anon","student","parent","staffno","staffc","s_payread","s_pay","sup","T1","s_updnoview","admin"]
sess = {}
for r in ROLES:
    if r == "anon": sess[r] = anon()
    else: s_ = S(); c = s_.login(*PW[r]); sess[r] = s_; (c != 200) and log("LOGIN FAIL", r, c)
TBL = ["payroll_payslip","payroll_teacherrate","payroll_payadjustment","payroll_withdrawalrequest","payroll_fixedsalary","payroll_studentrate","finance_expense"]
snap = lambda: q(" union all ".join(f"select '{t}',count(*)::text||':'||coalesce(max(updated_at)::text,'') from {t}" if t not in ("payroll_payadjustment","payroll_withdrawalrequest") else f"select '{t}',count(*)::text from {t}" for t in TBL))
hdr = "| endpoint | " + " | ".join(ROLES) + " |"; log(hdr); log("|" + "---|" * (len(ROLES) + 1))
viol = []
for m, p, b in EP:
    row = []
    for r in ROLES:
        if r == "admin" or r == "s_pay": row.append("-"); continue  # writes for full roles verified in their cases
        before = snap(); c, j = sess[r].req(m, p, b, raw=True); after = snap()
        row.append(str(c));
        if before != after: viol.append((r, m, p, c))
    log(f"| {m} {p} | " + " | ".join(row) + " |")
chk("no DB change from any denied/limited role request", not viol, str(viol))
# full staff and admin: GET only rows (writes covered elsewhere)
for r in ["s_pay", "admin"]:
    out = [f"{p}:{sess[r].get(p, raw=True)[0]}" for m, p, b in EP if m == "GET"]; log(r, "GETs", out)
save("tc023.txt")

log("==== TC-027", datetime.datetime.now().isoformat())
before = q("select count(*), max(updated_at) from payroll_payslip")
c, j = a.get("/payroll/payslips/projection/"); log("projection", c, short(j, n=1500))
t1row = None
for r in (j.get("rows") or j.get("teachers") or j.get("results") or []) if isinstance(j, dict) else []:
    if r.get("teacher", {}).get("id") == ID["T1"]: t1row = r
log("T1 projection row", short(t1row, n=500))
a.post("/payroll/payslips/generate/", {"year": 2026, "month": 10}); po = slip("T1", 2026, 10); log("T1 Oct draft net", po["net_minor"], "gross", po["gross_minor"])
c, raw = a.get("/payroll/payslips/projection/?format=csv", raw=True); log("projection csv", c, raw[:400])
pr = S(); pr.login(*PW["s_payread"]); c, j2 = pr.get("/payroll/payslips/projection/"); log("payread projection", c)
log(features("qa", off=["exchange_rates"])); c, j3 = a.get("/payroll/payslips/projection/"); log("exch off estimate", short({k: v for k, v in j3.items() if "estim" in k} if isinstance(j3, dict) else j3))
log(features("qa", on=["exchange_rates"]))
log(features("qa", off=["salary_projections"])); c, _ = a.get("/payroll/payslips/projection/"); chk("projection switch off 403/404", c in (403, 404), str(c)); log(features("qa", on=["salary_projections"]))
chk("projection no DB writes", before == q("select count(*), max(updated_at) from payroll_payslip") or True, "generate above changes updated_at; checked separately")
b2 = q("select count(*), max(updated_at) from payroll_payslip"); a.get("/payroll/payslips/projection/"); chk("projection call writes nothing", b2 == q("select count(*), max(updated_at) from payroll_payslip"))
st["proj"] = j; st_save(st); save("tc027.txt")

log("==== TC-028", datetime.datetime.now().isoformat())
c, j = a.get(f"/payroll/payslips/?year=2026&month=9&status=paid&teacher={ID['T1']}"); chk("filters", c == 200 and [x["id"] for x in j["results"]] == [st["slip_T1_sep"]], str([x["id"] for x in j["results"]]))
for qs in ["year=1", "month=13", "status=x", "teacher=0", "teacher=abc"]:
    c, j = a.get(f"/payroll/payslips/?{qs}"); chk(f"bad {qs} 400 names field", c == 400 and qs.split("=")[0] in (j or {}), f"{c} {short(j)}")
c, raw = a.get("/payroll/payslips/?year=2026&month=9&format=csv", raw=True); lines = raw.splitlines(); log("csv", c, len(lines)); [log("  ", l) for l in lines[:12]]
xl = [l for l in lines if "HYPERLINK" in l]; chk("formula name guarded with leading '", xl and ("'=HYPERLINK" in xl[0]), xl[0] if xl else "no row")
import csv as _csv, io
rows = list(_csv.reader(io.StringIO(raw.lstrip("﻿")))); h = rows[0]; ni = h.index("Net (minor units)")
s_csv = sum(int(r[ni]) for r in rows[1:]); s_db = q("select sum(net_minor) from payroll_payslip where year=2026 and month=9"); chk("csv net sum = DB", str(s_csv) == s_db, f"{s_csv} vs {s_db}")
chk("money columns plain ints", all(r[ni].lstrip("-").isdigit() for r in rows[1:]))
save("tc028.txt")
