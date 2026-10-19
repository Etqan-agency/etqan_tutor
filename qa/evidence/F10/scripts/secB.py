from qa import *
st = st_load(); ss = st["sess"]; a = S(); a.login(*PW["admin"])
def slip(t, y, m):
    c, j = a.get(f"/payroll/payslips/?year={y}&month={m}&teacher={ID[t]}"); r = j["results"]; return r[0] if r else None
def det(pid): return a.get(f"/payroll/payslips/{pid}/")[1]
log("==== TC-007", datetime.datetime.now().isoformat())
before = q("select id,number,status,net_minor,updated_at from payroll_payslip where year=2026 and month=9 order by id")
c1, g1 = a.post("/payroll/payslips/generate/", {"year": 2026, "month": 9}); c2, g2 = a.post("/payroll/payslips/generate/", {"year": 2026, "month": 9})
log("gen x2", c1, short(g1), c2, short(g2))
after = q("select id,number,status,net_minor,updated_at from payroll_payslip where year=2026 and month=9 order by id")
chk("same ids/numbers after 2 generates", [l.split("|")[:2] for l in before.splitlines()] == [l.split("|")[:2] for l in after.splitlines()])
chk("paid T1 row untouched", [l for l in before.splitlines() if l.startswith(f"{st['slip_T1_sep']}|")] == [l for l in after.splitlines() if l.startswith(f"{st['slip_T1_sep']}|")])
res = par([lambda: a.post("/payroll/payslips/generate/", {"year": 2026, "month": 9})[0] for _ in range(4)])
chk("4 parallel generates all 200", res == [200]*4, str(res))
dup = q("select teacher_id,year,month,count(*) from payroll_payslip group by 1,2,3 having count(*)>1"); chk("no duplicate (teacher,year,month)", dup == "", dup)
r = q(f"insert into payroll_payslip (number,teacher_id,year,month,status,currency,gross_minor,bonuses_minor,deductions_minor,net_minor,missing_rate,created_at,updated_at) select 'PAY-DUPTEST',teacher_id,year,month,'draft','EGP',0,0,0,0,false,now(),now() from payroll_payslip where id={st['slip_T1_sep']}")
chk("DB unique violation on duplicate", "duplicate key" in r or "violates" in r, r[:200])
# removal: cancel TX's only Sept session -> draft removed; then restore -> new draft with NEW number (S7)
px = slip("TX", 2026, 9); num0 = px["number"]
c, j = a.post(f"/sessions/{ss['TX_sep']}/cancel/", {"reason": "F10 S7"}); log("cancel TX", c)
c, g = a.post("/payroll/payslips/generate/", {"year": 2026, "month": 9}); chk("draft removed when nothing left", g["removed"] >= 1 and slip("TX", 2026, 9) is None, short(g))
c, j = a.post(f"/sessions/{ss['TX_sep']}/restore/"); log("restore TX", c, short(j, ["status"]))
if j.get("status") != "completed": a.post(f"/sessions/{ss['TX_sep']}/attendance/", {"student_attendance": "present", "teacher_attendance": "present"})
c, g = a.post("/payroll/payslips/generate/", {"year": 2026, "month": 9}); px2 = slip("TX", 2026, 9)
log("S7: TX draft number before", num0, "after re-create", px2 and px2["number"], "counter", q("select last_number from payroll_payslipcounter"))
st["S7"] = [num0, px2 and px2["number"]]
save("tc007.txt")

log("==== TC-008", datetime.datetime.now().isoformat())
c, j = a.post(f"/sessions/{ss['T1_0903']}/attendance/", {"student_attendance": "absent"}); chk("attendance on locked session 409 payroll.payslip_issued", c == 409 and j.get("code") == "payroll.payslip_issued", f"{c} {short(j)}")
c, j = a.post("/sessions/extra/", {"student": ID["S1"], "course": 1, "teacher": ID["T1"], "occurs_on": "2026-09-24", "start_time": "10:00", "minutes": 60}); late = j["session"]["id"]; ss["T1_late"] = late
c, j = a.post(f"/sessions/{late}/attendance/", {"student_attendance": "present", "teacher_attendance": "present"}); log("late marked", c, j.get("status"))
c, g = a.post("/payroll/payslips/generate/", {"year": 2026, "month": 9}); chk("unpaid_sessions lists T1 late session", "unpaid_sessions" in g and str(late) in json.dumps(g["unpaid_sessions"]), short(g["unpaid_sessions"]))
p1 = det(st["slip_T1_sep"]); chk("T1 Sept payslip unchanged 13500 paid", (p1["status"], p1["net_minor"]) == ("paid", 13500))
c, j = a.post("/payroll/adjustments/", {"teacher": ID["T1"], "kind": "bonus", "amount_minor": 6000, "effective_on": "2026-10-05", "reason": "late Sept session"}); log("bonus", c, short(j, n=200)); st["adj_T1_late"] = j.get("id")
a.post("/payroll/payslips/generate/", {"year": 2026, "month": 10}); po = slip("T1", 2026, 10); dl = det(po["id"])["lines"]
chk("Oct has no late Sept session line", late not in [l.get("session_id") for l in dl], str([(l["kind"], l.get("session_id"), l["amount_minor"]) for l in dl]))
chk("Oct has adjustment line 6000", any(l["kind"] == "adjustment" and l["amount_minor"] == 6000 for l in dl))
log("DB late", q(f"select payroll_locked from scheduling_session where id={late}"), "lines", q(f"select count(*) from payroll_payslipline where session_id={late}"))
st_save(st); save("tc008.txt")

log("==== TC-004", datetime.datetime.now().isoformat())
c, j = a.post("/payroll/rates/", {"teacher": ID["T4"], "hourly_rate_minor": 6000}); log("T4 default", c); st["rate_T4_def"] = j.get("id")
c, j = a.post("/payroll/rates/", {"teacher": ID["T4"], "course": 2, "hourly_rate_minor": 9000}); log("T4 C2", c); st["rate_T4_c2"] = j.get("id")
c, j = a.post("/payroll/student-rates/", {"teacher": ID["T4"], "student": ID["S2"], "hourly_rate_minor": 12000}); log("T4 S2", c, short(j, n=200)); st["srate_T4"] = j.get("id")
c, j = a.post("/payroll/rates/", {"teacher": ID["T4"], "hourly_rate_minor": 7000}); chk("dup default 400", c == 400, f"{c} {short(j)}")
c, j = a.post("/payroll/rates/", {"teacher": ID["T4"], "course": 2, "hourly_rate_minor": 7000}); chk("dup course 400", c == 400, f"{c} {short(j)}")
a.post("/payroll/payslips/generate/", {"year": 2026, "month": 8})
def amts():
    p = slip("T4", 2026, 8); return {l["session_id"]: l["amount_minor"] for l in det(p["id"])["lines"] if l["kind"] == "session"}
m = amts(); exp = {ss["T4_11"]: 6000, ss["T4_12"]: 9000, ss["T4_21"]: 12000, ss["T4_22"]: 12000}; chk("precedence on", m == exp, str(m))
log(features("qa", off=["student_teacher_rate"]))
c, j = a.post("/payroll/student-rates/", {"teacher": ID["T4"], "student": ID["S3"], "hourly_rate_minor": 1}); chk("student-rates gated off", c in (403, 404), f"{c} {short(j)}")
a.post("/payroll/payslips/generate/", {"year": 2026, "month": 8}); m = amts()
exp2 = {ss["T4_11"]: 6000, ss["T4_12"]: 9000, ss["T4_21"]: 6000, ss["T4_22"]: 9000}; chk("switch off falls back", m == exp2, str(m))
log("srate row survives", q("select id,teacher_id,student_id,hourly_rate_minor,currency from payroll_studentrate"))
log(features("qa", on=["student_teacher_rate"])); a.post("/payroll/payslips/generate/", {"year": 2026, "month": 8}); chk("on again", amts() == exp)
st_save(st); save("tc004.txt")
