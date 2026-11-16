import pathlib, subprocess
D = pathlib.Path(__file__).parent
LET = "M15 1h1v7h-1ZM5 1h1v6h1v-2h3v2h3v-1h1v2h-9ZM8 6v1h1v-1ZM1 5h1v2h1v-2h1v3h-3Z"
DOT = "M2 3h1v1h-1ZM7 3h1v1h-1ZM9 3h1v1h-1ZM11 4h1v1h-1ZM13 4h1v1h-1ZM15.2 9.2h.6v.6h-.6Z"
def mark(ink, gold, h=62):
    return (f'<svg viewBox="1 1 15 9" style="height:{h}px;width:auto" xmlns="http://www.w3.org/2000/svg">'
            f'<path fill="{ink}" fill-rule="evenodd" d="{LET}"/><path fill="{gold}" d="{DOT}"/></svg>')
def lockup(dark=False):
    ink = "#F6F1E7" if dark else "#1A5E43"
    return f'<div class="lockup">{mark(ink, "#C2A36B")}<span class="rule"></span><span class="name">ETQAN<br>TUTOR</span></div>'
def squares(cells):
    return "".join(f'<i class="sq" style="left:{c*54}px;top:{r*54}px"></i>' for c, r in cells)
HEAD = '<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="base.css"><style>{}</style></head>'

# A — the headline, light
a = HEAD.format("""
.wrap{position:absolute;inset:0;padding:120px 96px 96px;display:flex;flex-direction:column}
.mid{margin:auto 0}
h1{font-family:Fraunces;font-weight:600;font-size:118px;line-height:1.02;letter-spacing:-.02em;color:var(--green)}
h1 em{display:block;font-style:italic;font-weight:500;color:#8D6F27}
p{font-size:34px;line-height:1.5;margin-top:48px;max-width:860px;color:#3d3b35}
.foot{margin-top:auto;display:flex;justify-content:space-between;align-items:flex-end}
""") + f"""<body class="light">{squares([(17,0),(18,3),(1,3),(16,8),(2,19),(17,19),(12,21),(19,22)])}
<div class="wrap"><div class="eyebrow">For Quran, Arabic &amp; Islamic studies academies</div>
<div class="mid"><h1>Your entire academy.<em>Beautifully organized.</em></h1>
<p>Students, teachers, lessons, attendance, payments and progress, in one platform.</p></div>
<div class="foot">{lockup()}<span class="url">tutor.etqanpp.com</span></div></div></body></html>"""

# B — meet, dark
b = HEAD.format("""
.wrap{position:absolute;inset:0;padding:96px;display:flex;flex-direction:column;align-items:center;text-align:center}
.big{margin-top:250px}
h1{font-family:Fraunces;font-weight:500;font-size:96px;line-height:1.05;margin-top:90px;letter-spacing:-.01em}
h1 em{font-style:italic;color:var(--gold)}
p{font-size:32px;line-height:1.5;margin-top:34px;max-width:780px;color:rgba(246,241,231,.82)}
.foot{margin-top:auto;font-size:24px;font-weight:600;letter-spacing:.3em;color:var(--gold)}
""") + f"""<body class="dark">{squares([(2,2),(16,1),(17,6),(1,11),(18,15),(3,20),(15,22),(9,1)])}
<div class="wrap"><div class="big">{mark("#F6F1E7", "#C2A36B", 210)}</div>
<h1>Meet <em>Etqan Tutor</em></h1>
<p>The all-in-one platform for Quran, Arabic &amp; Islamic studies academies.</p>
<div class="foot">TUTOR.ETQANPP.COM</div></div></body></html>"""

# C — everything in one place, light, six tiles
tiles = [("Students &amp; teachers", "Every profile, class and family in one place"),
         ("Weekly schedules", "Sessions made from each subscription, in your time zone"),
         ("Attendance", "Taken in a tap, with alerts to guardians"),
         ("Hifz progress", "Surah by surah, verse by verse"),
         ("Invoices &amp; payslips", "Family invoices and teacher pay, from real sessions"),
         ("Arabic &amp; English", "The whole platform and your academy website")]
tile_html = "".join(f'<div class="t"><b class="n">{i+1:02d}</b><h3>{t}</h3><p>{d}</p></div>' for i, (t, d) in enumerate(tiles))
c = HEAD.format("""
.wrap{position:absolute;inset:0;padding:110px 86px 86px;display:flex;flex-direction:column}
h1{font-family:Fraunces;font-weight:600;font-size:78px;line-height:1.05;color:var(--green);margin-top:30px;letter-spacing:-.015em}
h1 em{font-style:italic;font-weight:500;color:#8D6F27}
.g{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-top:48px;margin-bottom:56px}
.t{background:#FFFDF8;border:1px solid rgba(194,163,107,.45);border-radius:22px;padding:28px 30px 30px;min-height:214px}
.n{display:inline-grid;place-items:center;width:54px;height:54px;background:var(--green);color:var(--parch);font-size:20px;font-weight:700;border-radius:6px}
.t h3{font-size:31px;font-weight:700;color:var(--ink);margin-top:22px}
.t p{font-size:23px;line-height:1.45;color:#5b584f;margin-top:10px}
.foot{margin-top:auto;display:flex;justify-content:space-between;align-items:flex-end}
""") + f"""<body class="light">{squares([(18,1),(1,0),(19,4)])}
<div class="wrap"><div class="eyebrow">Meet Etqan Tutor</div>
<h1>Your Quran academy, <em>all in one place</em></h1>
<div class="g">{tile_html}</div>
<div class="foot">{lockup()}<span class="url">tutor.etqanpp.com</span></div></div></body></html>"""

edge = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
for name, html in {"A-headline": a, "B-meet": b, "C-features": c}.items():
    f = D / f"{name}.html"; f.write_text(html, encoding="utf-8")
    subprocess.run([edge, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                    f"--screenshot={D / (name + '.png')}", "--window-size=1080,1350", "--virtual-time-budget=3000",
                    f.as_uri()], check=True, capture_output=True)
    print("rendered", name)
