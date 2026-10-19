from qa import *
st = st_load(); ss = st["sess"]; a = S(); a.login(*PW["admin"])
def slip(t, y, m):
    c, j = a.get(f"/payroll/payslips/?year={y}&month={m}&teacher={ID[t]}")
    r = j["results"]; return r[0] if r else None
def det(pid): return a.get(f"/payroll/payslips/{pid}/")[1]
log("==== TC-001", datetime.datetime.now().isoformat())
p = slip("T1", 2026, 9); d1 = det(p["id"]); log("detail keys", list(d1.keys())); log("lines", short(d1.get("lines"), n=1500))
L = [l for l in d1["lines"] if l["kind"] == "session"]
chk("3 session lines 6000/4500/3000", sorted(l["amount_minor"] for l in L) == [3000, 4500, 6000], str([(l["minutes"], l["rate_minor"], l["amount_minor"]) for l in L]))
chk("draft gross/net 13500 EGP", (p["status"], p["gross_minor"], p["net_minor"], p["currency"]) == ("draft", 13500, 13500, "EGP"))
c, j = a.post(f"/payroll/payslips/{p['id']}/issue/"); chk("issue 200 issued", c == 200 and j["status"] == "issued" and j["issued_by"], f"{c} {short(j, ['status','issued_by','issued_at','net_minor'])}")
c, j = a.post(f"/payroll/payslips/{p['id']}/mark-paid/", {"paid_on": TODAY.isoformat(), "notes": "cash"}); chk("mark-paid 200 paid", c == 200 and j["status"] == "paid", f"{c} {short(j, ['status','paid_on','paid_by','notes'])}")
t1 = S(); t1.login(*PW["T1"]); c, j = t1.get("/payroll/payslips/"); chk("T1 lists it", c == 200 and p["id"] in [x["id"] for x in j["results"]], f"{c} ids={[x['id'] for x in j['results']]}")
c, j = t1.post(f"/payroll/payslips/{p['id']}/acknowledge/"); chk("ack 200", c == 200 and j.get("acknowledged_at"), f"{c} {short(j, ['acknowledged_at','status'])}")
log("DB payslip", q(f"select id,number,status,paid_on,paid_by_id,issued_by_id,gross_minor,net_minor,currency,acknowledged_at is not null from payroll_payslip where id={p['id']}"))
log("DB lines", q(f"select kind,session_id,minutes,rate_minor,amount_minor from payroll_payslipline where payslip_id={p['id']} order by id"))
log("DB locked", q(f"select id,payroll_locked from scheduling_session where id in ({ss['T1_0903']},{ss['T1_0910']},{ss['T1_0917']})"))
log("DB expense", q(f"select id,source,source_id,type,amount_minor,currency,spent_on,title from finance_expense where source='payroll.payslip'"))
log("DB counter", q("select * from payroll_payslipcounter"), "| payslips", q("select count(*), max(number) from payroll_payslip"))
st["slip_T1_sep"] = p["id"]
save("tc001.txt")

log("==== TC-002", datetime.datetime.now().isoformat())
p = slip("T2", 2026, 9); d = det(p["id"]); am = sorted(l["amount_minor"] for l in d["lines"] if l["kind"] == "session")
log("lines", [(l["minutes"], l.get("pay_bp"), l["amount_minor"]) for l in d["lines"]])
chk("half-up per line", am == sorted([9259, 6173, 4115, 4629, 2315]), str(am))
chk("gross 26491 = sum lines; net", p["gross_minor"] == 26491 == sum(am) and p["net_minor"] == 26491, f"{p['gross_minor']} {p['net_minor']}")
chk("all ints", all(isinstance(l["amount_minor"], int) for l in d["lines"]) and isinstance(p["gross_minor"], int))
c, raw = a.get(f"/payroll/payslips/{p['id']}/", raw=True); chk("no decimal points in money in JSON", '"amount_minor": ' not in raw or all('.' not in seg.split(',')[0] for seg in raw.split('"amount_minor":')[1:]))
log("DB", q(f"select minutes,pay_bp,amount_minor from payroll_payslipline where payslip_id={p['id']} order by id"))
save("tc002.txt")

log("==== TC-003", datetime.datetime.now().isoformat())
p = slip("T3", 2026, 9); d = det(p["id"]); sids = sorted(l["session_id"] for l in d["lines"] if l["kind"] == "session")
chk("Sept pays exactly a,e", sids == sorted([ss["T3_a"], ss["T3_e"]]), f"{sids} teacher_absences={p['teacher_absences']}")
chk("teacher_absences = 2 (c,d)", p["teacher_absences"] == 2, str(p["teacher_absences"]))
a.post("/payroll/payslips/generate/", {"year": 2026, "month": 10}); po = slip("T3", 2026, 10)
chk("(b) on October", po and ss["T3_b"] in [l["session_id"] for l in det(po["id"])["lines"]], short(po, ["id","net_minor"]))
a.patch("/payroll/settings/", {"at_disposal_pays": True}); c, g = a.post("/payroll/payslips/generate/", {"year": 2026, "month": 9})
d = det(slip("T3", 2026, 9)["id"]); ls = {l["session_id"]: l for l in d["lines"] if l["kind"] == "session"}
chk("(h) included at 100% with at_disposal_pays", ss["T3_h"] in ls and ls[ss["T3_h"]]["amount_minor"] == 6000, str({k: (v["pay_bp"], v["amount_minor"]) for k, v in ls.items()}))
a.patch("/payroll/settings/", {"at_disposal_pays": False}); a.post("/payroll/payslips/generate/", {"year": 2026, "month": 9})
chk("back to a,e", sorted(l["session_id"] for l in det(slip("T3", 2026, 9)["id"])["lines"] if l["kind"] == "session") == sorted([ss["T3_a"], ss["T3_e"]]))
log("DB sessions unlocked", q(f"select id,payroll_locked from scheduling_session where teacher_id=4 order by id"))
save("tc003.txt")

log("==== TC-005", datetime.datetime.now().isoformat())
c, g = a.post("/payroll/payslips/generate/", {"year": 2026, "month": 7}); log("gen jul", c, short(g, n=400))
chk("missing_rate lists T12", any((x.get("id") if isinstance(x, dict) else x) == ID["T12"] for x in g["missing_rate"]), short(g["missing_rate"]))
p = slip("T12", 2026, 7); chk("payslip missing_rate, net 0", p["missing_rate"] and p["net_minor"] == 0, short(p, ["missing_rate","net_minor","status"]))
c, j = a.post(f"/payroll/payslips/{p['id']}/issue/"); chk("issue 409 missing_rate", c == 409 and j.get("code") == "payroll.missing_rate", f"{c} {short(j)}")
log("after 409", q(f"select status,issued_at from payroll_payslip where id={p['id']}"), q(f"select payroll_locked from scheduling_session where id={ss['T12_jul']}"))
a.post("/payroll/rates/", {"teacher": ID["T12"], "hourly_rate_minor": 6000})
c, j = a.post(f"/payroll/payslips/{p['id']}/issue/"); chk("issue after rate 200 priced 6000", c == 200 and j["net_minor"] == 6000, f"{c} {short(j, ['status','net_minor','missing_rate'])}")
save("tc005.txt")

log("==== TC-006", datetime.datetime.now().isoformat())
c, g = a.post("/payroll/payslips/generate/", {"year": 2026, "month": 10}); p = slip("T7", 2026, 10); num = p["number"]
c, j = a.post(f"/payroll/payslips/{p['id']}/issue/"); chk("Oct issue 409 month_not_over", c == 409 and j.get("code") == "payroll.month_not_over", f"{c} {short(j)}")
c, j = a.post(f"/payroll/payslips/{p['id']}/mark-paid/", {"paid_on": TODAY.isoformat()}); chk("mark-paid draft 409 not_allowed_in_status", c == 409 and j.get("code") == "payroll.not_allowed_in_status", f"{c} {short(j)}")
for b in [{"year": 1999, "month": 9}, {"year": 2026, "month": 13}, {"year": 2026}, {"year": "x", "month": 1}]:
    c, j = a.post("/payroll/payslips/generate/", b); chk(f"generate {b} 400 names field", c == 400, f"{c} {short(j)}")
a.post("/payroll/payslips/generate/", {"year": 2026, "month": 10}); p2 = slip("T7", 2026, 10)
chk("Oct draft rebuilt, number kept", p2["id"] == p["id"] and p2["number"] == num and p2["status"] == "draft", f"{num} {p2['number']}")
log("lock", q(f"select payroll_locked from scheduling_session where id={ss['T7_o']}"))
save("tc006.txt")
st_save(st)
