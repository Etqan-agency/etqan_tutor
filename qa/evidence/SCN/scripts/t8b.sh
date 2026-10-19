. ./lib.sh; . ./ids.env
echo "-- TC-008 addendum: U1 ended today (<24h) so by design (reports.py REPORT_DUE_AFTER=24h) it is not yet missing; U4 ended 2026-10-18 11:00Z (>24h)"
api tea qa GET reports/missing/; echo "U4 in missing: $(j "any(x['id']==$U4 for x in d['results'])")"
W=150 r tea qa PUT sessions/$U4/report/ '{"behaviour":4,"participation":4,"notes":"SCN U4"}'
api tea qa GET reports/missing/; echo "U4 in missing after report: $(j "any(x['id']==$U4 for x in d['results'])")"
echo "-- parent/student payload has_report? (reports are staff-only by design, can_read_report)"
api pa qa GET sessions/$U1/; echo "PA U1 keys: $(j "sorted(d.keys())")"
