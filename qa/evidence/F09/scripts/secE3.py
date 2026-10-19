from qa import *
st = st_load(); a = S(); a.login(*PW["admin"])
def codes(batch, status="unused"): return [x for x in q(f"select code from vouchers_voucher where batch_id={batch} and status='{status}' order by id").split("\n") if x]
def disp(c): return f"SYS-{c[:5]}-{c[5:]}"
dc("exec","-T","django","python","manage.py","shell","-c","from django.core.cache import cache; cache.clear()")
log("== TC-021", datetime.datetime.now().isoformat())
act=codes(st["DACT"]); ren=codes(st["DREN"]); log("act",act,"ren",ren)
par_=S(); par_.login(*PW["parent"]); stu=S(); stu.login(*PW["student"]); p2=S(); p2.login(*PW["parent2"]); p3=S(); p3.login(*PW["parent3"])
a.patch("/academy/settings/",{"auto_invoice_on_subscription":False})
sub0=q("select coalesce(max(id),0) from scheduling_subscription")
c,j=par_.post("/vouchers/check/",{"code":disp(act[0])}); log("check",c,short(j,n=300))
c,j=par_.post("/vouchers/redeem/",{"code":disp(act[0]),"student":5}); log("parent redeems ACT1",c,short(j,n=300))
sid=j.get("subscription_id")
log("sub", q(f"select id,student_id,course_id,package_id,teacher_id,starts_on,price_minor,currency,status from scheduling_subscription where id={sid}"))
log("inv", q(f"select id,amount_minor,currency,status from billing_invoice where subscription_id={sid}"), "pay", q(f"select p.method,p.amount_minor,p.status from billing_payment p join billing_invoice i on i.id=p.invoice_id where i.subscription_id={sid}"))
chk("TC021 ACT1 subscription + invoice paid in full by code despite auto_invoice off", q(f"select status||'|'||amount_minor from billing_invoice where subscription_id={sid}")=="paid|150000" and q(f"select count(*) from billing_payment p join billing_invoice i on i.id=p.invoice_id where i.subscription_id={sid} and p.method='code'")=="1")
c,j=stu.post("/vouchers/redeem/",{"code":disp(act[1]),"student":st["S2"]}); chk("TC021 student for S2 refused 404", c==404, short(j))
c,j=p2.post("/vouchers/redeem/",{"code":disp(act[1]),"student":5}); chk("TC021 parent2 for S1 refused 404", c==404, short(j))
c,j=p3.post("/vouchers/redeem/",{"code":disp(act[1]),"student":5}); chk("TC021 sibling payer P3 refused 404", c==404, short(j))
# race same code
res=par([lambda: par_.post("/vouchers/redeem/",{"code":disp(act[1]),"student":5}), lambda: stu.post("/vouchers/redeem/",{"code":disp(act[1]),"student":5})])
log("race", [(r[0], short(r[1],n=150)) for r in res]); chk("TC021 race exactly one 201", sorted(r[0] for r in res)[0] in (200,201) and sorted(r[0] for r in res)[1] in (400,409))
chk("TC021 one subscription per code", q(f"select count(*) from vouchers_voucher where code='{act[1]}' and subscription_id is not null")=="1")
# renewal
SUBR=sid
c,j=par_.post("/vouchers/redeem/",{"code":disp(ren[0]),"subscription":SUBR}); log("REN1 on SUBR",c,short(j,n=300)); rsid=j.get("subscription_id") if isinstance(j,dict) else None
if rsid: log("renewed", q(f"select id,starts_on,price_minor from scheduling_subscription where id={rsid}"), q(f"select status,amount_minor from billing_invoice where subscription_id={rsid}"))
chk("TC021 renewal creates subscription with paid invoice", bool(rsid) and q(f"select status from billing_invoice where subscription_id={rsid}")=="paid")
c,j=par_.post("/vouchers/redeem/",{"code":disp(ren[1]),"subscription":1}); log("REN on other course",c,short(j)); chk("TC021 wrong course refused", c in (400,409))
c,j=par_.post("/vouchers/redeem/",{"code":disp(ren[1])}); log("REN no subscription",c,short(j)); chk("TC021 renewal without subscription refused", c in (400,409))
# invoices off
a.patch("/academy/settings/",{"auto_invoice_on_subscription":True})
log(features("qa", off=["invoices"]))
c,j=par_.post("/vouchers/redeem/",{"code":disp(act[2]),"student":5}); log("ACT3 invoices off",c,short(j,n=200)); s3=j.get("subscription_id") if isinstance(j,dict) else None
log(features("qa", on=["invoices"]))
if s3: chk("TC021 invoices off: no invoice/payment, code used", q(f"select count(*) from billing_invoice where subscription_id={s3}")=="0" and q(f"select status from vouchers_voucher where code='{act[2]}'")=="used")
log("dupe invoices per sub", q("select subscription_id,count(*) from billing_invoice where subscription_id is not null and status<>'void' group by 1 having count(*)>1"))
log("code payments vs used vouchers w/ payment", q("select count(*) from billing_payment where method='code'"), q("select count(*) from vouchers_voucher where payment_id is not null"))
st.update(SUBR=SUBR); st_save(st); save("tc021.txt")
