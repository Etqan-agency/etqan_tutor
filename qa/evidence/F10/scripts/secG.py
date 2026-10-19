from qa import *
st = st_load(); ss = st["sess"]; a = S(); a.login(*PW["admin"])
def slip(t, y, m):
    c, j = a.get(f"/payroll/payslips/?year={y}&month={m}&teacher={ID[t]}"); r = j["results"]; return r[0] if r else None
log("==== TC-029 (S2)", datetime.datetime.now().isoformat())
BIG = 9223372036854775807
c, j = a.post("/payroll/rates/", {"teacher": ID["T14"], "hourly_rate_minor": BIG}); log("rate int64 max", c, short(j, n=200)); st["rate_T14"] = j.get("id") if isinstance(j, dict) else None
c, g = a.post("/payroll/payslips/generate/", {"year": 2026, "month": 4}, raw=True); log("S2 generate April with huge rate", c, g[:300])
c, j = a.post("/payroll/adjustments/", {"teacher": ID["T13"], "kind": "bonus", "amount_minor": BIG, "effective_on": "2026-05-15", "reason": "big"}); log("adj int64 max", c, short(j, n=200)); st["adj_big"] = j.get("id") if isinstance(j, dict) else None
c, j = a.post("/payroll/adjustments/", {"teacher": ID["T13"], "kind": "bonus", "amount_minor": BIG + 1, "effective_on": "2026-05-15", "reason": "big"}, raw=True); log("adj int64+1", c, j[:200])
c, j = a.post("/payroll/fixed-salaries/", {"teacher": ID["T14"], "monthly_minor": BIG + 1, "starts_on": "2026-04-01"}, raw=True); log("fixed int64+1", c, j[:200])
c, j = a.post("/payroll/rates/", {"teacher": ID["T9"], "course": 2, "hourly_rate_minor": BIG + 1}, raw=True); log("rate int64+1", c, j[:200])
t1 = S(); t1.login(*PW["T1"]); c, j = t1.post("/payroll/withdrawals/", {"amount_minor": BIG + 1, "currency": "EGP"}, raw=True); log("withdrawal int64+1", c, j[:200])
for v in ["6000.5", 6000.5, "abc", None, "1e3", 1e3, -0.0, True]:
    c, j = a.post("/payroll/adjustments/", {"teacher": ID["T13"], "kind": "bonus", "amount_minor": v, "effective_on": "2026-05-15", "reason": "fmt"}); log(f"adj amount {v!r}", c, short(j, n=150))
    if c == 201: a.delete(f"/payroll/adjustments/{j['id']}/")
    c, j = a.patch(f"/payroll/rates/{q('select id from payroll_teacherrate where teacher_id=14 and course_id is null')}/", {"hourly_rate_minor": v}); log(f"rate patch {v!r}", c, short(j, n=150))
log("T13 rate now", q("select hourly_rate_minor from payroll_teacherrate where teacher_id=14 and course_id is null"))
# moderate overflow: fixed BIG/2 + session lines -> gross overflow?
c, j = a.post("/payroll/fixed-salaries/", {"teacher": ID["T14"], "monthly_minor": BIG, "starts_on": "2026-04-01"}); log("fixed int64 max", c, short(j, n=150)); st["fixed_T14"] = j.get("id") if isinstance(j, dict) else None
c, g = a.post("/payroll/payslips/generate/", {"year": 2026, "month": 4}, raw=True); log("generate April fixed max", c, g[:300])
c, j = a.post("/payroll/adjustments/", {"teacher": ID["T14"], "kind": "bonus", "amount_minor": BIG, "effective_on": "2026-04-15", "reason": "big"}); st["adj_big14"] = j.get("id") if isinstance(j, dict) else None
c, g = a.post("/payroll/payslips/generate/", {"year": 2026, "month": 4}, raw=True); log("generate April fixed max + bonus max", c, g[:300])
log("T14 slips", q("select id,month,gross_minor,bonuses_minor,net_minor from payroll_payslip where teacher_id=15"))
st_save(st); save("tc029.txt")
