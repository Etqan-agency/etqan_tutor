"""QA fix cycle (F06): ETQAN-QA-039 (a renewal over a kept old lesson is
reported),
ETQAN-QA-040 (deactivated people get no new sessions) and ETQAN-QA-042
(create and renew report a teacher's double-bookings, P4-9)."""

from datetime import UTC
from datetime import date
from datetime import datetime
from datetime import time

from etqan.scheduling import services
from etqan.scheduling.models import Session
from etqan.scheduling.tests.conftest import deactivated
from etqan.scheduling.tests.conftest import make_student
from etqan.scheduling.tests.conftest import make_teacher
from etqan.scheduling.tests.conftest import substitute
from etqan.scheduling.tests.conftest import two_slots

URL = "/api/v1/subscriptions/"


def days(sub):
    return sorted(
        Session.objects.filter(subscription=sub)
        .exclude(status=Session.Status.CANCELLED)
        .values_list("occurs_on", flat=True)
    )


# ── ETQAN-QA-039 ─────────────────────────────────────────────────────────────
# By design (B2b §10, B2a; test_renewal), a renewal also generates a date whose
# old lesson was marked and kept. The renew answer now reports that overlap
# (P4-9, ETQAN-QA-042), so the office sees it.


def test_a_renewal_over_a_kept_lesson_reports_the_overlap(api_for, subscribe, clock):
    old = subscribe(slots=two_slots())  # Mon + Wed 18:00 from Mon 1 June
    kept = Session.objects.get(subscription=old, occurs_on=date(2026, 6, 8))
    clock.set(datetime(2026, 6, 8, 20, tzinfo=UTC))  # after Monday's lesson
    Session.objects.filter(pk=kept.pk).update(
        status=Session.Status.COMPLETED,
        student_attendance="present",
        teacher_attendance="present",
    )
    resp = api_for("admin").post(
        f"{URL}{old.pk}/renew/", {"starts_on": "2026-06-08"}, format="json"
    )
    data = resp.json()
    assert resp.status_code == 201, data
    assert date(2026, 6, 8) in days(old.renewal)  # by design
    assert [c["other"]["id"] for c in data["conflicts"]] == [kept.pk]


# ── ETQAN-QA-040 ─────────────────────────────────────────────────────────────


def _drop_future(sub):
    Session.objects.filter(subscription=sub, occurs_on__gte=date(2026, 6, 8)).delete()


def test_the_job_gives_a_deactivated_teacher_no_new_sessions(subscribe, world):
    sub = subscribe(slots=two_slots())
    _drop_future(sub)
    deactivated(world.teacher)
    result = services.generate_horizon(sub)
    assert result.created == 0
    assert result.skipped_inactive == 3  # 8, 10 and 15 June
    assert max(days(sub)) == date(2026, 6, 3)


def test_the_job_gives_a_deactivated_student_no_new_sessions(subscribe, world):
    sub = subscribe(slots=two_slots())
    _drop_future(sub)
    deactivated(world.student)
    assert services.run_lifecycle()["created"] == 0
    assert max(days(sub)) == date(2026, 6, 3)


def test_an_active_substitute_still_covers_a_deactivated_teacher(subscribe, world):
    sub = subscribe(slots=two_slots())
    _drop_future(sub)
    cover = make_teacher("Hamza")
    world.course.teachers.add(cover.teacher_profile)
    substitute(sub, cover, date(2026, 6, 8), date(2026, 6, 10))
    deactivated(world.teacher)
    result = services.generate_horizon(sub)
    assert (result.created, result.skipped_inactive) == (2, 1)
    assert days(sub)[-1] == date(2026, 6, 10)


def test_the_today_board_leaves_out_a_deactivated_persons_missing_row(subscribe, world):
    sub = subscribe(slots=two_slots())
    _drop_future(sub)
    monday = date(2026, 6, 8)
    assert [r.state for r in services.today_board(monday)] == ["missing"]
    deactivated(world.teacher)
    assert services.today_board(monday) == []
    # A session already there still shows (marked lessons stay visible).
    assert [r.state for r in services.today_board(date(2026, 6, 1))] == ["generated"]


def test_reactivating_fills_the_horizon_again(subscribe, world):
    sub = subscribe(slots=two_slots())
    _drop_future(sub)
    deactivated(world.teacher)
    services.generate_horizon(sub)
    type(world.teacher).objects.filter(pk=world.teacher.pk).update(is_active=True)
    assert services.generate_horizon(sub).created == 3


# ── ETQAN-QA-042 ─────────────────────────────────────────────────────────────


def test_create_reports_the_teachers_double_booking(api_for, world, subscribe):
    subscribe(slots=two_slots())  # the teacher: Mon + Wed 18:00
    other = make_student("Zaid")
    resp = api_for("admin").post(
        URL,
        {
            "student": other.id,
            "course": world.course.id,
            "teacher": world.teacher.id,
            "package": world.package.id,
            "starts_on": "2026-06-01",
            "slots": [{"weekdays": [0], "start_time": "18:30"}],
        },
        format="json",
    )
    data = resp.json()
    assert resp.status_code == 201, data
    # 1, 8 and 15 June at 18:30 overlap the 18:00-18:45 lessons.
    assert len(data["conflicts"]) == 3
    assert {c["other"]["starts_at"][:10] for c in data["conflicts"]} == {
        "2026-06-01",
        "2026-06-08",
        "2026-06-15",
    }


def test_create_without_a_clash_reports_none(api_for, world):
    resp = api_for("admin").post(
        URL,
        {
            "student": world.student.id,
            "course": world.course.id,
            "teacher": world.teacher.id,
            "package": world.package.id,
            "starts_on": "2026-06-01",
            "slots": [{"weekdays": [0], "start_time": "18:00"}],
        },
        format="json",
    )
    assert resp.status_code == 201
    assert resp.json()["conflicts"] == []


def test_renew_reports_the_teachers_double_booking(api_for, world, subscribe):
    old = subscribe(slots=[{"weekdays": [0], "start_time": time(10)}])
    clash_student = make_student("Zaid")
    services.create_subscription(
        student_id=clash_student.id,
        course_id=world.course.id,
        teacher_id=world.teacher.id,
        package_id=world.package.id,
        starts_on=date(2026, 6, 1),
        slots=[{"weekdays": [0], "start_time": time(10, 15)}],
    )
    resp = api_for("admin").post(
        f"{URL}{old.pk}/renew/", {"starts_on": "2026-06-08"}, format="json"
    )
    data = resp.json()
    assert resp.status_code == 201, data
    assert len(data["conflicts"]) == 2  # 8 and 15 June
