from qa import *
st = st_load()
a = S(); a.login(*PW["admin"])
def mk(kind, name, email, extra=None):
    ex = q(f"select id from identity_user where email='{email}'")
    if ex: return int(ex)
    body = {"user": {"full_name": name, "email": email}}
    if extra: body["profile"] = extra
    c, j = a.post(f"/people/{kind}/", body); log("create", kind, email, c, short(j, n=300))
    return j.get("id") if isinstance(j, dict) else None
st["S2"] = mk("students", "QA Student Two", "qa-student2@qa.etqan.test", {"country": "EG"})
st["S3"] = mk("students", "QA Student Three", "qa-student3@qa.etqan.test", {"country": "EG"})
st["P2"] = mk("parents", "QA Parent Two", "qa-parent2@qa.etqan.test")
st["P3"] = mk("parents", "QA Parent Three", "qa-parent3@qa.etqan.test")
log("ids", st)
for s_, p_ in [(5, 6), (st["S2"], st["P2"]), (st["S3"], st["P3"])]:
    c, j = a.post(f"/people/students/{s_}/guardians/", {"parent_id": p_}); log("guardian", s_, p_, c, short(j, n=200))
c, j = a.patch("/people/students/5/", {"profile": {"country": "EG"}}); log("S1 country", c, short(j, n=200))
c, j = a.patch("/people/families/1/", {"name": "QA Fam", "student_ids": [5, st["S3"]], "payer_id": st["P3"]}); log("family", c, short(j, n=400))
r = dc("exec","-T","django","python","manage.py","tenant_command","shell","--schema=academy_qa","-c",
 "from etqan.identity.models import User; [ (u.set_password('QA-People-2026!'), u.save()) for u in User.objects.filter(email__in=['qa-student2@qa.etqan.test','qa-parent2@qa.etqan.test','qa-student3@qa.etqan.test','qa-parent3@qa.etqan.test'])]")
log("pw", r[-200:])
for n in ["student2","parent2","parent3","student3"]:
    s = S(); log("login", n, s.login(*PW[n]))
B = ["invoice.view","invoice.view_any","invoice.create","invoice.update","payment.view_any","payment.create","payment.update","payment.delete","widget.revenue_stats","payment_method.view_any","payment_method.create","payment_method.update","payment_method.delete","checkout.view_any","checkout.update","payment_link.view_any","payment_link.create","payment_link.update","wallet.view_any","wallet.create","wallet.update","voucher.view_any","voucher.create","voucher.update","subscription.view","subscription.view_any","subscription.create","subscription.update","student.view","student.view_any","gateway.view","gateway.update"]
def role(name, perms):
    ex = q(f"select id from access_role where name_en='{name}' and is_active") if True else ""
    if ex and ex.isdigit(): return int(ex)
    c, j = a.post("/access/roles/", {"name_ar": name+" ع", "name_en": name, "permissions": perms}); log("role", name, c, short(j, n=500))
    return j.get("id") if isinstance(j, dict) else None
st["R_BILL"] = role("QA Billing", B)
st["R_NARROW"] = role("QA Billing Narrow", ["invoice.view","invoice.view_any","payment.view_any"])
c, j = a.patch("/access/staff/3/", {"role_ids": [3, st["R_BILL"]]}); log("staff3 roles", c, short(j, n=300))
c, j = a.post("/catalogue/courses/", {"name_ar":"تجويد","name_en":"Tajweed QA","teacher_ids":[7]}); log("course", c, short(j, n=300)); st["COURSE"] = j.get("id")
c, j = a.post("/catalogue/packages/", {"name_ar":"شهري","name_en":"Monthly QA","sessions_per_week":2,"session_minutes":30,"duration_value":1,"duration_unit":"month","price_minor":150000,"currency":"EGP"}); log("pkg", c, short(j, n=300)); st["PKG"] = j.get("id")
c, j = a.patch("/academy/settings/", {"auto_invoice_on_subscription": True, "invoice_due_days": 7}); log("acad settings", c, short(j, n=300))
c, j = a.patch("/gateways/settings/", {"stripe":{"enabled":True,"mode":"test","public_key":"pk_test_f09","secret":"sk_test_f09","webhook_secret":"whsec_qa_f09"},"fee":{"enabled":True,"basis_points":500}}); log("gw", c, short(j, n=600))
c, j = a.patch("/billing/settings/", {"local_payment_enabled": True}); log("billing settings", c, short(j, n=300))
log(dc("exec","-T","django","python","manage.py","shell","-c","from django.core.cache import cache; cache.clear()")[-100:])
for t in ['billing_invoice','billing_payment','wallet_walletentry','vouchers_voucher','gateways_checkout']:
    log("baseline", t, q(f'select count(*) from {t}'))
st_save(st); save("setup.txt")
