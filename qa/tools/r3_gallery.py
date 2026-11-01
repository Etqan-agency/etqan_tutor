#!/usr/bin/env python3
"""Collect round-3 bugs (ETQAN-QA-900..1799) with before/after screenshots for the gallery.

usage: python3 qa/tools/r3_gallery.py <out_dir>
Writes <out_dir>/data.json and copies one before + one after shot per bug (JPEG, max 1200 px wide)
into <out_dir>/shots/.
"""
import json, os, re, subprocess, sys

QA = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(QA)
OUT = sys.argv[1]
SHOTS = os.path.join(OUT, "shots")
os.makedirs(SHOTS, exist_ok=True)

AREAS = {"M01": "Etqan console", "M02": "Sign-in & account", "M03": "Dashboards & navigation", "M04": "People",
         "M05": "Catalogue", "M06": "Subscriptions & schedules", "M07": "Sessions & attendance", "M08": "Billing & finance",
         "M09": "Payroll", "M10": "Chat & notifications", "M11": "Learning & certificates", "M12": "Settings",
         "M13": "Website admin", "M14": "Teacher portal", "M15": "Student & parent portal", "M16": "Public academy site",
         "TR": "Translation", "SM": "Final smoke walk"}
RANGES = [("M02", 900), ("M03", 950), ("M04", 1000), ("M06", 1050), ("M07", 1100), ("M08", 1150), ("M09", 1200),
          ("M14", 1250), ("M15", 1300), ("M12", 1350), ("M05", 1400), ("M10", 1450), ("M11", 1500), ("M13", 1550),
          ("M16", 1600), ("M01", 1650), ("TR", 1700), ("SM", 1800)]


def area_of(n):
    code = None
    for c, start in RANGES:
        if n >= start:
            code = c
    return code


text = open(os.path.join(QA, "bug-register.md"), encoding="utf-8").read()
blocks = re.split(r"(?m)^## (?=ETQAN-QA-\d+:)", text)
PNG = re.compile(r"(?:qa/manual/screens|/screens)/r3/[^\s`'\"),;]+?\.(?:png|jpe?g)")


def field(block, name):
    m = re.search(r"\*\*" + name + r":?\*\*:?\s*(.+)", block)
    return m.group(1).strip() if m else ""


def resolve(p):
    p = p.split("qa/manual/screens/")[-1] if "qa/manual/screens/" in p else p.lstrip("/").split("screens/", 1)[-1]
    full = os.path.join(QA, "manual", "screens", p)
    return full if os.path.exists(full) else None


def fixdir_shots(code, n, kind):
    out = []
    dirs = [os.path.join(QA, "manual", "screens", "r3", code, "fix")]
    if code in ("translation", "smoke"):
        dirs.append(os.path.join(QA, "manual", "screens", "r3", code))
    for d in dirs:
      if not os.path.isdir(d):
        continue
      for f in sorted(os.listdir(d)):
        if not (re.search(rf"(?<!\d){n}(?!\d)", f) and f.endswith((".png", ".jpg"))):
            continue
        is_before = "before" in f.lower()
        if (kind == "before") == is_before:
            out.append(os.path.join(d, f))
    return out


def shrink(src, name):
    dst = os.path.join(SHOTS, name + ".jpg")
    if not os.path.exists(dst):
        subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "60", src, "--out", dst],
                       capture_output=True)
        w = subprocess.run(["sips", "-g", "pixelWidth", dst], capture_output=True, text=True).stdout
        m = re.search(r"pixelWidth: (\d+)", w)
        if m and int(m.group(1)) > 900:
            subprocess.run(["sips", "--resampleWidth", "900", dst], capture_output=True)
    return "shots/" + os.path.basename(dst)


FINDING = {}
for fm in re.finditer(r"\| M\d+-R3-(\d+)[^|]*\| ETQAN-QA-(\d+)", open(os.path.join(QA, "manual", "round-3", "triage.md"), encoding="utf-8").read()):
    FINDING.setdefault(int(fm.group(2)), []).append(int(fm.group(1)))

items = []
for b in blocks:
    m = re.match(r"ETQAN-QA-(\d+):\s*(.+)", b)
    if not m:
        continue
    n = int(m.group(1))
    if n < 900 or n > 1849:
        continue
    code = area_of(n)
    head = field(b, "Feature")
    sev = re.search(r"\*\*Severity:\*\*\s*(P\d)", b)
    typ = re.search(r"\*\*Type:\*\*\s*([^.*]+)", b)
    ver = field(b, "Verification status")
    vlines = re.findall(r"\*\*Verif[^*]*\*\*:?\s*\**\s*(VERIFIED|FAILED|REGRESSED|OPEN|FIXED)", b)
    status = vlines[-1] if vlines else "OPEN"
    if status == "REGRESSED":
        status = "FAILED"
    evid = field(b, "Evidence")
    before = [resolve(p) for p in PNG.findall(evid)] + fixdir_shots({"TR": "translation", "SM": "smoke"}.get(code, code), n, "before")
    after = fixdir_shots({"TR": "translation", "SM": "smoke"}.get(code, code), n, "after") + \
        [resolve(p) for p in PNG.findall(ver) if "before" not in p]
    if not after:
        for fnum in FINDING.get(n, []):
            d = os.path.join(QA, "manual", "screens", "r3", code, "fix")
            if os.path.isdir(d):
                after += [os.path.join(d, f) for f in sorted(os.listdir(d))
                          if re.match(rf"^[a-z]+0*{fnum}(?!\d)", f) and "before" not in f.lower()]
    before = [p for p in before if p]
    after = [p for p in after if p and p not in before]
    fixm = re.search(r"\*\*Fix \(Agent 3[^)]*\):\*\*\s*(.+)", b) or re.search(r"\*\*Fix[^*]*\*\*:?\s*(.+)", b)
    items.append({
        "id": f"QA-{n}", "area": code, "areaName": AREAS.get(code, code),
        "sev": sev.group(1) if sev else "P3", "type": typ.group(1).strip() if typ else "",
        "title": m.group(2).strip(), "actual": field(b, "Actual")[:400],
        "fix": (fixm.group(1).strip()[:400] if fixm else ""), "status": status,
        "before": shrink(before[0], f"{n}-before") if before else None,
        "after": shrink(after[-1], f"{n}-after") if after else None,
    })

import base64
bundles = {}
for it in items:
    for k in ("before", "after"):
        if it[k]:
            raw = open(os.path.join(OUT, it[k]), "rb").read()
            bundles.setdefault(it["area"], {}).setdefault(it["id"], {})[k] = "data:image/jpeg;base64," + base64.b64encode(raw).decode()
            it[k] = True
os.makedirs(os.path.join(OUT, "pub"), exist_ok=True)
for a, d in bundles.items():
    json.dump(d, open(os.path.join(OUT, "pub", f"shots-{a}.json"), "w"))
json.dump({"areas": [[c, AREAS[c]] for c, _ in RANGES], "items": items},
          open(os.path.join(OUT, "data.json"), "w"), ensure_ascii=False)
both = sum(1 for i in items if i["before"] and i["after"])
both = sum(1 for i in items if i["before"] and i["after"])
print(f"{len(items)} bugs, {both} with before+after, {sum(1 for i in items if i['status']=='VERIFIED')} verified")
print("missing before:", [i["id"] for i in items if not i["before"]][:40])
print("missing after:", [i["id"] for i in items if not i["after"]][:40])
