import json
from datetime import date, time
from etqan.scheduling import services as s
from etqan.scheduling.models import Session
g = s.create_group(name="F10 group", student_ids=[5, 32, 33])
created = s.create_bundle("group", None, starts_on=date(2026, 5, 4), group_id=g.pk,
    rows=[{"course": 1, "teacher": 46, "package": 2, "slots": [{"weekdays": [0], "start_time": time(18, 0)}]}])
ids = []
for m in created.members:
    s.generate(date(2026, 5, 4), date(2026, 5, 4), subscription=m)
    ids += list(Session.objects.filter(subscription=m, occurs_on=date(2026, 5, 4)).values_list("pk", flat=True))
print("JSON" + json.dumps({"group": g.pk, "bundle": created.bundle.pk if hasattr(created, "bundle") else None, "sessions": sorted(ids)}))
