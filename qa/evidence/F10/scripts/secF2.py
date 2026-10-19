from qa import *
st = st_load(); ss = st["sess"]; a = S(); a.login(*PW["admin"]); a2 = S(); a2.login(*PW["admin"])
def slip(t, y, m):
    c, j = a.get(f"/payroll/payslips/?year={y}&month={m}&teacher={ID[t]}"); r = j["results"]; return r[0] if r else None
t1 = S(); t1.login(*PW["T1"]); T = ID["T1"]
def bal(s=a, qs=f"?teacher={T}"): return s.get("/payroll/balances/" + qs)
log("==== TC-020 re-run: W5 (10, lower-case 'egp' normalised to EGP) was left under_review -> cancel first")
for w in q("select id from payroll_withdrawalrequest where teacher_id=1 and status in ('under_review','approved')").split():
    log("cancel", w, a.post(f"/payroll/withdrawals/{w}/cancel/")[0])
log("==== TC-020", datetime.datetime.now().isoformat())
c, j = bal(); log("before", short(j))  # available 12000
res = par([lambda: t1.post("/payroll/withdrawals/", {"amount_minor": 12000, "currency": "EGP"}) for _ in range(5)])
codes = sorted(r[0] for r in res); chk("5 parallel 12000: exactly one 201, rest 409", codes == [201, 409, 409, 409, 409], str(codes) + " " + str([r[1].get("code") for r in res if r[0] != 201]))
win = [r[1]["id"] for r in res if r[0] == 201]
s = q("select coalesce(sum(amount_minor),0) from payroll_withdrawalrequest where teacher_id=1 and status in ('under_review','approved','paid')"); chk("sum reserved+paid <= 20000", int(s) <= 20000, s)
if win:
    w = win[0]; a2 = S(); a2.login(*PW["admin"])
    res = par([lambda: a.post(f"/payroll/withdrawals/{w}/approve/"), lambda: a2.post(f"/payroll/withdrawals/{w}/reject/", {"office_notes": "race"})])
    log("approve vs reject", [(r[0], r[1].get("status") or r[1].get("code")) for r in res]); chk("one winner one 409", sorted(r[0] for r in res) == [200, 409])
    log("final", q(f"select status from payroll_withdrawalrequest where id={w}"))
    a.post(f"/payroll/withdrawals/{w}/cancel/")
c, W7 = t1.post("/payroll/withdrawals/", {"amount_minor": 100, "currency": "EGP"}); a.post(f"/payroll/withdrawals/{W7['id']}/approve/")
res = par([lambda: a.post(f"/payroll/withdrawals/{W7['id']}/pay/", {"paid_on": TODAY.isoformat()}), lambda: a2.post(f"/payroll/withdrawals/{W7['id']}/cancel/")])
log("pay vs cancel", [(r[0], r[1].get("status") or r[1].get("code")) for r in res]); chk("pay vs cancel one winner", sorted(r[0] for r in res) == [200, 409])
c, j = bal(); chk("available never negative", all(x["available_minor"] >= 0 for x in (j if isinstance(j, list) else j.get("results", []))), short(j))
save("tc020.txt")

log("==== TC-021", datetime.datetime.now().isoformat())
t2 = S(); t2.login(*PW["T2"])
dr = slip("T1", 2026, 10); c, j = t1.post(f"/payroll/payslips/{dr['id']}/acknowledge/"); chk("ack draft 404", c == 404, str(c))
# issued T1 payslip: none currently issued-unpaid for T1 -> use T2? T2 Sept draft. Issue T7 Oct? not over. Use T3 Aug issued (TC-014) -> T3 ack
t3 = S(); t3.login(*PW["T3"]); p3 = slip("T3", 2026, 8); c, j = t3.post(f"/payroll/payslips/{p3['id']}/acknowledge/"); chk("ack issued 409 not_allowed_in_status", c == 409 and j.get("code") == "payroll.not_allowed_in_status", f"{c} {short(j)}")
pa = st["slip_T1_aug"]; c, j = t2.post(f"/payroll/payslips/{pa}/acknowledge/"); chk("T2 acks T1's 404", c == 404, str(c))
c, j = t1.post(f"/payroll/payslips/{pa}/acknowledge/"); chk("own paid ack 200", c == 200 and j["acknowledged_at"], str(c))
c, j = t1.post(f"/payroll/payslips/{pa}/acknowledge/"); chk("again 409 already_acknowledged", c == 409 and j.get("code") == "payroll.already_acknowledged", f"{c} {short(j)}")
for who in ["admin", "s_pay", "student", "parent"]:
    s_ = S(); s_.login(*PW[who]); c, j = s_.post(f"/payroll/payslips/{st['slip_T1_sep']}/acknowledge/"); chk(f"{who} ack 403", c == 403, str(c))
c, j = anon().post(f"/payroll/payslips/{st['slip_T1_sep']}/acknowledge/"); chk("anon 401/403", c in (401, 403), str(c))
log(features("qa", off=["payslip_acknowledgement"])); c, j = t1.post(f"/payroll/payslips/{pa}/acknowledge/"); chk("switch off 403/404", c in (403, 404), str(c)); log(features("qa", on=["payslip_acknowledgement"]))
log("DB", q(f"select id,acknowledged_at,net_minor from payroll_payslip where id in ({st['slip_T1_sep']},{pa})"))
c, raw = a.get("/payroll/payslips/?format=csv", raw=True); chk("acknowledged_at in CSV header", c == 200 and "acknowledged_at" in raw.splitlines()[0], raw.splitlines()[0][:300] if raw else str(c))
st_save(st); save("tc021.txt")
