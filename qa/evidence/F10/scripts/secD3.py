from qa import *
a = S(); a.login(*PW["admin"])
def g(): a.post("/payroll/payslips/generate/", {"year": 2026, "month": 9}); return a.get(f"/payroll/payslips/?year=2026&month=9&teacher={ID['T2']}")[1]["results"][0]["gross_minor"]
log("==== secD3 TC-013 rules-off recheck (T2 rate back to 12345; earlier 21583 = 100% of a 7000 rate left by TC-016 bulk)")
log("rate", q("select hourly_rate_minor from payroll_teacherrate where teacher_id=3 and course_id is null"))
a.patch("/payroll/settings/", {"student_absent_pay_bp": 5000, "student_excused_pay_bp": 2500})
chk("rules on 26491", g() == 26491)
log(features("qa", off=["payroll_rules"])); v = g(); chk("rules off 100%: 38065", v == 9259+6173+4115+9259+9259, str(v))
log(features("qa", on=["payroll_rules"])); chk("rules on again 26491", g() == 26491)
a.patch("/payroll/settings/", {"student_absent_pay_bp": 10000, "student_excused_pay_bp": 10000}); save("tc013-014-016-rerun.txt")
