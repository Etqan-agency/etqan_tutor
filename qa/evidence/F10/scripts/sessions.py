from qa import *
st = st_load(); a = S(); a.login(*PW["admin"])
ss = st.setdefault("sess", {})
c, j = a.post("/sessions/9/attendance/", {"student_attendance": "present", "teacher_attendance": "present"}); log("mark 9", c, short(j, ["status","student_attendance","teacher_attendance"]))
ss["T1_0903"] = 9
plan = [
 ("T1_0910","T1","S1","C1","2026-09-10","10:00",45,{}), ("T1_0917","T1","S1","C1","2026-09-17","10:00",30,{}),
 ("T1_0805","T1","S1","C1","2026-08-05","10:00",120,{}), ("T1_0812","T1","S1","C1","2026-08-12","10:00",80,{}),
 ("T2_a","T2","S1","C1","2026-09-02","11:00",45,{}), ("T2_b","T2","S1","C1","2026-09-04","11:00",30,{}), ("T2_c","T2","S1","C1","2026-09-06","11:00",20,{}),
 ("T2_abs","T2","S1","C1","2026-09-08","11:00",45,{"sa":"absent"}), ("T2_exc","T2","S1","C1","2026-09-09","11:00",45,{"sa":"excused"}),
 ("T3_a","T3","S1","C1","2026-09-30","23:30",60,{}), ("T3_b","T3","S1","C1","2026-10-01","00:30",60,{}),
 ("T3_c","T3","S1","C1","2026-09-05","12:00",60,{"ta":"absent"}), ("T3_d","T3","S1","C1","2026-09-06","12:00",60,{"ta":"excused"}),
 ("T3_e","T3","S1","C1","2026-09-07","12:00",60,{"ta":None}), ("T3_f","T3","S1","C1","2026-09-08","12:00",60,{"mark":False}),
 ("T3_g","T3","S1","C1","2026-09-09","12:00",60,{"mark":False}), ("T3_h","T3","S1","C1","2026-09-11","12:00",60,{"mark":False}),
 ("T3_i","T3","S1","C1","2026-09-12","12:00",60,{"pays_teacher":False}),
 ("T4_11","T4","S1","C1","2026-08-03","13:00",60,{}), ("T4_12","T4","S1","C2","2026-08-04","13:00",60,{}),
 ("T4_21","T4","S2","C1","2026-08-05","13:00",60,{}), ("T4_22","T4","S2","C2","2026-08-06","13:00",60,{}),
 ("T5_a","T5","S1","C1","2026-08-10","14:00",120,{}),
 ("T6_a","T6","S1","C1","2026-06-02","15:00",60,{}), ("T6_b","T6","S1","C1","2026-06-03","15:00",45,{}), ("T6_c","T6","S1","C1","2026-06-04","15:00",30,{}),
 ("T7_s","T7","S1","C1","2026-09-15","16:00",60,{}), ("T7_o","T7","S1","C1","2026-10-05","16:00",60,{}),
 ("T8_s","T8","S1","C1","2026-09-15","17:00",60,{}), ("T9_s","T9","S1","C1","2026-09-15","18:00",60,{}),
 ("T10_a","T10","S1","C1","2026-09-02","19:00",60,{}), ("T10_b","T10","S1","C1","2026-09-03","19:00",60,{}), ("T10_c","T10","S1","C1","2026-09-04","19:00",60,{}),
 ("T11_aug","T11","S1","C1","2026-08-10","20:00",60,{}), ("T11_sep","T11","S1","C1","2026-09-10","20:00",60,{}),
 ("T12_jul","T12","S1","C1","2026-07-10","09:00",60,{}),
 ("T13_a","T13","S1","C1","2026-05-10","09:00",60,{}), ("T13_b","T13","S1","C1","2026-05-11","09:00",45,{}),
 ("T14_a","T14","S1","C1","2026-04-10","09:00",60,{}), ("T14_b","T14","S1","C1","2026-04-11","09:00",60,{}),
 ("T1_oct_done","T1","S1","C1","2026-10-12","10:00",60,{}), ("T1_oct_stale","T1","S1","C1","2026-10-10","10:00",60,{"mark":False}),
 ("T1_oct_future","T1","S1","C1","2026-10-28","10:00",60,{"mark":False}),
 ("TX_sep","TX","S1","C1","2026-09-20","09:00",60,{}),
]
for key, t, s, c_, on, start, m, o in plan:
    if key in ss: continue
    o = dict(o); sa = o.pop("sa", "present"); ta = o.pop("ta", "present"); mark = o.pop("mark", True)
    body = {"student": ID[s], "course": ID[c_], "teacher": ID[t], "occurs_on": on, "start_time": start, "minutes": m, **o}
    code, j = a.post("/sessions/extra/", body)
    if code != 201: log("FAIL create", key, code, short(j)); continue
    sid = j["session"]["id"]; ss[key] = sid
    if mark:
        att = {"student_attendance": sa}
        if ta: att["teacher_attendance"] = ta
        code2, j2 = a.post(f"/sessions/{sid}/attendance/", att)
        log(key, sid, "mark", code2, short(j2, ["status","student_attendance","teacher_attendance"]) if code2 == 200 else short(j2))
    else: log(key, sid, "created scheduled")
st_save(st)
# (g) cancel, (h) disposal
c, j = a.post(f"/sessions/{ss['T3_g']}/cancel/", {"reason": "F10 g"}); log("cancel g", c, short(j, n=150))
c, j = a.post(f"/sessions/{ss['T3_h']}/disposal/", {"reason": "F10 h"}); log("disposal h", c, short(j, n=150))
log(q("select id,teacher_id,occurs_on,starts_at,minutes,status,student_attendance,teacher_attendance,pays_teacher,payroll_locked from scheduling_session where id>=9 order by id"))
save("setup.txt")
