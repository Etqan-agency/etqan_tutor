from qa import *
st = st_load(); ss = st["sess"]; a = S(); a.login(*PW["admin"])
def slip(t, y, m):
    c, j = a.get(f"/payroll/payslips/?year={y}&month={m}&teacher={ID[t]}"); r = j["results"]; return r[0] if r else None
def det(pid): return a.get(f"/payroll/payslips/{pid}/")[1]
log("==== secD2 re-runs (staff login fixed: new users' emails were unverified -> verified via SQL)", datetime.datetime.now().isoformat())
ps = S(); log("s_pay login", ps.login(*PW["s_pay"]))
c, j = ps.patch("/payroll/settings/", {"group_pay": "per_student"}); chk("TC-013 staff payroll_settings.update PATCH 200", c == 200, str(c))
a.patch("/payroll/settings/", {"student_absent_pay_bp": 5000, "student_excused_pay_bp": 2500})
log(features("qa", off=["payroll_rules"])); a.post("/payroll/payslips/generate/", {"year": 2026, "month": 9}); p2 = slip("T2", 2026, 9)
chk("TC-013 rules off -> T2 absent/excused at 100%", p2["gross_minor"] == 9259+6173+4115+9259+9259, str(p2["gross_minor"]))
log(features("qa", on=["payroll_rules"])); a.post("/payroll/payslips/generate/", {"year": 2026, "month": 9}); chk("rules on -> 26491 again", slip("T2", 2026, 9)["gross_minor"] == 26491)
a.patch("/payroll/settings/", {"report_deduction_bp": 1000})
ids = []
for dd in ["2026-08-17", "2026-08-18", "2026-08-19"]:
    c, j = a.post("/sessions/extra/", {"student": ID["S1"], "course": 1, "teacher": ID["T3"], "occurs_on": dd, "start_time": "12:00", "minutes": 60}); sid = j["session"]["id"]; ids.append(sid)
    a.post(f"/sessions/{sid}/attendance/", {"student_attendance": "present", "teacher_attendance": "present"})
ss["T3_aug"] = ids
c, j = a.put(f"/sessions/{ids[0]}/report/", {"behaviour": 4, "participation": 4, "notes": "F10"}); log("report PUT", c, short(j, n=120))
a.post("/payroll/payslips/generate/", {"year": 2026, "month": 8}); p = slip("T3", 2026, 8); rl = [l for l in det(p["id"])["lines"] if l["kind"] == "report"]
chk("TC-014 2 report lines -600, ded 1200, net 16800, sent 1 missing 2", sorted(l["amount_minor"] for l in rl) == [-600, -600] and p["deductions_minor"] == 1200 and p["net_minor"] == 16800 and (p["reports_sent"], p["reports_missing"]) == (1, 2), f"{[(l['session_id'], l['amount_minor']) for l in rl]} {short(p, ['deductions_minor','net_minor','reports_sent','reports_missing'])}")
chk("reported session has no report line", ids[0] not in [l["session_id"] for l in rl])
c, j = a.post(f"/payroll/payslips/{p['id']}/issue/"); chk("TC-014 issue rebuilds same 16800", c == 200 and j["net_minor"] == 16800, f"{c} {j.get('net_minor')}")
a.patch("/payroll/settings/", {"report_deduction_bp": 0, "student_absent_pay_bp": 10000, "student_excused_pay_bp": 10000, "at_disposal_pays": False, "group_pay": "per_student"})
rc = S(); log("ratecreate login", rc.login(*PW["s_ratecreate"])); c, j = rc.post("/payroll/rates/bulk/", {"teachers": [ID["T1"]], "rates": [{"course": None, "hourly_rate_minor": 1}]}); chk("TC-016 create-only staff 403", c == 403, f"{c} {short(j)}")
c, j = ps.post("/payroll/rates/bulk/", {"teachers": [ID["T2"]], "rates": [{"course": None, "hourly_rate_minor": 12345}]}); chk("TC-016 full staff bulk 200", c == 200, f"{c} {short(j)}")
log("settings", q("select * from payroll_payrollsettings")); st_save(st); save("tc013-014-016-rerun.txt")
