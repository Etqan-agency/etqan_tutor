# Run: dc.sh exec -T django python manage.py tenant_command shell --schema=academy_qa < setup_people.py
import json
from etqan.identity import services as ids
from etqan.identity.models import User
from etqan.catalogue.models import Course
out = {}
def teacher(key, email, name, cur="EGP", active=True):
    u = User.objects.filter(email=email).first()
    if not u:
        u = ids.create_person("teacher", full_name=name, email=email, profile={"gender": "male", "pay_currency": cur}, invite=False)
        u.set_password("QA-People-2026!"); u.save()
    for c in Course.objects.filter(pk__in=[1, 2]):
        c.teachers.add(u.teacher_profile)
    out[key] = {"user": u.id, "profile": u.teacher_profile.id}
teacher("T1", "qa-teacher@qa.etqan.test", "QA Teacher")
for i, n in [(2, "Two"), (3, "Three"), (4, "Four"), (5, "Five"), (6, "Six"), (7, "Seven"), (8, "Eight"), (9, "Nine"), (10, "Ten"), (11, "Eleven"), (12, "Twelve"), (13, "Thirteen"), (14, "Fourteen")]:
    teacher(f"T{i}", f"qa-teacher{i}@qa.etqan.test", f"F10 Teacher {n}")
teacher("TX", "qa-teacher-formula@qa.etqan.test", '=HYPERLINK("http://evil","x")')
for k, e in [("S1", "qa-student@qa.etqan.test"), ("S2", "qa-student2@qa.etqan.test"), ("S3", "qa-student3@qa.etqan.test")]:
    u = User.objects.get(email=e); out[k] = {"user": u.id, "profile": u.student_profile.id}
print("JSON" + json.dumps(out))
