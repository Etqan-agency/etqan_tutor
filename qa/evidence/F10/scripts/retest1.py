from qa import *
import qa
qa.EVD = qa.EVD + "/retest-1"
a = S(); a.login(*PW["admin"])
def exp(pid): return q(f"select count(*)||':'||coalesce(string_agg(amount_minor||'|'||currency||'|'||spent_on,','),'') from finance_expense where source='payroll.payslip' and source_id={pid}")
def st(pid): return q(f"select status||'|'||coalesce(paid_on::text,'-')||'|'||paid_to_balance from payroll_payslip where id={pid}")
log("==== ETQAN-QA-029 retest-1 (REAL)", datetime.datetime.now().isoformat(), "TODAY", TODAY)
# 1 original repro, issued Aug slip 19
c, j = a.post("/payroll/payslips/19/mark-paid/", {"paid_on": "2026-01-01", "notes": "S1"}); chk("orig repro mark-paid 2026-01-01 -> 400 paid_on", c == 400 and "paid_on" in j, f"{c} {j}")
chk("DB slip 19 still issued, no expense", st(19).startswith("issued|-") and exp(19).startswith("0:"), f"{st(19)} {exp(19)}")
c, j = a.post("/payroll/payslips/19/mark-paid/", {"paid_on": "2026-07-31"}); chk("mark-paid day before month (07-31) -> 400", c == 400 and "paid_on" in j, f"{c} {j}")
c, j = a.post("/payroll/payslips/19/mark-paid/", {"paid_on": d(1)}); chk("future still 400", c == 400 and "paid_on" in j, f"{c} {j}")
c, j = a.post("/payroll/payslips/19/mark-paid/", {"paid_on": "2026-08-01"}); chk("month first day 08-01 -> 200 paid", c == 200 and j["status"] == "paid" and j["paid_on"] == "2026-08-01", f"{c} {short(j,['status','paid_on','net_minor'])}")
chk("DB 19 paid + expense 6000 EGP spent_on 2026-08-01", st(19).startswith("paid|2026-08-01") and exp(19) == "1:6000|EGP|2026-08-01", f"{st(19)} {exp(19)}")
c, j = a.post("/payroll/payslips/19/mark-paid/", {"paid_on": "2026-08-01"}); chk("pay again 409", c == 409, f"{c} {j}")
# 2 pay-to-balance, issued Jul slip 24
c, s24 = a.get("/payroll/payslips/24/"); tu = s24["teacher"]["id"]
def bal(): return json.dumps(a.get(f"/payroll/balances/?teacher={tu}")[1])
b0 = bal(); log("balance before", b0)
c, j = a.post("/payroll/payslips/24/pay-to-balance/", {"paid_on": "2026-06-30"}); chk("pay-to-balance 06-30 for July slip -> 400 paid_on", c == 400 and "paid_on" in j, f"{c} {j}")
c, j = a.post("/payroll/payslips/24/pay-to-balance/", {"paid_on": "2026-01-01"}); chk("pay-to-balance 01-01 -> 400", c == 400 and "paid_on" in j, f"{c} {j}")
chk("DB 24 still issued, no expense, balance unchanged", st(24).startswith("issued|-") and exp(24).startswith("0:") and bal() == b0, f"{st(24)} {exp(24)} {bal()}")
c, j = a.post("/payroll/payslips/24/pay-to-balance/", {"paid_on": "2026-07-01"}); chk("pay-to-balance 07-01 -> 200", c == 200 and j["status"] == "paid" and j.get("paid_to_balance") is True, f"{c} {short(j,['status','paid_on','paid_to_balance','net_minor'])}")
chk("DB 24 paid_to_balance + expense spent_on 07-01", st(24).startswith("paid|2026-07-01|t") and exp(24).endswith("|2026-07-01"), f"{st(24)} {exp(24)}")
log("balance after", bal(), "(net 4000 expected credited)")
# 3 slip 13 July: last day of month & today accepted
c, j = a.post("/payroll/payslips/13/mark-paid/", {"paid_on": TODAY.isoformat()}); chk("slip 13 paid today -> 200", c == 200 and j["paid_on"] == TODAY.isoformat(), f"{c} {short(j,['status','paid_on'])}")
chk("DB 13 expense spent_on today", exp(13) == f"1:6000|EGP|{TODAY}", exp(13))
# 4 non-admin staff/teacher still refused
t = S(); t.login(*PW["T1"]); c, j = t.post("/payroll/payslips/25/mark-paid/", {"paid_on": TODAY.isoformat()}); chk("teacher mark-paid 403/404", c in (403, 404), f"{c}")
save("api-db.txt")
