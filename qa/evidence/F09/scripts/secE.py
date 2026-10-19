from qa import *
st = st_load(); a = S(); a.login(*PW["admin"])
C,P=st["COURSE"],st["PKG"]
log("== TC-019", datetime.datetime.now().isoformat())
def batch(b):
    c,j=a.post("/vouchers/batches/",b); log("batch",short(b,n=150),c,short(j,n=300)); return c,j
c,j=batch({"kind":"discount","quantity":3,"valid_days":30,"discount_kind":"percent","discount_value":15}); st["DPCT"]=j.get("id")
c,j=batch({"kind":"discount","quantity":2,"valid_days":1,"discount_kind":"fixed","discount_value":20000,"currency":"EGP"}); st["DFIX"]=j.get("id")
c,j=batch({"kind":"activation","quantity":3,"valid_days":30,"course":C,"package":P,"teacher":7}); st["DACT"]=j.get("id")
c,j=batch({"kind":"renewal","quantity":2,"valid_days":30,"course":C,"package":P}); st["DREN"]=j.get("id")
c,j=batch({"kind":"discount","quantity":2,"valid_days":30,"discount_kind":"percent","discount_value":1}); st["DP1"]=j.get("id")
bad=[{"kind":"discount","quantity":0,"valid_days":30,"discount_kind":"percent","discount_value":15},
 {"kind":"discount","quantity":501,"valid_days":30,"discount_kind":"percent","discount_value":15},
 {"kind":"discount","quantity":1,"valid_days":0,"discount_kind":"percent","discount_value":15},
 {"kind":"discount","quantity":1,"valid_days":3651,"discount_kind":"percent","discount_value":15},
 {"kind":"discount","quantity":1,"valid_days":30,"discount_kind":"percent","discount_value":0},
 {"kind":"discount","quantity":1,"valid_days":30,"discount_kind":"percent","discount_value":101},
 {"kind":"discount","quantity":1,"valid_days":30,"discount_kind":"percent","discount_value":12.5},
 {"kind":"discount","quantity":1,"valid_days":30,"discount_kind":"fixed","discount_value":100},
 {"kind":"discount","quantity":1,"valid_days":30,"discount_kind":"fixed","discount_value":100000001,"currency":"EGP"},
 {"kind":"discount","quantity":1,"valid_days":30,"discount_kind":"percent","discount_value":10,"currency":"EGP"},
 {"kind":"activation","quantity":1,"valid_days":30,"course":C,"package":P},
 {"kind":"renewal","quantity":1,"valid_days":30,"course":C,"package":P,"teacher":7},
 {"kind":"activation","quantity":1,"valid_days":30,"course":1,"package":P,"teacher":16},
 {"kind":"nope","quantity":1,"valid_days":30}]
for b in bad:
    c,j=a.post("/vouchers/batches/",b); log("bad",short(b,n=140),c,short(j,n=160)); chk("TC019 refusal 400", c==400)
log("DB batches", q("select id,kind,quantity,expires_on,discount_kind,discount_value,currency from vouchers_voucherbatch order by id"))
log("expiry check", q(f"select id, expires_on = (date '{d(0)}' + valid_days - 1) from vouchers_voucherbatch order by id") if "valid_days" in q("select string_agg(column_name,',') from information_schema.columns where table_schema='academy_qa' and table_name='vouchers_voucherbatch'") else q("select string_agg(column_name,',') from information_schema.columns where table_schema='academy_qa' and table_name='vouchers_voucherbatch'"))
log("codes", q("select count(*), count(distinct code), sum((code ~ '^[0-9A-HJKMNP-TV-Z]{10}$')::int) from vouchers_voucher"))
c,j=a.get("/vouchers/codes/?kind=discount&state=unused"); log("list unused discount", c, j.get("count") if isinstance(j,dict) else j); sample=j["results"][0]; log("sample", short(sample,n=300))
c,txt=a.get("/vouchers/codes/?format=csv", raw=True); log("csv", c, txt[:200].replace("\n"," | "))
c,j=a.get(f"/vouchers/codes/?code={sample['code']}"); log("by code", c, j.get("count"))
# void
vid = int(q(f"select id from vouchers_voucher where batch_id={st['DPCT']} order by id desc limit 1"))
c,j=a.post(f"/vouchers/codes/{vid}/void/",{"reason":"qa"}); chk("TC019 void unused", c==200 and q(f"select status from vouchers_voucher where id={vid}")=="void", short(j,n=150))
c,j=a.post(f"/vouchers/codes/{vid}/void/",{"reason":"qa"}); chk("TC019 void again 409", c==409, short(j))
st["VOIDED_CODE"]=q(f"select code from vouchers_voucher where id={vid}")
# throttle
dc("exec","-T","django","python","manage.py","shell","-c","from django.core.cache import cache; cache.clear()")
stu=S(); stu.login(*PW["student"])
codes=[]
for i in range(22):
    c,j=stu.post("/vouchers/check/",{"code":"SYS-AAAAA-AAAAA"}); codes.append(c)
log("throttle codes", codes); chk("TC019 21st attempt 429", 429 in codes and codes.index(429)==20, str(codes.index(429) if 429 in codes else None))
dc("exec","-T","django","python","manage.py","shell","-c","from django.core.cache import cache; cache.clear()")
c1,j1=stu.post("/vouchers/check/",{"code":"SYS-AAAAA-AAAAA"}); c2,j2=stu.post("/vouchers/check/",{"code":st["VOIDED_CODE"]})
log("unknown vs void", c1, short(j1), c2, short(j2)); chk("TC019 unknown and void answer identically", (c1,j1)==(c2,j2))
dc("exec","-T","django","python","manage.py","shell","-c","from django.core.cache import cache; cache.clear()")
st_save(st); save("tc019.txt")
