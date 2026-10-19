from qa import *
st = st_load()
st["ids"] = {"T1": 7, "T2": 36, "T3": 37, "T4": 38, "T5": 39, "T6": 40, "T7": 41, "T8": 42, "T9": 43, "T10": 44, "T11": 45, "T12": 46, "T13": 47, "T14": 48, "TX": 49, "S1": 5, "S2": 32, "S3": 33, "C1": 1, "C2": 2}
a = S(); log("admin login", a.login(*PW["admin"]))
c, j = a.get("/features/"); log("features", c, short(j, n=200))
full = ["payslip.view","payslip.view_any","payslip.create","payslip.update","payroll_rate.view_any","payroll_rate.create","payroll_rate.update","payroll_rate.delete",
        "payroll_adjustment.view_any","payroll_adjustment.create","payroll_adjustment.update","payroll_adjustment.delete","payroll_settings.view","payroll_settings.update",
        "teacher_withdrawal.view_any","teacher_withdrawal.create","teacher_withdrawal.update"]
roles = {"pay": ("QA Payroll Full", full), "payread": ("QA Payroll Read", ["payslip.view_any","payslip.view"]),
         "ratecreate": ("QA Rate Create Only", ["payroll_rate.view_any","payroll_rate.create"]), "updnoview": ("QA Payslip Update NoView", ["payslip.update"])}
c, j = a.get("/access/roles/?page_size=100"); existing = {r["name_en"]: r["id"] for r in (j["results"] if isinstance(j, dict) else j)}
for k, (name, codes) in roles.items():
    if name in existing: rid = existing[name]
    else:
        c, j = a.post("/access/roles/", {"name_ar": name, "name_en": name, "permissions": codes}); log("role", name, c, short(j, n=150)); rid = j.get("id")
    st["ids"]["role_" + k] = rid
    email = f"qa-staff-{k}@qa.etqan.test"
    c, j = a.post("/access/staff/", {"full_name": f"QA Staff {k}", "email": email, "role_ids": [rid]}); log("staff", email, c, short(j, n=150))
st_save(st); save("setup.txt")
