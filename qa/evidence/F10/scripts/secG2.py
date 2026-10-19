from qa import *
st = st_load(); a = S(); a.login(*PW["admin"])
log("==== TC-029b: does one teacher's overflow block the whole month?")
sid = mk(a, "T13", "S1", "C1", "2026-04-12", "09:00", 60); st["sess"]["T13_apr"] = sid
a.patch(f"/payroll/rates/{st['rate_T14']}/", {"hourly_rate_minor": 9223372036854775807})
c, g = a.post("/payroll/payslips/generate/", {"year": 2026, "month": 4}); log("generate April", c, short(g))
log("T13 April payslip rows", q("select count(*) from payroll_payslip where teacher_id=14 and month=4 and year=2026"))
log("T14 April draft (pre-existing, 12000) unchanged?", q("select gross_minor from payroll_payslip where teacher_id=15 and month=4"))
a.patch(f"/payroll/rates/{st['rate_T14']}/", {"hourly_rate_minor": 6000}); c, g = a.post("/payroll/payslips/generate/", {"year": 2026, "month": 4}); log("restored generate", c, short(g))
st_save(st); save("tc029.txt")
