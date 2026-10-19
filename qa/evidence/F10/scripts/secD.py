from qa import *
st = st_load(); ss = st["sess"]; a = S(); a.login(*PW["admin"])
def slip(t, y, m):
    c, j = a.get(f"/payroll/payslips/?year={y}&month={m}&teacher={ID[t]}"); r = j["results"]; return r[0] if r else None
def det(pid): return a.get(f"/payroll/payslips/{pid}/")[1]
log("==== TC-013", datetime.datetime.now().isoformat())
c, j = a.patch("/payroll/settings/", {"student_absent_pay_bp": 5000, "student_excused_pay_bp": 2500, "at_disposal_pays": True, "group_pay": "per_class"}); chk("settings patch 200", c == 200, short(j))
for b in [{"student_absent_pay_bp": -1}, {"student_absent_pay_bp": 10001}, {"group_pay": "x"}]:
    c, j = a.patch("/payroll/settings/", b); chk(f"{b} 400", c == 400 and list(b)[0] in j, f"{c} {short(j)}")
ps = S(); ps.login(*PW["s_pay"]); c, j = ps.patch("/payroll/settings/", {"group_pay": "per_class"}); chk("staff payroll_settings.update PATCH 200", c == 200, str(c))
G = [58, 59, 60]
for sid in G: a.post(f"/sessions/{sid}/attendance/", {"student_attendance": "present", "teacher_attendance": "present"})
a.patch("/payroll/settings/", {"group_pay": "per_student"}); a.post("/payroll/payslips/generate/", {"year": 2026, "month": 5}); p = slip("T12", 2026, 5)
chk("per_student 3 lines x 3000 = 9000", p["gross_minor"] == 9000, short(p, ["gross_minor","sessions"]))
a.patch("/payroll/settings/", {"group_pay": "per_class"}); a.post("/payroll/payslips/generate/", {"year": 2026, "month": 5}); p = slip("T12", 2026, 5); dl = det(p["id"])["lines"]
log("per_class lines", [(l["session_id"], l.get("group_role"), l.get("pay_bp"), l["amount_minor"], l.get("description")) for l in dl])
chk("per_class carrier lowest id 3000, 2 members 0", p["gross_minor"] == 3000 and [l["amount_minor"] for l in sorted(dl, key=lambda l: l["session_id"])] == [3000, 0, 0] and p["sessions"] == 1, f"gross={p['gross_minor']} sessions={p['sessions']}")
for sid in G[1:]: a.post(f"/sessions/{sid}/attendance/", {"student_attendance": "absent"})
a.post("/payroll/payslips/generate/", {"year": 2026, "month": 5}); p = slip("T12", 2026, 5); dl = det(p["id"])["lines"]
chk("mixed attendance (1 present, 2 absent) carrier at 100%", p["gross_minor"] == 3000 and min(dl, key=lambda l: l["session_id"])["pay_bp"] == 10000, str([(l["session_id"], l.get("pay_bp"), l["amount_minor"]) for l in dl]))
log("DB lines", q(f"select session_id,group_role,pay_bp,group_key,amount_minor from payroll_payslipline where payslip_id={p['id']} order by session_id"))
log(features("qa", off=["payroll_rules"]))
c, j = a.get("/payroll/settings/"); chk("settings GET off 403/404", c in (403, 404), str(c)); c, j = a.patch("/payroll/settings/", {"group_pay": "per_student"}); chk("settings PATCH off 403/404", c in (403, 404), str(c))
a.post("/payroll/payslips/generate/", {"year": 2026, "month": 5}); p = slip("T12", 2026, 5); chk("rules off -> per_student 100% defaults: 9000", p["gross_minor"] == 9000, str(p["gross_minor"]))
p2 = slip("T2", 2026, 9); chk("rules off -> T2 absent/excused at 100%: 12345*(45*3+30+20)/60 lines", p2["gross_minor"] == 9259+6173+4115+9259+9259, str(p2["gross_minor"]))
log(features("qa", on=["payroll_rules"])); log("settings row", q("select * from payroll_payrollsettings"))
save("tc013.txt")

log("==== TC-014", datetime.datetime.now().isoformat())
c, j = a.patch("/payroll/settings/", {"report_deduction_bp": 1000}); chk("report bp 200", c == 200, short(j))
c, j = a.post(f"/sessions/{ss['T10_a']}/report/", {"behaviour": 4, "participation": 4, "notes": "F10"}); log("report", c, short(j, n=150))
a.post("/payroll/payslips/generate/", {"year": 2026, "month": 9}); p = slip("T10", 2026, 9); dl = det(p["id"])["lines"]
rl = [l for l in dl if l["kind"] == "report"]
chk("2 report lines -600, ded 1200, net 16800, sent 1 missing 2", [l["amount_minor"] for l in rl] == [-600, -600] and p["deductions_minor"] == 1200 and p["net_minor"] == 16800 and (p["reports_sent"], p["reports_missing"]) == (1, 2), f"{[l['amount_minor'] for l in rl]} {short(p, ['deductions_minor','net_minor','reports_sent','reports_missing','report_deductions_minor'])}")
c, j = a.patch("/payroll/settings/", {"report_deduction_bp": 10001}); chk("10001 400", c == 400, str(c))
# group: May group class, 3 members present? set all present, 0 reports -> carrier owes reports for members present
for sid in G: a.post(f"/sessions/{sid}/attendance/", {"student_attendance": "present"})
a.post("/payroll/payslips/generate/", {"year": 2026, "month": 5}); p = slip("T12", 2026, 5); dl = det(p["id"])["lines"]
log("group report lines", [(l["kind"], l["session_id"], l["amount_minor"]) for l in dl if l["kind"] == "report"], "expected round(3000*1000*3/(10000*3))=300")
chk("group report deduction once = 300", [l["amount_minor"] for l in dl if l["kind"] == "report"] == [-300])
log(features("qa", off=["report_deductions"]))
c, j = a.patch("/payroll/settings/", {"report_deduction_bp": 500}); chk("off: PATCH bp 400", c == 400, f"{c} {short(j)}")
a.post("/payroll/payslips/generate/", {"year": 2026, "month": 9}); p = slip("T10", 2026, 9); chk("off: build ignores bp", p["deductions_minor"] == 0 and p["net_minor"] == 18000, short(p, ["deductions_minor","net_minor"]))
log(features("qa", on=["report_deductions"])); a.post("/payroll/payslips/generate/", {"year": 2026, "month": 9})
p = slip("T10", 2026, 9); c, j = a.post(f"/payroll/payslips/{p['id']}/issue/"); chk("issue rebuilds same 16800", c == 200 and j["net_minor"] == 16800, f"{c} {j.get('net_minor')}")
a.patch("/payroll/settings/", {"report_deduction_bp": 0, "student_absent_pay_bp": 10000, "student_excused_pay_bp": 10000, "at_disposal_pays": False, "group_pay": "per_student"})
save("tc014.txt")

log("==== TC-015", datetime.datetime.now().isoformat()); T = ID["T11"]
a.post("/payroll/payslips/generate/", {"year": 2026, "month": 8}); p8 = slip("T11", 2026, 8); c, j = a.post(f"/payroll/payslips/{p8['id']}/issue/"); log("issue Aug T11", c, j.get("currency"), j.get("net_minor"))
c, F = a.post("/payroll/fixed-salaries/", {"teacher": T, "monthly_minor": 400000, "starts_on": "2026-10-01"}); log("fixed T11 (from Oct)", c); st["fixed_T11"] = F.get("id")
c, A = a.post("/payroll/adjustments/", {"teacher": T, "kind": "bonus", "amount_minor": 1500, "effective_on": "2026-09-10", "reason": "F10"}); log("adj T11", c)
c, j = a.patch(f"/people/teachers/{T}/", {"profile": {"pay_currency": "USD"}}); log("pay_currency USD", c, short(j, n=200))
log("profile", q(f"select pay_currency from identity_teacherprofile where user_id={T}"))
c, g = a.post("/payroll/payslips/generate/", {"year": 2026, "month": 9}); log("gen", short(g, n=600))
chk("missing_rate lists T11", T in [x["id"] for x in g["missing_rate"]]); chk("other_currency lists T11", T in [x["id"] for x in g["other_currency"]])
c, g10 = a.post("/payroll/payslips/generate/", {"year": 2026, "month": 10}); chk("stale_fixed_salary lists T11 (Oct)", T in [x["id"] for x in g10["stale_fixed_salary"]], short(g10["stale_fixed_salary"]))
rid = q(f"select id from payroll_teacherrate where teacher_id=(select id from identity_teacherprofile where user_id={T})")
c, j = a.patch(f"/payroll/rates/{rid}/", {"hourly_rate_minor": 6000}); log("S10 rate re-save", c, short(j, n=250))
p9 = slip("T11", 2026, 9); log("S10 Sept draft now", short(p9, ["currency","gross_minor","net_minor","missing_rate"]))
c, j = a.post(f"/payroll/payslips/{p9['id']}/issue/"); chk("issue T11 Sept USD", c == 200 and j["currency"] == "USD", f"{c} {short(j, ['currency','net_minor'])}")
chk("Aug still EGP", det(p8["id"])["currency"] == "EGP")
c, j = a.post("/payroll/rates/bulk/", {"teachers": [T, ID["T1"]], "rates": [{"course": None, "hourly_rate_minor": 7000}]}); chk("bulk mixed currencies 400 payroll.mixed_currencies", c == 400 and "mixed_currencies" in json.dumps(j), f"{c} {short(j)}")
c, j = a.post("/payroll/adjustments/", {"teacher": T, "kind": "bonus", "amount_minor": 100, "effective_on": "2026-10-10", "reason": "usd"}); chk("new adj stored USD", c == 201 and j["currency"] == "USD", f"{c} {j.get('currency')}")
log("DB currencies", q(f"select 'rate',currency from payroll_teacherrate where teacher_id=12 union all select 'adj',currency from payroll_payadjustment where teacher_id=12 union all select 'fixed',currency from payroll_fixedsalary where teacher_id=12 union all select 'slip '||month,currency from payroll_payslip where teacher_id=12"))
st_save(st); save("tc015.txt")

log("==== TC-016", datetime.datetime.now().isoformat())
cnt = lambda: q("select count(*) from payroll_teacherrate")
n0 = cnt(); c, j = a.post("/payroll/rates/bulk/", {"teachers": [ID["T1"], ID["T2"], ID["T3"]], "rates": [{"course": None, "hourly_rate_minor": 7000}, {"course": 1, "hourly_rate_minor": 8000}]})
chk("bulk ok created 3 updated 3", c == 200 and (j.get("created"), j.get("updated")) == (3, 3), f"{c} {short(j)} rows {n0}->{cnt()}")
n1 = cnt()
for b, lab in [({"teachers": [ID["T1"]], "rates": [{"course": 999, "hourly_rate_minor": 1}]}, "unknown course"), ({"teachers": [ID["T1"], ID["S1"]], "rates": [{"course": None, "hourly_rate_minor": 1}]}, "student id"),
               ({"teachers": [ID["T1"]], "rates": [{"course": 1, "hourly_rate_minor": 1}, {"course": 1, "hourly_rate_minor": 2}]}, "dup course"), ({"teachers": list(range(1000, 1201)), "rates": [{"course": None, "hourly_rate_minor": 1}]}, "201 teachers")]:
    c, j = a.post("/payroll/rates/bulk/", b); chk(f"bulk {lab} 400, nothing written", c == 400 and cnt() == n1, f"{c} {short(j, n=200)}")
rc = S(); rc.login(*PW["s_ratecreate"]); c, j = rc.post("/payroll/rates/bulk/", {"teachers": [ID["T1"]], "rates": [{"course": None, "hourly_rate_minor": 1}]}); chk("create-only staff 403", c == 403, str(c))
ps = S(); ps.login(*PW["s_pay"]); c, j = ps.post("/payroll/rates/bulk/", {"teachers": [ID["T2"]], "rates": [{"course": None, "hourly_rate_minor": 12345}]}); chk("full staff bulk 200", c == 200, f"{c} {short(j)}")
log(features("qa", off=["bulk_teacher_rates"])); c, j = a.post("/payroll/rates/bulk/", {"teachers": [ID["T1"]], "rates": [{"course": None, "hourly_rate_minor": 6000}]}); chk("switch off 403/404", c in (403, 404), str(c)); log(features("qa", on=["bulk_teacher_rates"]))
a.post("/payroll/rates/bulk/", {"teachers": [ID["T1"], ID["T3"]], "rates": [{"course": None, "hourly_rate_minor": 6000}]})
for t in ["T1", "T2", "T3"]:
    rid = q(f"select id from payroll_teacherrate where course_id=1 and teacher_id=(select id from identity_teacherprofile where user_id={ID[t]})")
    if rid: log("delete C1 rate", t, a.delete(f"/payroll/rates/{rid}/")[0])
log("rates now", q("select teacher_id,course_id,hourly_rate_minor,currency from payroll_teacherrate where teacher_id in (1,3,4) order by 1,2"))
save("tc016.txt")
