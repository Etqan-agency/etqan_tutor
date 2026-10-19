from qa import *
st = st_load(); ss = st["sess"]; a = S(); a.login(*PW["admin"])
def slip(t, y, m):
    c, j = a.get(f"/payroll/payslips/?year={y}&month={m}&teacher={ID[t]}"); r = j["results"]; return r[0] if r else None
def det(pid): return a.get(f"/payroll/payslips/{pid}/")[1]
def adj(**b): return a.post("/payroll/adjustments/", {"reason": "F10", **b})
log("==== TC-009", datetime.datetime.now().isoformat()); T = ID["T5"]
c, A = adj(teacher=T, kind="bonus", amount_minor=2500, effective_on="2026-08-15"); log("A", c)
c, B = adj(teacher=T, kind="deduction", amount_minor=1000, effective_on="2026-08-20"); log("B", c)
c, C = adj(teacher=T, kind="bonus", amount_minor=700, effective_on="2026-09-02"); log("C", c)
for b in [dict(amount_minor=0), dict(amount_minor=-5), dict(amount_minor=100, percent_bp=100), dict()]:
    c, j = adj(teacher=T, kind="bonus", effective_on="2026-08-15", **b); chk(f"bad {b} 400", c == 400, f"{c} {short(j)}")
c, j = a.patch(f"/payroll/adjustments/{A['id']}/", {"amount_minor": 3000}); chk("PATCH A unused ok", c == 200 and j["amount_minor"] == 3000, str(c))
c, j = a.delete(f"/payroll/adjustments/{B['id']}/"); chk("DELETE B unused ok", c in (200, 204), str(c))
c, B = adj(teacher=T, kind="deduction", amount_minor=1000, effective_on="2026-08-20"); log("B again", c)
a.post("/payroll/payslips/generate/", {"year": 2026, "month": 8}); p = slip("T5", 2026, 8); dl = det(p["id"])["lines"]
chk("Aug gross 12000 bonus 3000 ded 1000 net 14000", (p["gross_minor"], p["bonuses_minor"], p["deductions_minor"], p["net_minor"]) == (12000, 3000, 1000, 14000), short(p, ["gross_minor","bonuses_minor","deductions_minor","net_minor"]))
chk("C not on August", all(l["amount_minor"] != 700 for l in dl)); chk("deduction line negative", any(l["kind"] == "adjustment" and l["amount_minor"] == -1000 for l in dl), str([(l["kind"], l["amount_minor"]) for l in dl]))
log("before issue payslip_id", q(f"select id,payslip_id from payroll_payadjustment where teacher_id={6} order by id"))
c, j = a.post(f"/payroll/payslips/{p['id']}/issue/"); log("issue", c, j.get("net_minor"))
log("after issue payslip_id", q(f"select id,payslip_id from payroll_payadjustment where teacher_id=6 order by id"))
c, j = a.patch(f"/payroll/adjustments/{A['id']}/", {"amount_minor": 1}); chk("PATCH used 409 adjustment_used", c == 409 and j.get("code") == "payroll.adjustment_used", f"{c} {short(j)}")
c, j = a.delete(f"/payroll/adjustments/{A['id']}/"); chk("DELETE used 409", c == 409 and j.get("code") == "payroll.adjustment_used", f"{c} {short(j)}")
c, j = a.get(f"/payroll/adjustments/?teacher={T}&used=false"); chk("used=false returns C only", [x["id"] for x in j["results"]] == [C["id"]], str([x["id"] for x in j["results"]]))
a.post("/payroll/payslips/generate/", {"year": 2026, "month": 9}); p9 = slip("T5", 2026, 9)
chk("Sept: C applied once, A not again", p9 and p9["bonuses_minor"] == 700 and p9["net_minor"] == 700, short(p9, ["bonuses_minor","net_minor"]))
save("tc009.txt")

log("==== TC-005b S5 (issue order moves adjustments)")
# T5 has pending C (eff 09-02). Create October completed session for T5, generate Oct, Oct draft also picks C? (effective_on <= month end)
c, j = a.post("/sessions/extra/", {"student": ID["S1"], "course": 1, "teacher": T, "occurs_on": "2026-10-03", "start_time": "14:00", "minutes": 60}); sid = j["session"]["id"]
a.post(f"/sessions/{sid}/attendance/", {"student_attendance": "present", "teacher_attendance": "present"})
a.post("/payroll/payslips/generate/", {"year": 2026, "month": 10}); p10 = slip("T5", 2026, 10)
log("S5: Sept draft bonuses", slip("T5", 2026, 9)["bonuses_minor"], "| Oct draft bonuses", p10["bonuses_minor"], "(same pending adjustment C shown on BOTH drafts)")
st["S5"] = [slip("T5", 2026, 9)["bonuses_minor"], p10["bonuses_minor"]]
save("tc009.txt")

log("==== TC-010", datetime.datetime.now().isoformat()); T = ID["T6"]
c, P = adj(teacher=T, kind="bonus", percent_bp=1250, effective_on="2026-06-10", reason="target"); chk("percent bonus 201", c == 201 and P["amount_minor"] is None, f"{c} {short(P)}")
a.post("/payroll/payslips/generate/", {"year": 2026, "month": 6}); p = slip("T6", 2026, 6); dl = det(p["id"])["lines"]
chk("bonus 1688 (1687.5 half-up) net 15188", (p["gross_minor"], p["bonuses_minor"], p["net_minor"]) == (13500, 1688, 15188), short(p, ["gross_minor","bonuses_minor","net_minor"]))
log("line text", [l.get("description") for l in dl if l["kind"] == "adjustment"])
for b, f in [(dict(kind="deduction", percent_bp=500), "kind"), (dict(kind="bonus", percent_bp=500, amount_minor=5), "amount_minor"), (dict(kind="bonus", percent_bp=0), "percent_bp"), (dict(kind="bonus", percent_bp=10001), "percent_bp")]:
    c, j = adj(teacher=T, effective_on="2026-06-10", **b); chk(f"{b} 400 on {f}", c == 400 and f in (j or {}), f"{c} {short(j)}")
log(features("qa", off=["incentives_deductions"]))
c, j = adj(teacher=T, kind="bonus", percent_bp=500, effective_on="2026-06-10"); chk("percent with switch off 400", c == 400, f"{c} {short(j)}")
a.post("/payroll/payslips/generate/", {"year": 2026, "month": 6}); p = slip("T6", 2026, 6); chk("off: skipped", p["bonuses_minor"] == 0 and p["net_minor"] == 13500, short(p, ["bonuses_minor","net_minor"]))
log(features("qa", on=["incentives_deductions"]))
a.post("/payroll/payslips/generate/", {"year": 2026, "month": 6}); p = slip("T6", 2026, 6); chk("on again applied", p["bonuses_minor"] == 1688)
# gross 0 case: T14 percent bonus effective 2026-03 (no sessions in March)
c, j = adj(teacher=ID["T14"], kind="bonus", percent_bp=1000, effective_on="2026-03-10"); st["adj_T14_pct"] = j.get("id")
c, g = a.post("/payroll/payslips/generate/", {"year": 2026, "month": 3}); p = slip("T14", 2026, 3)
log("gross-0 percent: payslip", short(p, ["id","gross_minor","bonuses_minor","net_minor"]) if p else None, "| adj used", q(f"select payslip_id from payroll_payadjustment where id={j.get('id')}"))
log("DB", q(f"select id,kind,amount_minor,percent_bp,currency from payroll_payadjustment where teacher_id=7"))
save("tc010.txt")

log("==== TC-011", datetime.datetime.now().isoformat())
c, j = a.post("/sessions/extra/", {"student": ID["S1"], "course": 1, "teacher": ID["T9"], "occurs_on": "2026-07-20", "start_time": "18:00", "minutes": 60}); sid = j["session"]["id"]; ss["T9_jul"] = sid
a.post(f"/sessions/{sid}/attendance/", {"student_attendance": "present", "teacher_attendance": "present"})
c, D = adj(teacher=ID["T9"], kind="deduction", amount_minor=9000, effective_on="2026-07-25")
a.post("/payroll/payslips/generate/", {"year": 2026, "month": 7}); p = slip("T9", 2026, 7); chk("draft net -3000", p["net_minor"] == -3000, str(p["net_minor"]))
c, j = a.post(f"/payroll/payslips/{p['id']}/issue/"); chk("issue 409 negative_net", c == 409 and j.get("code") == "payroll.negative_net", f"{c} {short(j)}")
log("after 409", q(f"select payslip_id from payroll_payadjustment where id={D['id']}"), q(f"select payroll_locked from scheduling_session where id={sid}"), q(f"select status from payroll_payslip where id={p['id']}"))
a.patch(f"/payroll/adjustments/{D['id']}/", {"amount_minor": 2000}); c, j = a.post(f"/payroll/payslips/{p['id']}/issue/"); chk("issue 200 net 4000", c == 200 and j["net_minor"] == 4000, f"{c} {short(j, ['net_minor','status'])}")
st_save(st); save("tc011.txt")

log("==== TC-012", datetime.datetime.now().isoformat())
c, F = a.post("/payroll/fixed-salaries/", {"teacher": ID["T8"], "monthly_minor": 500000, "starts_on": "2026-09-17"}); chk("fixed 201 snapped to 09-01", c == 201 and F["starts_on"] == "2026-09-01", f"{c} {short(F)}"); st["fixed_T8"] = F.get("id")
c, j = a.post("/payroll/fixed-salaries/", {"teacher": ID["T8"], "monthly_minor": 1, "starts_on": "2026-09-01"}); chk("second 409 fixed_salary_exists", c == 409 and j.get("code") == "payroll.fixed_salary_exists", f"{c} {short(j)}")
c, j = a.post("/payroll/fixed-salaries/", {"teacher": ID["T9"], "monthly_minor": 0, "starts_on": "2026-09-01"}); chk("monthly 0 400", c == 400, f"{c} {short(j)}")
c, F9 = a.post("/payroll/fixed-salaries/", {"teacher": ID["T9"], "monthly_minor": 300000, "starts_on": "2026-09-01"}); st["fixed_T9"] = F9.get("id")
a.post("/payroll/payslips/generate/", {"year": 2026, "month": 9}); p = slip("T8", 2026, 9); dl = det(p["id"])["lines"]
chk("T8 fixed line 500000, sessions 0, gross 500000", p["gross_minor"] == 500000 and any(l["kind"] == "fixed" and l["amount_minor"] == 500000 for l in dl) and all(l["amount_minor"] == 0 for l in dl if l["kind"] == "session"), str([(l["kind"], l["amount_minor"]) for l in dl]))
# deactivate T9 then generate Nov (no sessions)
log("deactivate T9", dc("exec", "-T", "django", "python", "manage.py", "tenant_command", "shell", "--schema=academy_qa", "-c", f"from etqan.identity.models import User; u=User.objects.get(pk={ID['T9']}); u.is_active=False; u.save(); print('ok')").splitlines()[-1])
c, g = a.post("/payroll/payslips/generate/", {"year": 2026, "month": 11}); log("gen Nov", short(g))
log("S8 Nov drafts", q("select p.teacher_id,p.number,p.status,p.gross_minor from payroll_payslip p where year=2026 and month=11"))
c, g = a.post("/payroll/payslips/generate/", {"year": 2099, "month": 12}); log("S8 gen 2099-12", c, short(g)); log("2099 drafts", q("select teacher_id,number,gross_minor from payroll_payslip where year=2099"))
st["S8"] = q("select teacher_id,number,gross_minor from payroll_payslip where year=2099")
log(features("qa", off=["fixed_teacher_salary"])); a.post("/payroll/payslips/generate/", {"year": 2026, "month": 9}); p = slip("T8", 2026, 9)
chk("switch off: fixed line gone, sessions priced", p["gross_minor"] == 6000, str(p["gross_minor"])); log("fixed rows stay", q("select id,teacher_id,monthly_minor,starts_on,currency from payroll_fixedsalary"))
log(features("qa", on=["fixed_teacher_salary"])); a.post("/payroll/payslips/generate/", {"year": 2026, "month": 9})
p = slip("T8", 2026, 9); c, j = a.post(f"/payroll/payslips/{p['id']}/issue/"); log("issue T8 Sept", c, j.get("net_minor"))
c, j = a.post("/sessions/extra/", {"student": ID["S1"], "course": 1, "teacher": ID["T8"], "occurs_on": "2026-09-25", "start_time": "17:00", "minutes": 60}); sid = j["session"]["id"]
a.post(f"/sessions/{sid}/attendance/", {"student_attendance": "present", "teacher_attendance": "present"})
c, g = a.post("/payroll/payslips/generate/", {"year": 2026, "month": 9}); chk("fixed teacher late session NOT in unpaid_sessions", ID["T8"] not in [x["id"] for x in g["unpaid_sessions"]], short(g["unpaid_sessions"]))
chk("missing_rate false for fixed", not p["missing_rate"])
# cleanup 2099 drafts via regenerate after deleting? leave; record
log("reactivate T9", dc("exec", "-T", "django", "python", "manage.py", "tenant_command", "shell", "--schema=academy_qa", "-c", f"from etqan.identity.models import User; u=User.objects.get(pk={ID['T9']}); u.is_active=True; u.save(); print('ok')").splitlines()[-1])
st_save(st); save("tc012.txt")
