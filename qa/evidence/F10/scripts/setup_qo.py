import json
from etqan.identity import services as ids
from etqan.identity.models import User
from etqan.catalogue import services as cat
u = User.objects.filter(email="qo-teacher@qa.etqan.test").first()
if not u:
    u = ids.create_person("teacher", full_name="QO Teacher F10", email="qo-teacher@qa.etqan.test", profile={"gender": "male", "pay_currency": "USD"}, invite=False)
    u.set_password("QA-People-2026!"); u.save()
from allauth.account.models import EmailAddress
EmailAddress.objects.filter(user=u).update(verified=True)
from etqan.catalogue.models import Course
c = Course.objects.first() or cat.create_course(name_ar="F10", name_en="F10 QO Course", teacher_ids=[u.id])
c.teachers.add(u.teacher_profile)
print("JSON" + json.dumps({"teacher": u.id, "course": c.id, "student": User.objects.get(email="qo-student@qa.etqan.test").id}))
