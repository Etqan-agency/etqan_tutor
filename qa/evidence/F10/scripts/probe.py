from qa import *
a = S(); a.login(*PW["admin"])
c0 = q("select last_number from payroll_payslipcounter"); log("counter before", c0)
for t, r in [("T1",6000),("T2",12345),("T3",6000),("T7",6000),("T8",6000),("T9",6000),("T10",6000),("T11",6000),("TX",6000),("T13",6000),("T5",6000),("T6",6000)]:
    c, j = a.post("/payroll/rates/", {"teacher": ID[t], "hourly_rate_minor": r}); log("rate", t, c, short(j, n=250))
c, j = a.get("/payroll/settings/"); log("settings", c, short(j))
c, j = a.patch("/payroll/settings/", {"student_absent_pay_bp": 5000, "student_excused_pay_bp": 2500}); log("settings patch", c, short(j))
c, j = a.post("/payroll/payslips/generate/", {"year": 2026, "month": 9}); log("generate", c, short(j, n=1500))
c, j = a.get(f"/payroll/payslips/?year=2026&month=9&teacher={ID['T1']}"); log("list", c, short(j, n=1500))
save("probe.txt")
