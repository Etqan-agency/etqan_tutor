from qa import *
st = st_load(); ss = st["sess"]; a = S(); a.login(*PW["admin"])
def slip(t, y, m):
    c, j = a.get(f"/payroll/payslips/?year={y}&month={m}&teacher={ID[t]}"); r = j["results"]; return r[0] if r else None
def det(pid): return a.get(f"/payroll/payslips/{pid}/")[1]
TOM = d(1)
log("==== TC-017", datetime.datetime.now().isoformat(), "today", TODAY)
a.post("/payroll/payslips/generate/", {"year": 2026, "month": 8})
draft = slip("T1", 2026, 10); paid = det(st["slip_T1_sep"]); iss = slip("T5", 2026, 8)  # T5 Aug issued in TC-009
c, j = a.post(f"/payroll/payslips/{draft['id']}/mark-paid/", {"paid_on": TODAY.isoformat()}); chk("mark-paid draft 409", c == 409 and j.get("code") == "payroll.not_allowed_in_status", f"{c} {short(j)}")
for p, lab in [(iss, "issued"), (paid, "paid")]:
    c, j = a.post(f"/payroll/payslips/{p['id']}/issue/"); chk(f"issue on {lab} 409", c == 409 and j.get("code") == "payroll.not_allowed_in_status", f"{c} {short(j)}")
c, j = a.post(f"/payroll/payslips/{paid['id']}/mark-paid/", {"paid_on": TODAY.isoformat()}); chk("mark-paid on paid 409", c == 409, f"{c} {short(j)}")
c, j = a.post(f"/payroll/payslips/{iss['id']}/mark-paid/", {"paid_on": TOM}); chk("paid_on tomorrow 400 on paid_on", c == 400 and "paid_on" in j, f"{c} {short(j)}")
c, j = a.post(f"/payroll/payslips/{iss['id']}/mark-paid/", {"paid_on": "2026-13-45"}); chk("paid_on malformed 400", c == 400 and "paid_on" in j, f"{c} {short(j)}")
log("T5 Aug unchanged", q(f"select status,paid_on,paid_by_id from payroll_payslip where id={iss['id']}"))
# pay-to-balance: T1 August -> issue then pay to balance (20000) with switch off then on
p8 = slip("T1", 2026, 8); log("T1 Aug draft", short(p8, ["id","gross_minor","net_minor"]))
c, j = a.post(f"/payroll/payslips/{p8['id']}/issue/"); log("issue T1 Aug", c, j.get("net_minor"))
log(features("qa", off=["teacher_balance"])); c, j = a.post(f"/payroll/payslips/{p8['id']}/pay-to-balance/", {"paid_on": TODAY.isoformat()}); chk("pay-to-balance off 403/404", c in (403, 404), f"{c} {short(j)}")
log(features("qa", on=["teacher_balance"]))
# impersonation: admin quick-logs in as T1
qi = S(); qi.login(*PW["admin"]); c, j = qi.post(f"/people/teachers/{ID['T1']}/quick-login/"); log("quick-login as T1", c, short(j, n=150))
c, j = qi.get("/identity/me/"); log("me under quick login", c, short(j, n=120))
for path, body in [(f"/payroll/payslips/{p8['id']}/pay-to-balance/", {"paid_on": TODAY.isoformat()}), (f"/payroll/payslips/{p8['id']}/mark-paid/", {"paid_on": TODAY.isoformat()}), (f"/payroll/payslips/{p8['id']}/issue/", {}), ("/payroll/payslips/generate/", {"year": 2026, "month": 8}), (f"/payroll/payslips/{st['slip_T1_sep']}/acknowledge/", {})]:
    c, j = qi.post(path, body); log("S3 impersonated", path.split("/")[-2], c, short(j, n=150))
st["imp_status"] = "see tc017"
c, j = a.post(f"/payroll/payslips/{p8['id']}/pay-to-balance/", {"paid_on": TODAY.isoformat()}); chk("pay-to-balance 200 paid_to_balance", c == 200 and j.get("paid_to_balance") and j["status"] == "paid", f"{c} {short(j, ['status','paid_to_balance','net_minor'])}")
c, j = a.post(f"/payroll/payslips/{p8['id']}/pay-to-balance/", {"paid_on": TODAY.isoformat()}); chk("pay-to-balance on paid 409", c == 409, f"{c} {short(j)}")
st["slip_T1_aug"] = p8["id"]; st_save(st); save("tc017.txt")

log("==== TC-018", datetime.datetime.now().isoformat())
E = lambda: q("select id,source_id,type,amount_minor,currency,spent_on,title from finance_expense where source='payroll.payslip' order by id")
log("expenses now", E())
chk("1 expense per paid payslip (T1 Sept, T1 Aug pay-to-balance)", q(f"select count(*) from finance_expense where source='payroll.payslip' and source_id={st['slip_T1_sep']}") == "1" and q(f"select amount_minor from finance_expense where source='payroll.payslip' and source_id={p8['id']}") == "20000")
# T5 Aug issued net 14000: switch off -> pay -> 0 expenses -> switch on -> not back-posted
log(features("qa", off=["salary_expenses"])); c, j = a.post(f"/payroll/payslips/{iss['id']}/mark-paid/", {"paid_on": TODAY.isoformat()}); log("pay T5 Aug off", c)
log(features("qa", on=["salary_expenses"])); chk("no expense for switch-off payment, not back-posted", q(f"select count(*) from finance_expense where source='payroll.payslip' and source_id={iss['id']}") == "0")
# S1 backdate: T7 Sept (generated, draft) -> issue -> paid_on 2026-01-01
p7 = slip("T7", 2026, 9); c, j = a.post(f"/payroll/payslips/{p7['id']}/issue/"); log("issue T7 Sept", c, j.get("net_minor"), j.get("issued_at"))
c, j = a.post(f"/payroll/payslips/{p7['id']}/mark-paid/", {"paid_on": "2026-01-01", "notes": "S1"}); log("S1 backdated paid_on 2026-01-01 on Sept payslip issued today:", c, short(j, ["status","paid_on"]))
log("S1 expense", q(f"select source_id,amount_minor,currency,spent_on from finance_expense where source='payroll.payslip' and source_id={p7['id']}"))
st["S1"] = [c, q(f"select spent_on from finance_expense where source='payroll.payslip' and source_id={p7['id']}")]
# S9: T11 Sept USD issued (TC-015) -> mark paid -> expense USD; finance summary
p11 = slip("T11", 2026, 9); c, j = a.post(f"/payroll/payslips/{p11['id']}/mark-paid/", {"paid_on": TODAY.isoformat()}); log("pay T11 USD", c, j.get("currency"), j.get("net_minor"))
log("S9 expense", q(f"select amount_minor,currency,title from finance_expense where source='payroll.payslip' and source_id={p11['id']}"))
for path in ["/finance/summary/", "/finance/expenses/?page_size=50", "/finance/reports/summary/", "/finance/overview/"]:
    c, j = a.get(path); log("finance", path, c, short(j, n=700))
# net-0 payslip: T9 has fixed 300000 ... use T14 March? make: T13 May? create deduction equal to pay for T12 May (gross 9000 per_student)
p12 = slip("T12", 2026, 5); log("T12 May", short(p12, ["gross_minor","net_minor"]))
c, Dd = a.post("/payroll/adjustments/", {"teacher": ID["T12"], "kind": "deduction", "amount_minor": p12["gross_minor"], "effective_on": "2026-05-20", "reason": "net0"})
a.post("/payroll/payslips/generate/", {"year": 2026, "month": 5}); p12 = slip("T12", 2026, 5); c, j = a.post(f"/payroll/payslips/{p12['id']}/issue/"); log("issue net0", c, j.get("net_minor"))
c, j = a.post(f"/payroll/payslips/{p12['id']}/mark-paid/", {"paid_on": TODAY.isoformat()}); chk("net-0 paid -> no expense", c == 200 and q(f"select count(*) from finance_expense where source='payroll.payslip' and source_id={p12['id']}") == "0", f"{c} net={j.get('net_minor')}")
dup = q("select source_id,count(*) from finance_expense where source='payroll.payslip' group by 1 having count(*)>1"); chk("expense unique per payslip", dup == "", dup)
chk("expense amount = net for every posted payslip", q("select count(*) from finance_expense e join payroll_payslip p on p.id=e.source_id where e.source='payroll.payslip' and (e.amount_minor<>p.net_minor or e.currency<>p.currency)") == "0")
log("all expenses", E())
st_save(st); save("tc018.txt")
