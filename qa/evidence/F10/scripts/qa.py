import json, subprocess, urllib.request, urllib.error, http.cookiejar, datetime, os, sys, time, hmac, hashlib, threading
EVD = "/Users/khaledsakr/Documents/Etqan tutor/etqan_tutor/qa/evidence/F10"
QA = "http://qa.etqan.localhost"; QO = "http://qaother.etqan.localhost"
OUT = []
def log(*a):
    s = " ".join(str(x) for x in a); print(s); OUT.append(s)
def save(name):
    with open(f"{EVD}/{name}", "a") as f: f.write("\n".join(OUT) + "\n")
    OUT.clear()
class S:
    def __init__(self, host=QA):
        self.host = host; self.cj = http.cookiejar.CookieJar()
        self.op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.cj))
    def csrf(self):
        for c in self.cj:
            if c.name == "csrftoken": return c.value
        return ""
    def req(self, method, path, body=None, raw=False, host=None, headers=None):
        h = host or self.host
        url = path if path.startswith("http") else f"{h}/api/v1{path}"
        data = None if body is None else (body if isinstance(body, bytes) else json.dumps(body).encode())
        r = urllib.request.Request(url, data=data, method=method)
        r.add_header("Content-Type", "application/json"); r.add_header("Referer", h + "/")
        r.add_header("X-CSRFToken", self.csrf())
        for k, v in (headers or {}).items(): r.add_header(k, v)
        try:
            resp = self.op.open(r, timeout=60); code = resp.status; txt = resp.read().decode()
        except urllib.error.HTTPError as e:
            code = e.code; txt = e.read().decode()
        if raw: return code, txt
        try: j = json.loads(txt) if txt else None
        except Exception: j = txt[:300]
        return code, j
    def get(self, p, **k): return self.req("GET", p, **k)
    def post(self, p, b=None, **k): return self.req("POST", p, b if b is not None else {}, **k)
    def patch(self, p, b, **k): return self.req("PATCH", p, b, **k)
    def put(self, p, b, **k): return self.req("PUT", p, b, **k)
    def delete(self, p, **k): return self.req("DELETE", p, **k)
    def login(self, email, pw):
        self.get("/identity/csrf/")
        c, j = self.post("/identity/login/", {"identifier": email, "password": pw})
        return c
def anon(host=QA): s = S(host); s.get("/identity/csrf/"); return s
def q(sql, schema="academy_qa"):
    env = dict(os.environ, PGPASSWORD="etqan")
    r = subprocess.run(["psql", "-h", "localhost", "-p", "5433", "-U", "etqan", "-d", "etqan", "-AtF|", "-c", f"SET search_path={schema}; {sql}"], capture_output=True, text=True, env=env)
    return (r.stdout.replace("SET\n", "", 1) + r.stderr).strip()
def dc(*args):
    r = subprocess.run(["/Users/khaledsakr/.etqan-qa-tools/dc.sh", *args], capture_output=True, text=True)
    return (r.stdout + r.stderr).strip()
def features(sub, on=(), off=()):
    a = ["exec", "-T", "django", "python", "manage.py", "set_features", sub]
    if on: a += ["--on", *on]
    if off: a += ["--off", *off]
    return dc(*a).splitlines()[-1]
TODAY = datetime.date.fromisoformat(q("select (now() at time zone 'Africa/Cairo')::date"))
def d(n=0): return (TODAY + datetime.timedelta(days=n)).isoformat()
def short(j, keys=None, n=400):
    if isinstance(j, dict) and keys: j = {k: j.get(k) for k in keys}
    s = json.dumps(j, ensure_ascii=False); return s[:n]
def chk(label, cond, detail=""):
    log(("OK  " if cond else "BAD ") + label + (" :: " + detail if detail else "")); return cond
def par(fns):
    res = [None]*len(fns)
    def run(i, f): res[i] = f()
    ts = [threading.Thread(target=run, args=(i, f)) for i, f in enumerate(fns)]
    [t.start() for t in ts]; [t.join() for t in ts]; return res
STATE = "/private/tmp/claude-501/-Users-khaledsakr-Documents-Etqan-tutor/55afddca-abb7-4698-b08b-38df7f0acb0e/scratchpad/f10/state.json"
def st_load():
    try: return json.load(open(STATE))
    except Exception: return {}
def st_save(st): json.dump(st, open(STATE, "w"), indent=1)
PW = {"admin": ("qa-admin@qa.etqan.test", "QA-Admin-2026!"), "staffno": ("qa-staff-nocode@qa.etqan.test", "QA-People-2026!"),
      "staffc": ("qa-staff-codes@qa.etqan.test", "QA-People-2026!"), "sup": ("qa-supervisor@qa.etqan.test", "QA-People-2026!"),
      "teacher": ("qa-teacher@qa.etqan.test", "QA-People-2026!"), "student": ("qa-student@qa.etqan.test", "QA-People-2026!"),
      "parent": ("qa-parent@qa.etqan.test", "QA-People-2026!"), "student2": ("qa-student2@qa.etqan.test", "QA-People-2026!"),
      "parent2": ("qa-parent2@qa.etqan.test", "QA-People-2026!"), "parent3": ("qa-parent3@qa.etqan.test", "QA-People-2026!"),
      "student3": ("qa-student3@qa.etqan.test", "QA-People-2026!")}
def sessions(names):
    out = {}
    for n in names:
        s = S(); c = s.login(*PW[n]); out[n] = s
        if c != 200: log("login", n, c)
    return out
def oadmin():
    s = S(QO); c = s.login("qaother-admin@qa.etqan.test", "QA-Other-2026!"); return s
for _k in ["pay","payread","ratecreate","updnoview"]: PW["s_"+_k] = (f"qa-staff-{_k}@qa.etqan.test", "QA-People-2026!")
for _i in range(2, 15): PW[f"T{_i}"] = (f"qa-teacher{_i}@qa.etqan.test", "QA-People-2026!")
PW["T1"] = PW["teacher"]
ID = st_load().get("ids", {})
def mk(a, t, s, c, on, start, minutes, sa="present", ta="present", mark=True, **extra):
    """Extra session via API, then attendance via API. Returns session id."""
    body = {"student": ID[s], "course": ID[c], "teacher": ID[t], "occurs_on": on, "start_time": start, "minutes": minutes, **extra}
    code, j = a.post("/sessions/extra/", body)
    if code not in (200, 201): log("mk FAIL", code, short(j), body); return None
    sid = j.get("id") or (j.get("session") or {}).get("id")
    if mark:
        code2, j2 = a.post(f"/sessions/{sid}/attendance/", {"student_attendance": sa, "teacher_attendance": ta})
        if code2 not in (200, 201): log("mark FAIL", sid, code2, short(j2))
    return sid
