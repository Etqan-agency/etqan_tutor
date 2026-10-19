from qa import *
st = st_load(); a = S(); a.login(*PW["admin"])
dc("exec","-T","django","python","manage.py","shell","-c","from django.core.cache import cache; cache.clear()")
log("== TC-012", datetime.datetime.now().isoformat())
INV=st["INV1"]; refunded=st["P_b"]; PS=st["PS"]; used_code=q("select id from vouchers_voucher where status='used' limit 1"); ck=st["K1"]
L=st["L1"]
EP=[("inv list","GET","/billing/invoices/",None,"inv_read"),("inv detail","GET",f"/billing/invoices/{INV}/",None,"inv_read"),
 ("inv create","POST","/billing/invoices/",{},"inv_write"),("inv patch","PATCH",f"/billing/invoices/{INV}/",{"amount_minor":0},"inv_write"),
 ("inv void","POST",f"/billing/invoices/{st['A']}/void/",{},"inv_write"),
 ("inv payments GET","GET",f"/billing/invoices/{INV}/payments/",None,"inv_read"),("inv payments POST","POST",f"/billing/invoices/{INV}/payments/",{},"pay_write"),
 ("payments list","GET","/billing/payments/",None,"pay_list"),("payment patch","PATCH",f"/billing/payments/{refunded}/",{"notes":"x"},"pay_write"),
 ("payment delete","DELETE",f"/billing/payments/{PS}/",None,"pay_write"),("payment refund","POST",f"/billing/payments/{refunded}/refund/",{},"pay_write"),
 ("summary","GET","/billing/summary/",None,"summary"),("payers","GET","/billing/payers/?student=5",None,"inv_write"),
 ("bill settings GET","GET","/billing/settings/",None,"settings"),("bill settings PATCH","PATCH","/billing/settings/",{"local_payment_enabled":"x"},"settings"),
 ("local-methods GET","GET","/billing/local-methods/",None,"settings"),("local-methods POST","POST","/billing/local-methods/",{},"settings"),
 ("gw settings GET","GET","/gateways/settings/",None,"gw"),("gw settings PATCH","PATCH","/gateways/settings/",{"fee":{"basis_points":-1}},"gw"),
 ("checkouts list","GET","/gateways/checkouts/",None,"gw"),("checkout resolve","POST",f"/gateways/checkouts/{ck}/resolve/",{},"gw"),
 ("links list","GET","/gateways/links/",None,"gw"),("links POST","POST","/gateways/links/",{},"gw"),
 ("wallet topup","POST","/wallet/students/5/top-ups/",{},"wallet"),("wallet adjust","POST","/wallet/students/5/adjustments/",{},"wallet"),
 ("wallet move","POST",f"/wallet/payments/{refunded}/move/",{},"wallet"),("wallet student GET","GET","/wallet/students/5/",None,"wallet_read"),
 ("wallet mine","GET","/wallet/mine/",None,"family"),("wallet pay own","POST",f"/wallet/invoices/{INV}/pay/",{"amount_minor":0},"wallet_pay"),
 ("codes check","POST","/vouchers/check/",{"code":"SYS-AAAAA-AAAAA"},"family"),("codes redeem","POST","/vouchers/redeem/",{"code":"SYS-AAAAA-AAAAA"},"family"),
 ("voucher batches GET","GET","/vouchers/batches/",None,"voucher"),("voucher batches POST","POST","/vouchers/batches/",{},"voucher"),
 ("voucher void","POST",f"/vouchers/codes/{used_code}/void/",{"reason":"x"},"voucher"),("office redeem","POST","/vouchers/codes/redeem/",{"code":"SYS-AAAAA-AAAAA","invoice":INV},"voucher")]
ROLES=["admin","staffno","bill","narrow","sup","teacher","student","parent","anon"]
# expectation: A=allowed (2xx/400/409), D=denied (401/403/404)
EXP={"inv_read":"AD AA DD AA D","inv_write":"AD AD DD DD D","pay_write":"AD AD DD DD D","pay_list":"AD AA DD DD D","summary":"AD AD DD DD D",
     "settings":"AD AD DD DD D","gw":"AD AD DD DD D","wallet":"AD AD DD DD D","wallet_read":"AD AD DD AA D","family":"DD DD DD AA D","wallet_pay":"DD DD DD AA D","voucher":"AD AD DD DD D"}
def sess(role):
    if role=="anon": return anon()
    if role in("bill","narrow"):
        a.patch("/access/staff/3/",{"role_ids":[3,st["R_BILL"]] if role=="bill" else [st["R_NARROW"]]}); s=S(); s.login(*PW["staffc"]); return s
    s=S(); s.login(*PW[role]); return s
counts0=[q(f"select count(*) from {t}") for t in ["billing_invoice","billing_payment","wallet_walletentry","vouchers_voucherbatch","gateways_paymentlink","billing_localpaymentmethod"]]
M={}
for r in ROLES:
    s=sess(r)
    for name,m,p,b,g in EP:
        dc_ = None
        c,j=s.req(m,p,b)
        M[(name,r)]=(c, (j.get("code") or j.get("detail","")[:40]) if isinstance(j,dict) else "")
    dc("exec","-T","django","python","manage.py","shell","-c","from django.core.cache import cache; cache.clear()") if r in ("student","parent") else None
a.patch("/access/staff/3/",{"role_ids":[3,st["R_BILL"]]})
counts1=[q(f"select count(*) from {t}") for t in ["billing_invoice","billing_payment","wallet_walletentry","vouchers_voucherbatch","gateways_paymentlink","billing_localpaymentmethod"]]
log("row counts before/after", counts0, counts1); chk("TC012 no rows changed by the matrix", counts0==counts1)
log("| endpoint | "+" | ".join(ROLES)+" |"); log("|"+"---|"*(len(ROLES)+1))
bad=[]
for name,m,p,b,g in EP:
    exp=EXP[g].replace(" ","")
    cells=[]
    for i,r in enumerate(ROLES):
        c,code=M[(name,r)]; ok=(c in (200,201,204,400,409)) if exp[i]=="A" else (c in (401,403,404))
        if c>=500: ok=False
        cells.append(f"{c}{'' if ok else '!'}")
        if not ok: bad.append((name,r,c,code,exp[i]))
    log(f"| {m} {name} | "+" | ".join(cells)+" |")
log("deviations (! = outside expectation):")
for x in bad: log("  ", x)
st_save(st); save("tc012.txt")
