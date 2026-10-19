from qa import *
st = st_load(); a = S(); a.login(*PW["admin"])
log("== TC-012 second-code checks", datetime.datetime.now().isoformat())
c,j=a.post("/access/roles/",{"name_ar":"قسائم","name_en":"QA Voucher Only","permissions":["voucher.view_any","voucher.update","wallet.view_any","wallet.update","student.view","student.view_any"]}); vr=j["id"]; st["R_VONLY"]=vr
a.patch("/access/staff/3/",{"role_ids":[vr]}); s=S(); s.login(*PW["staffc"])
c,j=a.post("/vouchers/batches/",{"kind":"discount","quantity":1,"valid_days":30,"discount_kind":"percent","discount_value":5}); code=q(f"select code from vouchers_voucher where batch_id={j['id']}")
I=a.post("/billing/invoices/",{"student":5,"amount_minor":10000,"due_on":d(7),"description":"2nd code"})[1]["id"]
c,j=s.post("/vouchers/codes/redeem/",{"code":code,"invoice":I}); log("office redeem w/o payment.create",c,short(j)); chk("TC012 office redeem without payment.create/invoice.view 403 naming code", c==403 and ("payment.create" in str(j) or "invoice.view" in str(j)))
used=q("select id from vouchers_voucher where status='used' and kind='discount' limit 1")
c,j=s.post(f"/vouchers/codes/{used}/remove-discount/",{"reason":"x"}); log("remove w/o payment.update",c,short(j)); chk("TC012 remove-discount without payment.update 403", c==403 and "payment.update" in str(j))
pm=q("select id from billing_payment where invoice_id is not null and status='completed' and method='cash' limit 1")
c,j=s.post(f"/wallet/payments/{pm}/move/",{}); log("move w/o payment.update",c,short(j)); chk("TC012 wallet move without payment.update 403", c==403 and "payment.update" in str(j))
chk("TC012 nothing changed", q(f"select status from billing_payment where id={pm}")=="completed" and q(f"select count(*) from billing_payment where invoice_id={I}")=="0")
a.patch("/access/staff/3/",{"role_ids":[3,st["R_BILL"]]})
st_save(st); save("tc012.txt")
