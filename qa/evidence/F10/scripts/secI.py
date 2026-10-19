from qa import *
st = st_load(); a = S(); a.login(*PW["admin"]); o = oadmin()
QOT, QOC, QOS = 4, 1, 3
log("==== TC-024", datetime.datetime.now().isoformat())
cnt = lambda sch: q(" union all ".join(f"select '{t}',count(*) from {t}" for t in ["payroll_payslip","payroll_teacherrate","payroll_payadjustment","payroll_withdrawalrequest","payroll_fixedsalary","finance_expense"]), sch)
QO0 = cnt("academy_qaother")
c, r = o.post("/payroll/rates/", {"teacher": QOT, "hourly_rate_minor": 2000}); log("qo rate", c, short(r, n=150))
c, j = o.post("/sessions/extra/", {"student": QOS, "course": QOC, "teacher": QOT, "occurs_on": "2026-09-05", "start_time": "10:00", "minutes": 60}); log("qo session", c); sid = j["session"]["id"]
c, j = o.post(f"/sessions/{sid}/attendance/", {"student_attendance": "present", "teacher_attendance": "present"}); log("qo mark", c)
c, ad = o.post("/payroll/adjustments/", {"teacher": QOT, "kind": "bonus", "amount_minor": 500, "effective_on": "2026-09-10", "reason": "F10"}); log("qo adj", c)
c, fx = o.post("/payroll/fixed-salaries/", {"teacher": QOT, "monthly_minor": 1000, "starts_on": "2026-12-01"}); log("qo fixed", c, short(fx, n=120))
c, g = o.post("/payroll/payslips/generate/", {"year": 2026, "month": 9}); log("qo generate", c, short(g))
ps = o.get("/payroll/payslips/")[1]["results"][0]; log("qo payslip", short(ps, ["id","number","currency","net_minor"]))
o.post(f"/payroll/payslips/{ps['id']}/issue/"); c, j = o.post(f"/payroll/payslips/{ps['id']}/pay-to-balance/", {"paid_on": TODAY.isoformat()}); log("qo pay-to-balance", c, short(j, ["status","net_minor","currency"]))
qt = S(QO); log("qo teacher login", qt.login("qo-teacher@qa.etqan.test", "QA-People-2026!")); c, wd = qt.post("/payroll/withdrawals/", {"amount_minor": 100, "currency": "USD"}); log("qo withdrawal", c)
QO_ID = {"payslip": ps["id"], "rate": r["id"], "adj": ad["id"], "wd": wd["id"], "fixed": fx["id"]}; st["QO"] = QO_ID; log("qaother ids", QO_ID)
log("qo payslip number", ps["number"], "| qa has", q(f"select number from payroll_payslip where number='{ps['number']}'"))
QA_snap = cnt("academy_qa"); QO_snap = cnt("academy_qaother")
# qa admin reading qaother-only ids from qa host
QA_max = {"payslip": q("select max(id) from payroll_payslip"), "wd": q("select max(id) from payroll_withdrawalrequest"), "adj": q("select max(id) from payroll_payadjustment"), "rate": q("select max(id) from payroll_teacherrate"), "fixed": q("select max(id) from payroll_fixedsalary")}
log("qa max ids", QA_max)
for k, path in [("payslip", "/payroll/payslips/{}/"), ("adj", "/payroll/adjustments/{}/"), ("rate", "/payroll/rates/{}/"), ("wd", "/payroll/withdrawals/{}/"), ("fixed", "/payroll/fixed-salaries/{}/")]:
    i = QO_ID[k]; c, j = a.get(path.format(i)); m = "GET"
    if c == 405: c, j = a.patch(path.format(i), {}); m = "PATCH"
    same = int(QA_max[k] or 0) >= i
    if same: chk(f"qa {m} {path.format(i)} (id exists in both) returns qa's own row, not qaother's", c in (200, 400) and json.dumps(j).find("QO Teacher") < 0, f"{c} {short(j, n=150)}")
    else: chk(f"qa {m} {path.format(i)} (qaother-only id) 404", c == 404, f"{c}")
# reverse: qaother admin to qa ids
for k, path, i in [("payslip", "/payroll/payslips/{}/", st["slip_T1_sep"]), ("wd", "/payroll/withdrawals/{}/", 1), ("adj", "/payroll/adjustments/{}/", st["adj_T1_late"])]:
    c, j = o.get(path.format(i)); m = "GET"
    if c == 405: c, j = o.patch(path.format(i), {}); m = "PATCH"
    chk(f"qaother {m} qa {k} {i}: not qa's data", c == 404 or "QA teacher" not in json.dumps(j), f"{c} {short(j, n=150)}")
c, j = a.get("/payroll/payslips/", host=QO); chk("qa cookie against qaother host 401/403", c in (401, 403), f"{c}")
c, j = a.post("/payroll/payslips/generate/", {"year": 2026, "month": 9}, host=QO); chk("qa cookie generate on qaother refused", c in (401, 403), str(c))
c, j = o.get("/payroll/payslips/"); chk("qaother list only own", all("QO" in x["teacher"]["full_name"] for x in j["results"]), str([x["teacher"]["full_name"] for x in j["results"]]))
c, j = a.get("/payroll/payslips/?page_size=200"); chk("qa list has no qaother teacher", "QO Teacher" not in json.dumps(j))
c, j = a.post("/payroll/rates/", {"teacher": QOT, "hourly_rate_minor": 1}); log("qa POST rate teacher=qaother id 4", c, short(j))
chk("qa POST rates with qaother teacher id does not create for qaother", q("select count(*) from payroll_teacherrate", "academy_qaother") == [l for l in QO_snap.splitlines() if l.startswith("payroll_teacherrate")][0].split("|")[1])
a.post("/payroll/payslips/generate/", {"year": 2026, "month": 9})
chk("qa writes changed nothing in academy_qaother", cnt("academy_qaother") == QO_snap, cnt("academy_qaother"))
log("qaother expense", q("select source_id,amount_minor,currency,spent_on from finance_expense where source='payroll.payslip'", "academy_qaother"))
chk("qaother salary expense only in qaother schema", q(f"select count(*) from finance_expense where source='payroll.payslip' and title like '%QO Teacher%'") == "0")
st_save(st); save("tc024.txt")
