# Round 3 decisions

Safe defaults applied by Agent 3, and proposals for anything risky. One section per area.

## M03 (Agent 3, 2026-11-01)

- **D-M03-1. The sidebar is a drawer below `lg` (ETQAN-QA-954/955).** It used to be always on
  from `md`. At 768 px that left about 480 px for the page, which crushed the Home cards and
  pushed the teacher's table sideways.
  - **Default applied:** in `AppShell`/`AppTopbar`, the sidebar is on from `lg` (1024 px). Below
    that, the hamburger opens the drawer. The Home shortcut tiles now hide at `lg`, to match.
  - Effect: 768 px tablets get the full width plus the drawer. 1024 px and wider look the same as
    before.
  - Not chosen: container queries on every card and table. That change is much bigger, and it
    wouldn't stop other pages from being cramped at 768 px.
- **D-M03-2. Net profit with several currencies (ETQAN-QA-951).**
  - **Default applied:** no currency line is "the" figure anymore. When there are several lines,
    every one uses the same size (`Stat`, `[&_li:not(:only-child)]:text-xl`). A lone figure stays
    large.
  - The overall estimate line is now normal-weight foreground text, not a muted footnote.
  - Red still marks a currency line that really is negative.
  - Per-currency net profit is unchanged, as finance.md specifies.
- **D-M03-3. Supervisor/limited-staff Home (ETQAN-QA-963).**
  - **Default applied:** a new "Today at a glance" card (`StaffTodayCard`) for staff accounts. It
    shows only the figures their codes open:
    - today's sessions (`session.view_any`);
    - missing reports (`session_report.view_any` + `session_reports`);
    - sessions they supervise (`session.supervise` + `supervision`).
  - Each figure links to its page.
  - When the card shows, the shortcut tiles hide where the sidebar is on screen (`lg`). This is
    the same rule as the other roles.
  - No new API: it reads counts from the existing list endpoints.
  - **Amended (cycle 2, after the gate failed the limited-staff half):** the tiles now hide at `lg`
    for every role, card or not, because from `lg` the sidebar is always beside them. A Home with
    nothing of its own shows a one-line pointer to the side menu at `lg` instead (`home.useSidebar`).
    Not chosen: a people-count card for people-only staff (new cross-feature queries for little gain).
- **D-M03-7. Phone top bar: the theme switch moves into the account menu (ETQAN-QA-953).**
  - **Default applied:** below `sm` (640 px) the light/dark button leaves the top bar and becomes the
    first item of the account menu ("الوضع الداكن" / "الوضع الفاتح"); the account button drops its
    chevron. The freed room lets the academy name show in full (two lines at most). From `sm` up
    nothing changes. Language, bell and menu stay in the bar.
- **D-M03-4. Where a list page's main action goes (ETQAN-QA-972).**
  - **Default applied:** the page's main create/generate action goes in `PageHeader actions`, at
    the end of the title row:
    - Today: "إنشاء الحصص لفترة";
    - Contracts: "Add contract";
    - Students, Teachers, Parents: "New …", plus Student reports on Students.
  - The list's own row keeps search, filters, export and the selection actions (send links).
  - Other list pages were not moved in this round.
- **D-M03-5. Home's arch backdrop (ETQAN-QA-969).**
  - **Default applied:** Home uses the quiet arch (`staticData.ornament: "quiet"`), like the other
    dense pages. It ends above the cards, so no pillar stubs show between them.
  - The teacher's section is now an opaque card (ETQAN-QA-966), so the lantern no longer sits
    behind its text.
- **D-M03-6. Words.**
  - "إعدادات تسجيل الدخول" / "Sign-in settings" / "Ajustes de inicio de sesión" names the
    Google sign-in settings page (ETQAN-QA-957).
  - "إنشاء" replaces the literal "ولّد" (ETQAN-QA-972).
  - The teacher check-in hint names the «دخلت» button, not "تسجيل الدخول" (ETQAN-QA-964).
  - Level-upgrade notices say "طلب ترقية", matching the sidebar's "طلبات الترقية"
    (ETQAN-QA-960).
  - Not changed: the roles screen's resource label `access/registry.py` "طلبات رفع المستوى". It
    is outside M03 and may be synced to stored roles, so it is left for the translation review.
- **Proposal (not applied).**
  - The teacher detail page still mounts its side cards (notification preferences) for a teacher
    id that doesn't exist. That is the same pattern as ETQAN-QA-971, but it was not filed. Apply
    the same `data !== undefined` gate if Agent 2 files it.

## M02 (Agent 3, 2026-11-01)
- **D-M02-1. Local phone numbers at sign-in (ETQAN-QA-916).**
  - **Default applied:** a number typed with the national "0" (`01009990947`) is completed with
    the calling code of the academy's country, read from the academy's timezone
    (`etqan/platform/phones.py`, a short list of the zones Etqan serves). A `00…` number becomes
    `+…`. Any other zone leaves a local number as typed, so it is refused as before and never
    matched to another country.
  - No new dependency (the `phonenumbers` library is not installed) and no migration. The
    password check is unchanged, so this cannot sign anyone into an account they don't hold.
  - **Proposal (not applied):** an explicit "country" in the academy settings would be more
    exact than the timezone; that needs a migration and a settings field.
- **D-M02-2. One name for two-step sign-in (ETQAN-QA-905).** Arabic uses "التحقق بخطوتين"
  everywhere (the sign-in step, the admin's people pages and the quick-login log already did);
  the Account card's "تسجيل الدخول بخطوتين" was renamed.
- **D-M02-3. Theme names (ETQAN-QA-911).** Arabic names describe the colours: "بنفسجي ليلي"
  (Dracula) and "أزرق شمالي" (Nord). English and Spanish keep the proper names. The mode is a
  two-option group "فاتح / داكن" instead of the moon icon.
- **D-M02-4. Sign-out and "sign in as" (ETQAN-QA-908, 932).**
  - Sign-out: the shell unmounts itself first, then the cache is cleared, then the browser goes
    to `/login`.
  - "Sign in as" and "back to my account": the previous person's page is left first, then the
    queries are reset. "Back to my account" returns to the page the admin started from (kept in
    `sessionStorage`, in-app paths only).
- **D-M02-5. Verify-email while signed in (ETQAN-QA-923, 924).** A signed-in person gets "تم
  تأكيد البريد الإلكتروني. يمكنك الآن استخدامه لتسجيل الدخول." and "العودة إلى الحساب". A
  signed-out visitor still gets the registration wording, because the API does not say whether
  the address belongs to a registration.
  - **Proposal (not applied):** `verify-email/` could return `{"registration": true}` so a
    signed-out person who added an extra address also gets the neutral text.
- **D-M02-6. Reset email (ETQAN-QA-928).** A branded email has the button "تعيين كلمة مرور جديدة"
  with the address in small type under it. The shared email layout now shows that fallback line
  under every email button. Etqan's own unbranded mail, which has no HTML, keeps the address in
  its text.
- **D-M02-7. Spanish (ETQAN-QA-913).** The Account page's cards (WhatsApp, Install the app,
  Notifications on this device) and every sidebar label now have Spanish text: 77 keys, and
  20 new `es/*.json` files that hold only those keys. Spanish stays a subset of English by
  design (spec L-1). The other ~2,700 missing keys, which belong to other pages, are left for
  the translation review.
- **D-M02-8. Long names (ETQAN-QA-934).** The Account form stops at 255 characters and gives its
  own message. The server's Django default Arabic message is still there for API clients. The
  people forms are ETQAN-QA-1016 (M04).
- **D-M02-9. Language button label (ETQAN-QA-938).** One convention: the label is always the
  language's full name in its own script (`LANGUAGE_NAMES`: "العربية", "English", "Español"),
  never a code. The two-way toggle names the language it switches to (it is an action: one press
  goes there); the three-language menu trigger names the current language with a check on it in
  the list (it is a selection). Changing the toggle to show the current language was rejected:
  a button reading "العربية" that switches to English is more confusing.

## M07 (Agent 3, 2026-11-01)

- **D-M07-1. Date placeholders "dd/mm/yyyy" (ETQAN-QA-1100, 1112).** The date and date-time
  fields are the browser's own controls. Chromium draws their placeholder in the browser's UI
  language, not the page's, so an Arabic browser already shows Arabic. The QA browser runs in
  English.
  - **Default applied:** the native controls stay. Building a custom date picker would be a large
    change for a cosmetic gain. The picker icon is already pinned to the field's end
    (ETQAN-QA-1083, shared `Input`), and every filter now has the same label and width.
- **D-M07-2. A past session that nobody marked (ETQAN-QA-1102).**
  - **Default applied:** the office Sessions list uses the same amber "لم يُسجَّل الحضور" chip as
    the teacher and family pages (`SessionStateChip`, ETQAN-QA-412/454). No API or status change.
- **D-M07-3. Bulk attendance on sessions that haven't started (ETQAN-QA-1115).**
  - **Default applied:**
    - "Mark present/absent" is disabled, with the reason shown, when none of the chosen sessions
      has started.
    - A mixed choice still runs, and the server skips the rest.
    - Skipped rows are named by student, day and time, and the result panel can be dismissed.
- **D-M07-4. The session's kind card (ETQAN-QA-1112).**
  - **Default applied:** the make-up links, "created by", "pays the teacher", Add make-up and
    Delete are now a section inside the summary card. The kind is already the header's chip. When
    there is nothing to show, the section is not drawn.
- **D-M07-5. The undo dialog's scrim (ETQAN-QA-1106).**
  - **Not changed:** the shared `--overlay` token is 55% in light mode and 68% in dark. The pale
    look in the screenshot was the 150 ms fade-in captured mid-animation. Only the copy was
    rewritten.
- **D-M07-6. The office's "Add review" (ETQAN-QA-1118).**
  - **Default applied:** the title matches the button ("إضافة تقييم"), and the subtitle reads
    "سجّل تقييم حصة نيابةً عن الطالب.".
  - The office dialogs (add and edit) use their own comment placeholder. The student's
    "Rate lessons" screen keeps its own wording.

## M04 People (Agent 3, round 3)

- **D-M04-1. Native date and time formats (ETQAN-QA-1014).** The date of birth and the
  availability times are the browser's own `date`/`time` controls, drawn in the browser's UI
  language (the QA browser runs in English).
  - **Default applied:** the native controls stay, as in D-M07-1. The other parts of the bug are
    fixed: the add button has a label (ETQAN-QA-1274) and the week is two columns from the
    medium breakpoint, so the empty days no longer make a 3,000 px page.
  - **Proposal (not built):** a custom Arabic date/time picker, if the owner wants Arabic digits
    and ص/م in an English browser too.
- **D-M04-2. One wording for add buttons (ETQAN-QA-1009).** Every list's add button reads
  "إضافة …" ("Add …") with a "+": إضافة طالب / ولي أمر / معلم / عائلة / مجموعة دراسية / موظف.
  "دعوة مدير" stays, because inviting is a different action, but it gains the user-plus icon.
  The "… جديد" keys stay as the new-person page titles. The add buttons of Families, Staff, Study
  groups and Admins moved into the page header's actions, following M03's ETQAN-QA-972. The status
  column is the shared `StatusChip` pill on Students, Families, Staff and Groups.
- **D-M04-3. "المسؤول عن الدفع" for a family's payer (ETQAN-QA-1028).** This applies to the
  family screens only. The payment-link screens (`gateways.json`, a different area) still say
  "الدافع", and are left for that area's owner.
- **D-M04-4. Tablet layout of the people lists (ETQAN-QA-1003).** Students, Parents and Teachers
  show one card per person below the extra-large breakpoint (1280 px), two cards per row from
  768 px, and the full table only where it fits. The filters sit in an even grid of their own,
  two columns on a phone and four from 768 px.
- **D-M04-5. Bulk bar (ETQAN-QA-1005).** The bar now sits under the list, pinned to the bottom
  of the screen (`sticky`), so ticking a row never moves the list. Its controls are in groups:
  account; status; tag; family. The counter is pluralised ("تم تحديد طالبين").
- **D-M04-6. Study-group student picker (ETQAN-QA-1021).** The list keeps its server limit (20)
  in a scrolling box, with outline "أضف" buttons. Search-first was not built.
- **D-M04-7. Last sign-in time (ETQAN-QA-1018).** An additive API field, `user.last_login`
  (ISO, or null), on the person payload. There is no migration, because it is Django's own
  column.
- **D-M04-8. Teachers CSV (ETQAN-QA-1027).** The "Course IDs" column became "Courses" (the
  course names in the academy's language, joined with "; "). The export is for people to read;
  nothing in the product parses it.
- **D-M04-9. Arabic search (ETQAN-QA-1026).** The shared folding (`platform/search.py`) now
  also joins "عبد" to the next word ("عبد الرحمن" = "عبدالرحمن"). Study groups (name and
  candidates) and Contracts (teacher name) use the folding. No migration.
- **D-M04-10. Bulk bar on a phone (ETQAN-QA-1005, cycle 2).** Below 640 px the bar is one line,
  the count and an "الإجراءات" toggle; the controls open on demand, capped at half the screen
  and scrolling inside. Each picker gets a line of its own, and its buttons share the next
  line evenly. From 640 px up nothing changed: the controls always show. Safe default: nothing
  is removed or hidden behind a permission, it is one extra tap on a phone only.
- **D-M04-11. Tabular figures only in figure columns (ETQAN-QA-1038).** The premium UI set
  `tabular-nums` on every table, and Inter's `tnum` also widens the hyphen, so every e-mail,
  code and file name in a table read "a - b - c". Safe default applied: tables no longer force
  it; end-aligned cells (`.text-end`/`.text-right`) and every `Money` / wallet amount keep
  tabular figures; cells that already said `tabular-nums` are unchanged. Start-aligned date and
  count cells now use Inter's proportional figures (Inter's digits are near-uniform, so the
  change there is a pixel or two). Not done: marking each of the ~38 inline `formatMoney`
  table cells by hand (they read fine either way); propose it only if a gate sees a ragged
  amount column.
- **D-M04-12. One search box component (ETQAN-QA-1039).** New `SearchInput` in `src/ui`; the
  five people-area list searches (Students/Parents/Teachers, Families, Staff, Contracts, Study
  groups) all use it. Same look as before for the three that had the icon.

## M09 Payroll (Agent 3, round 3, 2026-11-01)
- **D-M09-1. One word for a rate (ETQAN-QA-1208).** Everything priced per hour is "سعر": the
  per-student section is now "أسعار خاصة بالطلاب" (was "أجور حسب الطالب"), its buttons and dialog
  "إضافة سعر لطالب" / "حفظ السعر", the amount fields "سعر الساعة (EGP)", and a fixed salary
  "الراتب الشهري (EGP)". "أجر" stays only where the rules talk about pay for a session
  (Payroll rules weights). An empty "From month" now reads "هذا الشهر".
- **D-M09-2. "تحت تصرف الإدارة" stays the status's name (ETQAN-QA-1220).** It is the session status
  used across scheduling, trials and reports, so only the payroll rule was reworded ("دفع أجر
  الحصص الموضوعة «تحت تصرف الإدارة»") and the narrow counts column says "تحت التصرف".
- **D-M09-3. Session counts on the payslips list (ETQAN-QA-1228).** Kept as extra columns, with a
  visible thin scrollbar and the payslip number pinned at the start while the counts scroll. A
  per-payslip counts view was not built (the payslip page already shows its counters).
- **D-M09-4. Payslips list on a tablet (ETQAN-QA-1214).** It uses the shared `wideTableCards`
  (as the people lists, D-M04-4): cards below 1280 px, two a row from 768 px.
- **D-M09-5. Export CSV height, app-wide (ETQAN-QA-1231).** The shared `ExportButton` takes the
  default 44 px button height, since it always sits in a filter row of 44 px selects. This
  touches the 16 lists that show it; nothing else about them changes.
- **D-M09-6. Withdrawals filters in the address (ETQAN-QA-1226).** `?status=` (one of the five
  statuses), `?teacher=` and `?page=`, like the payslips list (ETQAN-QA-372). An unknown status is
  dropped.
- **D-M09-7. Withdrawal action slots (ETQAN-QA-1225).** The first action (Approve or Pay) has one
  minimum width, so Reject and Cancel line up across rows. The table's columns still widen
  when a page has any action row; fixing every column width was not done (it would cut long
  names and notes).
- **D-M09-8. Deductions in the adjustments list (ETQAN-QA-1217).** Shown with a minus sign and
  in the destructive colour; the stored amount is unchanged (still positive with `kind`).
- **D-M09-9. Fixed-salary start-month hint (ETQAN-QA-1208, cycle 2).** The month select's
  empty choice reads "هذا الشهر", so the hint no longer says "leave it empty". It now says what
  the other choices are for: "اختر شهرًا لاحقًا ليبدأ الراتب منه." / "Pick a later month to
  start the salary then." The empty value still means this month; behaviour is unchanged.
- **D-M09-10. Names kept on one line in titles (ETQAN-QA-1203, cycle 2).** Teacher names in the
  pay and withdrawal dialog titles and the issuer fact use no-break spaces (shared
  `unbrokenName()` in `dashboard/src/lib/bidi.ts`). Names longer than 32 characters keep normal
  spaces, so a very long name still wraps instead of overflowing a phone-width dialog.

## M14 Teacher portal (Agent 3, round 3, 2026-11-01)
- **D-M14-1. Native date/time pickers in Arabic (ETQAN-QA-1255) — PROPOSAL, not built.** Chromium
  draws `<input type="time|date">` in the browser's own language ("10:00 AM", "dd/mm/yyyy"),
  whatever the page's `lang`. A localised picker would be a new shared component replacing ~40
  date/time fields across scheduling, payroll and billing, which is a refactor, not a fix.
  Proposal: a shared `TimeField`/`DateField` in `dashboard/src/ui/` (two selects for hour and
  minute in the app's language, and a text date with an Arabic calendar popover), rolled out
  screen by screen. Done now: the file fields (homework create and edit) use the shared
  `FilePicker`, so "Choose File / No file chosen" is gone from the teacher portal.
- **D-M14-2. Homework search narrows the list (ETQAN-QA-1265).** The API was extended, without
  breaking anything: `GET learning/homework/?q=` filters by student name, with the same
  Arabic-aware folding as the people search (`platform/search.py`). Choosing a student from the
  matches still narrows it to that student. No match says "لا يوجد طالب بهذا الاسم.". The status
  tab and search are **not** put in the address (kept as local state, as before). That would be a
  separate change to the route.
- **D-M14-3. Homework and levels tables on a tablet (ETQAN-QA-1250).** Both use the shared
  `wideTableCards` (cards below 1280 px, two per row from 768 px), like people/payslips
  (D-M04-4, D-M09-4). The "My sessions" part is the same table as ETQAN-QA-955 (M03), so it was
  left to that fix.
- **D-M14-4. Card padding, app-wide (ETQAN-QA-1251).** `Card` now drops the top padding of a
  `CardContent` that opens the card (a leftover `pt-4`/`pt-6` from before the card had its own
  `py-6`), unless the card sets `py-0` itself. This applies to every such card, about 30 call
  sites: reviews, materials, certificates, wallet, recorded courses, homework and so on. Content
  after a header is unchanged.
- **D-M14-5. Invalid field + focus (ETQAN-QA-1258).** Shared `Input`, `Select` and `Textarea`:
  an invalid field keeps the red ring while it is focused. Before, a green focus ring was drawn
  over the red border. This changes the decision in ETQAN-QA-755, which let the green ring win.
- **D-M14-6. Join on a finished session (ETQAN-QA-1257).** In a sessions column (the teacher's list
  and the session page) a lesson that is over (completed, or past its end) shows "انتهت" instead
  of "انضمام". Family cards only list lessons still ahead, so they are unchanged.
- **D-M14-7. Consultations icon (ETQAN-QA-1272).** Consultations (teacher, family and the office's
  products) use lucide `Headset`, and chat keeps `MessagesSquare`.
- **D-M14-8. Wording (ETQAN-QA-1258/1259/1260/1261/1270).** These were reworded as follows:

  | Was | Now |
  |---|---|
  | "اختر واحدًا من الخمسة." | "اختر تقييمًا." |
  | report dialog body | "كيف كانت الحصة مع …؟ لا يطّلع على التقارير إلا فريق الأكاديمية." |
  | "اكتب التعليمات للواجب ذي الإجابة المكتوبة." | "اكتب تعليمات الواجب." |
  | withdrawal intro | "اختر العملة والمبلغ الذي تريد سحبه من رصيدك، على ألا يزيد على المتاح." |
  | "قسائم الراتب" | "كشوف الرواتب" (one term) |
  | "بدون مستوى" | "بلا مستوى فقط" |

  - The currency is shown by name everywhere in the teacher portal: the withdrawal select, the
    amount label and the payslip's "العملة".
  - Both search boxes now read "ابحث باسم الطالب".
  - EN and ES were updated to match.
- **D-M14-9. Teacher sessions table on a tablet (ETQAN-QA-1277, also covers M03's ETQAN-QA-977).**
  The shared `TeacherSessionTable` (My sessions and Home's Today) now uses `wideTableCards`
  (cards below 1280 px, two a row from 768), like homework and levels (D-M14-3). Stacking the
  attendance selects alone did not fit: EN 1024 still measured 737 px in a 710 px box. The two
  selects sit side by side only from 1440 px, so ETQAN-QA-1256's short rows at 1440 are kept.
  From 1280 to 1439 px they stack, because side by side EN 1280 overflowed (1049/966).
- **D-M14-10. Availability day boxes (ETQAN-QA-1278).** The day grid stretches its items, so the two
  days of a row have one height. An empty day's "أضف فترة" stays under its "لا توجد فترات" line.

## M06 — subscriptions & schedules (Agent 3, round 3)

- **R3-M06-D1. Pause after an early renewal (ETQAN-QA-1058) — PROPOSAL, not applied.** A pause on
  a period that already has a live renewal pushes that period's end past the renewal's start, so the
  two periods overlap. Options: (a) refuse such a pause with a 409 (`scheduling.pause_after_renewal`)
  and point to pausing the renewal instead; (b) move the renewal's start (and its sessions) by the
  paused days. Both change behaviour on live data, so neither was applied. What was applied: the
  add-pause dialog of a renewed subscription now warns about the overlap, and the summary note no
  longer claims lessons were "moved". Recommendation: (a), the smaller change.
- **R3-M06-D2. One Arabic term per action (ETQAN-QA-1068/1080).** Pause a subscription or bundle =
  **تجميد** ("فترات التجميد", "إضافة تجميد", "تجميد الحزمة", "أيام التجميد"); stop a slot or a
  schedule = **إيقاف**, status **متوقف**; start it again = **استئناف** (slot, bulk bar and schedule
  card; EN "Resume"); delete a schedule = **حذف** with **استرجاع** to undo. Applied in ar (en
  "Resume" to match).
- **R3-M06-D3. One shared person picker (ETQAN-QA-1081) — PROPOSAL.** The study-group, subscription
  and trial forms each pick a student their own way. A shared `PersonPicker` (search + capped list +
  "type to find the rest" hint) is a refactor across three forms and two endpoints, so it is left as
  a proposal. Applied now: the study-group list says when it is capped at 20.
- **R3-M06-D4. Price on bundle rows stays optional (ETQAN-QA-1082).** By design (B3d D-5): an empty
  bundle price keeps each member's own resolved price, so it is not marked required like the
  individual form's. Only the labels were aligned ("يبدأ", "الطالب 1/2").
- **R3-M06-D5. Editing a price leaves issued invoices alone (ETQAN-QA-1087) — default applied.** The
  edit dialog now says so under the price, and how to correct the unpaid invoice. Re-pricing an
  unpaid invoice automatically is a billing change (proposal), not applied.
- **R3-M06-D6. Delete is not offered while a subscription is invoiced (ETQAN-QA-1056).** The server
  already refuses; the button is hidden while `payment_status` shows a non-void invoice. With
  invoices off the button stays and the server decides.
- **R3-M06-D7. Bulk schedule actions follow the selection (ETQAN-QA-1067).** Stop for active rows,
  Resume for stopped, Delete for not-deleted, Restore for deleted; a mixed bundle row may take any;
  with no known row every action stays (the server decides).
- **R3-M06-D8. API additions (ETQAN-QA-1066/1072), additive only.** `GET /api/v1/schedules/` members
  gain `starts_on`, `ends_on`, `stopped_slots`; `GET /api/v1/schedules/candidates/` rows gain
  `starts_on`, `ends_on`. No migration; the page's select count is unchanged.
- **R3-M06-D9. Arabic buttons use the verbal noun (ETQAN-QA-1094) — default applied.** Action
  buttons read as verbal nouns ("إضافة / تعديل / حذف / تجديد / إلغاء / أرشفة / استرجاع / فتح /
  إنشاء / حفظ / إزالة / اختيار"), matching D-M04-2 ("إضافة …") and most existing labels in the area.
  Hints and error prompts stay imperative ("ابحث عن طالب", "اختر واحدًا."). The subscriptions list
  button is "إضافة اشتراك" (new key `scheduling.addAction`); "اشتراك جديد" stays the page title.
  Applied in ar only; en/es unchanged.
- **R3-M06-D10. Danger triggers in the area (ETQAN-QA-1093) — default applied.** Every M06
  confirmation trigger names its variant: deletes and removals are outline red
  (`destructiveOutline`), reversible steps (archive, restore a bundle) are plain outline and confirm
  in primary; only the dialog's final confirm of a real delete stays filled red. The shared
  `Confirm` default (filled red) was left as it is because other areas rely on it; proposal: switch
  that default to `destructiveOutline` app-wide once every area has signed off. The teacher account
  "تعطيل" (M04) is left to that area.
- **R3-M06-D11. Sub-page back links (ETQAN-QA-1092) — default applied.** The bundle page, the
  subscriptions archive and the expanded calendar use the header `BackLink` (arrow above the title)
  naming the list they return to; the bundle title is "<kind> bundle · <owner>".

## M08 Billing & finance (Agent 3, round 3)
- **R3-M08-D1. Display face (ETQAN-QA-1150) — default applied.** `@fontsource-variable/fraunces`
  registers the family as "Fraunces Variable"; the token's "Fraunces" never matched, so every
  `font-display` title rendered in Georgia (old-style figures). `dashboard/src/index.css` now names
  "Fraunces Variable" first in `--font-display`. Visible change: titles app-wide now draw in the
  intended Fraunces instead of Georgia. The `tokens` package itself is untouched (marketing loads
  its own fonts); a token release naming the variable family is proposed for later.
- **R3-M08-D2. Shared table frame and wide-table cards (ETQAN-QA-1155/1175/1181/1182).** New recipes
  `tableFrame` / `tableHead` in `src/ui/styles.ts`; payments, codes, links, online payments and
  invoices use `wideTableCards` (cards below 1280px), expenses and donations `phoneCards`.
- **R3-M08-D3. Row destructive actions are outlined (ETQAN-QA-1157/1183).** New Button variant
  `destructiveOutline`; `Confirm` accepts it. Applied to M08 row actions only (codes void/remove,
  payment and finance deletes, link cancel, wallet reverse, local method delete, invoice-payment
  delete) and the invoice's Void (moved to the far end of the toolbar). The app-wide `Confirm`
  default is unchanged; switching it globally is proposed (touches 39 screens in other areas).
- **R3-M08-D4. Status tones (ETQAN-QA-1151/1156/1179/1178).** StatusChip gains `caution` (amber, the
  existing warning pair) and `muted` (outlined). Invoice: unpaid neutral, partly paid caution, paid
  live, void muted. Codes: unused soft green, used neutral, expired/void muted. Checkouts and
  donations: failed negative, cancelled/expired muted.
- **R3-M08-D5. Arabic glossary for money (ETQAN-QA-1154/1163/1164/1178/1179/1183).** Batch of codes
  = "مجموعة الأكواد"; transaction id = "رقم العملية" everywhere; brand names stay Latin (Zelle,
  Venmo, Cash App, Stripe, PayPal); "Mark refunded" = "تسجيل كمستردّة"; "Move to balance" =
  "تحويل إلى رصيد الطالب"; code payment method = "خصم بكود"; checkout columns "الغرض" / "الدافع";
  wallet "Reverse" = "إلغاء الشحن". Subscription terms `system` relabelled "دورة الفوترة / Billing
  cycle" with `normal` = "حسب الباقة / Per package" (`monthly` unchanged). Stored codes unchanged.
- **R3-M08-D6. Amount cap (ETQAN-QA-1174) — default applied.** The shared money field refuses more
  than 1,000,000,000 (major units); the finance API refuses `amount_minor` above 10^12 with "This
  amount is too large." (serializer only, no migration). Invoices/payments backends are not capped
  server-side (proposal: same cap in billing serializers).
- **R3-M08-D7. Payment links CSV (ETQAN-QA-1187), additive API.** `GET /api/v1/gateways/links/?format=csv`
  (needs `export`, like the other lists); new CSV header translations in `platform/csv_labels.py`.
  Copy/Cancel are shown only for open links.
- **R3-M08-D8. Payroll expense titles (ETQAN-QA-1173) — PROPOSAL, not applied.** Expenses posted before
  ETQAN-QA-368 keep the title "… إيصال PAY-…". Renaming them is a data migration over posted rows
  (destructive to history), so proposed only: `UPDATE finance_expense SET title = replace(title,
  'إيصال PAY-', 'كشف راتب PAY-') WHERE source = 'payroll.payslip'` per academy schema. Applied now:
  labelled filters and the posted badge under the title instead of in the actions column.
- **R3-M08-D9. Return page reference (ETQAN-QA-1169).** A public checkout read deliberately omits
  what it pays for, so the page shows the link's own public title (only for a payment-link payer
  whose tab remembered the link) and a reference = last 8 characters of the checkout id.
- **R3-M08-D10. Phone number check on payment records (ETQAN-QA-1152).** Loose format (digits with
  optional +, spaces, dashes, brackets), not strict E.164, so existing local formats still save.

## M01 Etqan staff console (Agent 3, round 3, 2026-11-01)

- **D-M01-1. The staff console is English throughout (ETQAN-QA-1658, also clears QA-1657, QA-1659,
  QA-1676, QA-1678).** The bug offered two outcomes: a full Arabic console, or a consistently
  English one.
  - **Default applied:** `/admin/` always renders in English, whatever the browser asks
    (`etqan.platform.middleware.ConsoleLanguageMiddleware`, after `LocaleMiddleware`). The page is
    `lang="en" dir="ltr"`. So the mixed strings ("اختر academy لتغييره", "حسب status"),
    "وزارة الخارجية" for MFA, the ":Name" colons, the "أكتوبر 12, 2026" dates, the unmirrored
    breadcrumbs and the half-Arabic login error are all gone. The console's users are Etqan's own
    staff; academies never see it. Feature names keep their Arabic name in brackets, as before.
  - Not chosen, now a **proposal**: an Arabic console. It needs `gettext_lazy` on every console
    label, action, message and help text in `tenants`, `etqan_billing`, `integrations`, `identity`;
    `verbose_name`s on the public models (a no-op `AlterField` migration per field); a
    `backend/locale/ar` catalogue (no project catalogue exists yet; `msgfmt` is not in the image);
    project overrides for Django/allauth slips ("لا شي", "الالكتروني", "MFA"); an `ar`
    `FORMAT_MODULE_PATH`; and RTL breadcrumb CSS. Then the middleware goes.
- **D-M01-2. A failed academy's way out (ETQAN-QA-1654).** Spec 2026-10-29 says a failed build is
  retried by deleting the row and adding it again.
  - **Default applied:** the Delete button appears only for an academy that is "Creation failed"
    **and** has no schema (`tenants.services.may_delete`); its pending subdomain row goes with it,
    which frees the subdomain. Every other academy still can't be deleted, and there is no bulk
    delete. The change page explains the state in a read-only "Build" line.
  - Not chosen, a **proposal**: storing the failure reason on the academy (an additive
    `build_error` text column written by `provision_academy`) and a "Retry the build" action (it
    needs the admin email stored, too). Today the reason is only in the worker's log.
- **D-M01-3. Unbuilt academies are read-only for status, and never built by a save
  (ETQAN-QA-1651).** Status offers only Active/Suspended on a built academy; on a "Being created" or
  "Creation failed" academy it is read-only. A change-page save sets `auto_create_schema = False`, so
  `TenantMixin.save` can no longer run every migration inside the request.
  - **Data note (not changed, proposal):** QA R3 A (id 27) is already "Active"/"Suspended" with a
    schema and no admin, and QA R3 B (id 28) was made "Active" with no schema (ETQAN-QA-1656). The
    owner may suspend 27 and set 28 back to `failed` in the database, then delete 28 from the
    console. Nothing was changed in the data by Agent 3.
- **D-M01-4. Console layout at tablet and phone widths (ETQAN-QA-1674, QA-1675).**
  - **Default applied (console CSS in `templates/admin/base_site.html`):** below 1100 px the side
    menu is hidden (Home and the breadcrumbs list every page; Django already does this below
    768 px) and the filter panel sits under the list at full width. Below 768 px each list row is a
    card with one "Column: value" line per cell; the labels come from the table header by a small
    script. The action bar wraps with even gaps everywhere, and its extra inputs (Copy features
    from, Paid on…) show only for their own action.
- **D-M01-5. Money typed as money on a manual invoice line (ETQAN-QA-1666).** The amount is a
  decimal in the invoice's currency ("12.50"), converted to minor units with
  `platform.currency.from_decimal_string`; more decimals than the currency has is a field error;
  the ceiling is 1,000,000. Storage is unchanged (integer minor units).
- **D-M01-6. Old history rows (ETQAN-QA-1671), proposal only.** New lines are logged with their
  currency. The 2026-10-28 `django_admin_log` rows (ids 82–89: "Price<…>", "ConnectFee<22 250bp>",
  "Setup fee — رسوم الإعداد (1250 )") are left as they are: rewriting the audit log is
  destructive. If wanted, the owner may delete those QA-era rows by id.
- **D-M01-7. Issue asks first (ETQAN-QA-1665).** "Issue the selected drafts now" now shows a
  confirm page like Void. An invoice of an academy that was never built is refused. The message no
  longer claims the PDF went out; it points to "Emailed at", which the send task fills in.

- **D-M01-8. Tablet console lists (ETQAN-QA-1674, after gate cycle 2).** Between 768 and 1100 px
  the record timestamps (Academies "Created at", Domains "Verified at") are hidden in the lists
  so name, host, status and flags keep readable widths; they stay on each record's page, on the
  phone cards and at 1440. Words are never split mid-word; a date stays in one piece.

## M11 Learning & certificates (Agent 3, round 3, 2026-11-01)
- **D-M11-1. At-disposal in the report facts (ETQAN-QA-1511).** Following D-M09-2, the status keeps
  its name "تحت تصرف الإدارة" everywhere a session is shown; only the compact counts line of the
  monthly-report facts panel uses the short "تحت التصرف" (as the payroll counts column). Each
  "label: n" pair is kept on one line.
- **D-M11-2. "Pride" certificate (ETQAN-QA-1507).** The kind reads "فخر واعتزاز" and its printed
  title "شهادة فخر واعتزاز", the usual Arabic name for this certificate. English stays "Pride".
  The stored value `pride` is unchanged.
- **D-M11-3. Completed sessions at issue (ETQAN-QA-1507).** The field is optional (empty = the server
  counts the attended sessions, as the API already allows), so it loses its star rather than
  getting a required error. It stays required when editing an issued certificate.
- **D-M11-4. Card-table frame, app-wide recipe (ETQAN-QA-1522).** New shared `phoneCardsFrame` /
  `wideTableCardsFrame` in `dashboard/src/ui/styles.ts`: the bordered frame steps back when its
  table turns into cards. Applied to the M11 tables; other lists that pair `tableFrame` with
  `phoneCards` (expenses, donations, codes, payment links…) can switch to it with no other change.
- **D-M11-5. Free-text direction (ETQAN-QA-1504/1506).** New `textDir()` in `dashboard/src/lib/bidi.ts`:
  the script with more letters decides, a tie takes the UI's. Used for titles and summaries in
  M11 instead of first-strong `dir="auto"`, which turned "M11 عنوان…" left to right. File names and
  answers keep `dir="auto"`.
- **D-M11-6. Uniform row actions (ETQAN-QA-1510).** Row buttons read "تعديل" / "حذف" with the item in
  the accessible name; dialogs and confirms keep the full titles ("تعديل القالب", "حذف التكريم").
- **D-M11-7. New-homework exact match (ETQAN-QA-1519).** A search that matches one student's full
  name exactly picks that student, once per search (clearing the pick by hand sticks). The
  20-result cap stays; the hint says how to reach the rest.
- **D-M11-8. One phone page action (ETQAN-QA-1528, sweep).** Recommended default applied: on a
  phone the list page's main action is a full-width bar in its own row under the filters
  (Certificates, Reports, Library, Templates, Honour, Homework); from 640 px up it keeps its natural
  width at the end of the toolbar. Shared `pageAction` / `listToolbar` in `dashboard/src/ui/styles.ts`.
  Every add button carries the "+" (QA-1009); «رفع ملف» carries the upload arrow.
- **D-M11-9. One cut-list hint (ETQAN-QA-1529, sweep).** The homework dialog uses the shared
  `people.picker.more` («يظهر أول {{shown}} من {{count}} طالبًا. اكتب الاسم للوصول إلى البقية.»), shown
  under the search box as in `StudentPicker`; `homework.dialog.firstResults` removed. The 20 vs 100
  page sizes stay (the sentence now states the real numbers). `studyGroups.moreHint` belongs to
  another area and is left as is.
- **D-M11-10. Multi-line field direction (ETQAN-QA-1530, sweep).** Shared `ui/textarea.tsx` sets
  `dir={textDir(value)}` for a controlled string value when the caller gives no `dir`; an empty
  field takes the UI's direction. Uncontrolled textareas are unchanged.

## M12 Settings (Agent 3, round 3, 2026-11-01)
- **D-M12-1. One Save pattern on settings forms (ETQAN-QA-1358, 1367).** A form whose only action is
  Save uses the compact `SubmitButton` at the start, under the last field (`self-start`): sign-in,
  Stripe, PayPal, service fee, the role editor and academy settings. A Save that comes with a
  Cancel (the integration account forms) is laid out like a dialog footer: Cancel first, the
  primary last, at the end. Dialogs were already like that and stay unchanged.
- **D-M12-2. Time zones outside the common list (ETQAN-QA-1356).** No browser runtime names every
  city in Arabic, so the "all zones" group shows the zone's general name in the reader's language
  (Intl `longGeneric`, e.g. "توقيت وسط أوروبا") followed by the city as the zone database spells it
  ("— Ceuta") and the offset. The 30 common zones keep their translated city names. System status and
  the add-code hint use the same naming (`zoneLabel(zone, t, language)`). Values stay IANA ids.
- **D-M12-3. Registration code characters (ETQAN-QA-1369).** New codes allow letters a-z (any case,
  stored lower-case), digits and dashes only, checked on the server (`_clean_code`) and in the
  dialog. Existing codes are not touched (validation applies on create only), so the test code
  "xy z! تجربة" left by the repro stays as it is (codes cannot be deleted).
- **D-M12-4. Roles order (ETQAN-QA-1350).** The list is ordered active first, then retired, each by
  English name; the filter still defaults to "any status" (no change to the API's filter).
- **D-M12-5. PayPal page language (ETQAN-QA-1360).** The free-text "en-US" box became a list of nine
  common PayPal locales named by Intl in the reader's language; a saved code outside the list is
  kept as its own option, so nothing saved is lost. The server's `xx-XX` validation is unchanged.
- **D-M12-6. Run summary (ETQAN-QA-1362).** Instead of a sentence with plural agreement for four
  counts, the line lists only the counts that changed as "label: n" parts, and says "لم يتغيّر شيء."
  when all are zero. A 409 "run already open" is shown as a plain notice, not an error.
- **D-M12-7. Mode wording (ETQAN-QA-1360).** PayPal's "Environment: Sandbox/Production" became the same
  "Mode: Test/Live" as Stripe in all three languages; the unused `environment(s)` keys were removed.

## M10 Chat & notifications (Agent 3, round 3, 2026-11-01)

- **D-M10-1. Typed text takes the direction of the script it is mostly written in
  (ETQAN-QA-1452/1461/1474).** Round 1 kept `dir="auto"` (first strong letter) for chat bubbles and
  broadcasts (QA-604/617). The gate now asks for natural order, so:
  - **Default applied:** a shared `BidiText` (`dashboard/src/components/BidiText.tsx`, helper
    `bidiRuns` in `lib/bidi.ts`, built on the existing `textDir`): each line's direction comes
    from the script with more letters (a tie takes the page's), and each run of the other script is
    isolated with the punctuation typed right after it ("Thanks!", "R3-M10", "PM"). Used by chat
    bubbles and previews, the moderation list, the broadcasts list and detail. The broadcast email
    does the same per line (`channels/email._typed_line`).
  - A one-line preview keeps its text direction but aligns with the page (`text-left`/`text-right`
    from the UI language), so the list no longer zig-zags (ETQAN-QA-1454).
- **D-M10-2. One 12-hour clock for notice times (ETQAN-QA-1473).** The bell and notifications page
  now use the language's own short time (`clockTime`, "1:30 AM" / "1:30 ص"), like chat and
  broadcasts. Schedules keep `wallTime` (24-hour slot times) — not changed.
  - Backend `notifications/text.when/day`: Arabic "15/01/2026 6:00 م (القاهرة)", English
    "Jan 15, 2026, 6:00 PM (Cairo)" (city from the zone id); English dates "Jan 31, 2026" instead
    of ISO. Only new notices change; stored notices keep their text.
- **D-M10-3. WhatsApp not set up (ETQAN-QA-1476).** Additive API field: `GET/PATCH
  /api/v1/notifications/whatsapp/` now also returns `whatsapp_ready` (an account resolves for the
  academy). While false, the card cannot be turned on (it can still be turned off) and says the
  academy has not set WhatsApp up. Not chosen: hiding the card (people would lose the way to turn
  an old opt-in off).
- **D-M10-4. Broadcast delivery line (ETQAN-QA-1464).** The locked "Email" checkbox is replaced by
  one sentence ("in the app, and by email when they have an address"); the request still sends
  `channels: ["email"]` (email-whatsapp.md). Unused `composer.channels/email/inApp` keys removed.
- **D-M10-5. Tables as cards (ETQAN-QA-1460/1471/1478).** Broadcasts and Messages use the shared
  `wideTableCards` (cards below 1280 px, two per row from 768), since both are cramped at 1024;
  the notification log uses `phoneCards` (it fits from 640). Moderation gets a select-all box in
  the table head and, below 1280, one above the cards.
- **D-M10-6. Email call to action (ETQAN-QA-1474).** The notice email button reads "عرض في التطبيق" /
  "View in the app" for every notice type (was "افتحه من هنا" / "Open it here").

## M13 (Agent 3, 2026-11-01)
- **D-M13-1. Where a toast sits (ETQAN-QA-1572).** The success/error toast covered list rows'
  "تعديل"/"حذف" and form checkboxes, all of which sit at the row's end side.
  - **Default applied:** from `sm` up the shared `Toaster` viewport sits in the bottom *start*
    corner (`sm:end-auto sm:start-0`). On a phone it stays full width at the top (ETQAN-QA-654).
    The call room's centred control bar and dialogs' end-side footer buttons stay clear.
  - Not chosen: top-end below the top bar (it would cover the page header's actions, D-M03-4),
    or replacing every website toast with the inline `PublishNote` (editors that close after
    saving would lose the confirmation).
- **D-M13-2. One word for "shown on the site" (ETQAN-QA-1566).** No glossary existed yet.
  - **Default applied:** content that shows on the public site uses «منشور/منشورة» for its
    switch and «غير منشور/غير منشورة» for its chip: pages, testimonials, articles, videos, FAQs
    (was «مفعّل»), hero slides (was «إظهار على الموقع»/«ظاهرة»). Redirects keep «مفعّل/موقوف»:
    they are rules, not content. Ads keep «ساري/منتهي»: it is a validity state, not a switch.
  - "Order" + the published switch share one layout (`ORDER_ROW`/`CHECK_LABEL` in `ListRow.tsx`):
    two equal columns from `sm`, checkbox centred on the 44 px input row.
- **D-M13-3. Filters in the address (ETQAN-QA-1573).** Articles keep `?status=&category=&page=`
  and Videos `?status=` (validated in the route; the manager still works without the route).
- **D-M13-4. AI notes (ETQAN-QA-1570).** `AiDraftButton` gains `offNote` (default true, so other
  screens keep ETQAN-QA-1022's per-button note). The article editor passes `offNote={false}` and
  shows one `AiOffNote` at the top of the form. The buttons stay (muted) so the "not set up"
  dialog still explains how to turn AI on. Categories (2 buttons) are unchanged.
- **D-M13-5. Who handled an inquiry (ETQAN-QA-1577).** `handled_at` already existed (QA-712);
  the admin serializer adds a read-only `handled_by_name` (the user's `full_name`). No migration.
  Rows handled before `handled_at` existed still show only who.
- **D-M13-6. Name of the "system_only" site status (ETQAN-QA-1590, sweep).**
  - **Default applied:** the dashboard label becomes «الموقع مغلق» / "Site closed" / "Sitio cerrado"
    (it names what visitors get, like «يعمل» / «تحت الصيانة» / «تجريبي»); the hint still says
    sign-in keeps working. Stored value `system_only` unchanged.
  - Left as is: the backend `SiteSettings.Status` choice label "System only" (seen only in Django
    admin). Renaming a choice label makes Django want a migration; not worth one. Proposal: rename it
    next time that model gets a migration anyway.

## M05 (Agent 3, 2026-11-01)

- **D-M05-1. Latin currency symbols in Arabic amounts (ETQAN-QA-1402).** Intl gives Arabic no
  symbol of its own for USD, GBP, CAD, AUD, TRY, PKR… and falls back to "US$", "UK£", "TRY".
  - **Default applied:** in `formatMoney` (shared, `dashboard/src/lib/money.ts`), when the Arabic
    symbol contains Latin letters it is replaced by the currency's Arabic name ("85.00 دولار
    أمريكي"). Arabic symbols ("ج.م.", "ر.س."), "€" and "₹" and every English/Spanish amount are
    unchanged. This applies app-wide, not only to the catalogue.
  - Not chosen: `currencyDisplay: "name"` for every currency (would turn "ج.م." into "جنيه مصري"
    everywhere and lengthen every table).
- **D-M05-2. Dialog actions clipped at the panel edge (ETQAN-QA-1417).**
  - **Default applied:** the shared dialog footer (`dashboard/src/ui/dialog.tsx`) is sticky at
    the bottom of a scrolling panel, with the panel's colour behind it. A dialog that does not
    scroll lays out exactly as before. Every dialog and alert dialog gets it.
- **D-M05-3. Surah spellings (ETQAN-QA-1418).** The bundled data is fixed. Existing academies
  hold the old names in their own table.
  - **Default applied:** a data-only migration `learning/0006_fix_surah_spellings` corrects only
    rows that still hold the old bundled spelling (an academy's own edit is kept). No schema
    change. Applied to `academy_qa` only so triage can verify; the owner's next
    `migrate_schemas` applies it to the other academies (demo/other/khaled/journey-* untouched).
- **D-M05-4. Repeated copies (ETQAN-QA-1408).**
  - **Default applied:** besides locking the button while a copy is made, the backend numbers a
    copy whose name is taken: "غ (نسخة)", "غ (نسخة 2)", "غ (نسخة 3)" (`catalogue/services.py`
    `_copy_name`). No API change.
- **D-M05-5. Lengths in the recorded-course lists (ETQAN-QA-1427).**
  - **Default applied:** abbreviated units, which need no Arabic number agreement: "3 ث",
    "12 د", "1 س 5 د" (en "1 h 5 min"). The video form keeps HH:MM:SS for typing a duration.
- **D-M05-6. Consultation "enabled" flag (ETQAN-QA-1429).**
  - **Default applied:** renamed "معروضة للحجز" / "Open for booking" in the list column and the
    form, shown as a chip; "الحالة" (available/archived) unchanged. No data change.
- **D-M05-7. Course teacher picker (ETQAN-QA-1412).**
  - **Default applied:** search box + chosen count + compact 1/2/3-column scrolling list, the
    course's saved teachers first. Not chosen: a new combobox multi-select component (larger
    change, no shared one exists yet).

## M15 Student & parent portal (Agent 3, round 3, 2026-11-01)

- **D-M15-1. "ادفع" beside the outstanding total (ETQAN-QA-1301).**
  - **Default applied:** the button keeps opening the invoice due first (there is no "pay several
    invoices at once" flow), but with several invoices open it now says so: "ادفع أقدم فاتورة" /
    "Pay the oldest invoice". With one invoice it stays "ادفع".
  - Not chosen: a multi-invoice checkout. It would need a new API and gateway purpose.
- **D-M15-2. Honour board emoji (ETQAN-QA-1318).**
  - **Default applied:** the family board shows the app's line Trophy icon in a tinted tile for
    every entry, instead of the entry's colour emoji. The `emoji` field is kept as is: it is still
    stored and shown in the office's honour list, so no data changes.
  - Proposal for the owner: drop the emoji field from the honour form, or turn it into a choice of
    line icons, if the office no longer needs it.
- **D-M15-3. One payment reference (ETQAN-QA-1309).**
  - **Default applied:** the reference a family sees is the provider's transaction id, shortened to
    "…" plus its last six characters (`src/lib/payment-ref.ts` `shortRef`). It is used on the
    invoice page, the printed invoice, the receipts list and the payment return page. The return
    page falls back to the checkout id's tail only until the provider confirms (no transaction id
    yet). The office still sees the full id on the invoice page.
- **D-M15-4. A consultation whose time passed while still under review (ETQAN-QA-1304).**
  - **Default applied:** this is a display state only, with no change to the backend. The family
    list and page show "انتهى الموعد دون تأكيد" (amber), and a paid booking's note says to contact
    the academy instead of promising a confirmation "soon". The request status on the server is
    unchanged.
- **D-M15-5. Receipt descriptions (ETQAN-QA-1322).**
  - **Default applied:** the server stores the receipt's note in English ("Recorded course: …",
    "Consultation CR-…"). The family list words these in the reader's language and falls back to
    "دفعة إلكترونية" when there is no note. Each receipt has its own Print button, which prints
    only that receipt.
  - Proposal: give receipts a `kind` and an item reference on the server, so the label does not
    depend on the note's English prefix.

## M16 (Agent 3, 2026-11-01)

- **D-M16-1. The public site and the /app pages a visitor reaches from it look the same (ETQAN-QA-1613).**
  - **Default applied:** the signed-out pages (`AuthLayout`: sign-in, registration, certificate check,
    password reset…; `PublicFrame`: consultation booking, payment link, payment return) stay light,
    like the academy's site, and drop their theme switch. `useForceLight` does not touch the stored
    choice, so a signed-in user's dark mode comes back inside the app. A dark-only academy theme
    still wins. `index.html` skips the early `dark` class on those paths (no flash).
  - Not chosen: a dark theme for the whole Astro site. It is a full design pass (the site uses
    `--site-ink` both as heading colour and as the dark hero background) and is left as a proposal:
    **P-M16-1**, give the site a dark palette and a switch, then let the public /app pages follow
    it again.
- **D-M16-2. PWA manifest `theme_color` (ETQAN-QA-1612).**
  - **Default applied:** unchanged. The manifest installs the dashboard (`/app/`), which uses
    Etqan's emerald until the academy sets `colors_customized`, so `#146A51` matches the installed
    app. The site keeps the academy's raw `primary_color` and now says so in its own
    `<meta name="theme-color">`.
  - Proposal **P-M16-2**: decide whether the public site should also honour `colors_customized`
    (it would turn the `qa` site from `#0E7C66` to Etqan's emerald), then align both.
- **D-M16-3. What the anonymous return page may say (ETQAN-QA-1609).**
  - **Default applied:** the anonymous checkout read still hides its purpose and reference id (by
    design, G-15). It now carries only the provider's `transaction_number`. A consultation is
    described from the manage link the booking tab remembered (sessionStorage), which already
    holds the right to see it; otherwise the generic line explains the emailed link.
  - Proposal **P-M16-3**: expose a non-identifying `purpose` label on public checkouts, if the
    owner wants the return page to know a consultation without the remembered link.
- **D-M16-4. Signed-in detection on the site (ETQAN-QA-1600).** The SSR site reads only the
  presence of Django's HttpOnly `sessionid` cookie (no API call per page). A stale cookie shows
  "لوحتي", and `/app/` then asks for sign-in. Logout deletes the cookie.
- **D-M16-5. Signed-in family on `/consult/<id>` (ETQAN-QA-1601).** Students and parents are
  redirected to the account booking (`/learning/consultations/book?product=<id>`). Staff stay on
  the public form (they have no my/book).
- **D-M16-6. Words.** Pay buttons in Arabic: "ادفع عبر {provider}" everywhere, "تبرّع عبر" for a
  donation. Return page: "حالة الدفع" / "تم الدفع بنجاح، شكرًا لك.". Certificate: "لم نجد هذه
  الشهادة". Registration review: "راجع بياناتك قبل الإرسال".
- **D-M16-7. Recorded-course card footer at 768 (ETQAN-QA-1633, sweep).** Price, struck old price
  and "Course details" are each kept on one line (`whitespace-nowrap`) and the footer wraps as
  whole pieces. Two English cards per row leave 286 px; "EGP 20.00 EGP 100.00" + the link need
  ~287 px, and longer prices more, so a single line cannot be guaranteed without shrinking the
  type. Default applied: the link moves under the prices whole (start-aligned) instead of breaking
  into "Course / details" with the old price stacked. Arabic and 1440 stay on one line.
- **D-M16-8. One "back to site" string (ETQAN-QA-1636, sweep).** Sign-in now uses the shared
  `BackToSiteLink` (`common.backToSite`, "Back to the academy's website", into `/ar/` or `/en/`);
  the duplicate `auth.backToSite` key is removed from ar/en/es (no other user).

## Dropdown redesign (owner request)
Owner (Khaled), after round 3, with screenshots of the Students/Trials filter row in Arabic dark
mode: (1) the gap between a dropdown's text and its chevron is far too big, (2) field borders look
black/harsh, (3) replace the browser's select popup with a custom one in the brand colours. The
owner explicitly overrode the "deliberately native" rationale in `dashboard/src/ui/select.tsx`.
Built by Agent 3 (builder), 2026-11-01. Screens: `qa/manual/screens/r3/dropdown/build-*.png`.

- **Shape: native `<select>` underneath, custom listbox on top.** `Select` is now a wrapper
  (`data-slot="select"`: border, fill, focus ring, size) holding the chosen option's text, a
  chevron, and the real `<select>` laid transparently over it. The select stays the focused
  element, the `combobox` in the accessibility tree, the `<label htmlFor>` target, the
  `register()` binding and the form value. The popup is a `role="listbox"` in a portal, driven
  from the select with `aria-expanded` / `aria-controls` / `aria-activedescendant`
  (`aria-haspopup="listbox"`), so focus never leaves the field.
  - Why not a separate hidden select plus a `<button>` trigger: 440 `userEvent.selectOptions`
    calls in 122 unit-test files, ~270 Playwright `selectOption` calls, the `step.mjs` `select`
    action, `toHaveValue` on comboboxes and Field's cloned `id`/`aria-invalid`/`aria-describedby`
    all target the select. Keeping it as the combobox means every one of the ~258 call sites and
    every one of those tests and specs works unchanged (no e2e spec needed editing).
  - The select is `pointer-events: none`; the wrapper takes the pointer, so no browser (phones
    included) ever opens its own popup. The keys that would open the native popup (Enter, Space,
    Alt+Down, F4, arrows, typeahead) are intercepted.
  - Options are read from the select's own DOM, so `<TimezoneOptions/>`, fragments, `optgroup`s
    and late-loading options appear without call-site changes. The shown text follows a
    controlled `value`, a `change`, react-hook-form's `reset()`/`setValue()` (a hook on the
    instance's `value`/`selectedIndex` setters, since they fire no event) and option mutations.
  - Choosing sets `selectedIndex` and dispatches real `input` + `change` events (bubbling), so
    `onChange` gets the usual event with `target.value`.
- **Keyboard (WAI-ARIA select-only combobox).** Closed: Enter/Space/Alt+Down/Down/Up open,
  Home/End open on the first/last, a letter opens on the first match. Open: Up/Down (skip
  disabled), Home/End, PageUp/PageDown (10), typeahead (burst + repeated-letter cycling), Enter
  and Space choose, Alt+Up chooses, Escape closes and keeps focus, Tab chooses the highlighted
  option and moves on. Click outside / blur closes. Disabled options are shown dimmed,
  `aria-disabled`, never chosen. Escape inside a dialog closes only the list: Radix listens on
  `document` in capture, so the list listens on `window` in capture and stops it (verified: the
  "Add a session" dialog stays open, `build-06`).
- **Gap and width.** The wrapper sizes to the CHOSEN option's text, not the widest option (that
  was the native behaviour behind the big gap). `w-auto` filter selects are text + 8px gap +
  chevron with `ps-3 pe-2.5` and a `min-w-24` floor; form selects stay `w-full` with the chevron
  at the end. Long labels truncate with an ellipsis. Height stays 44px, focus ring identical
  (`has-[select:focus-visible]` versions of `focusRing(surface)`), invalid state as before (red
  border + red ring, focused or not, QA-755/1258), driven from the `aria-invalid` prop.
- **Popup look.** `bg-popover`, `border-border` hairline, `rounded-lg`, `shadow-lg`, `p-1`,
  opacity-only fade-in (`--animate-listbox-in`, reduced-motion off). Rows `min-h-9`, 44px on
  coarse pointers, `rounded-md`; hover/keyboard highlight `bg-secondary` (sand / ink.800); the
  chosen row has a check mark in a fixed start column (labels stay aligned) and an emerald tint
  (`bg-primary/10`, `/15` when also highlighted) with `text-primary-text`. Optgroup labels are
  small muted headings.
- **Placement.** Portalled into the nearest `role=dialog`/`alertdialog` (so Radix's
  outside-click and `pointer-events: none` on body don't fight it), else `document.body`;
  `position: fixed`, at least the trigger's width (up to 22rem or the viewport), anchored to the
  inline start so it mirrors in RTL; flips above when below has less than ~200px and above has
  more; max height 320px, scrolls (`overscroll-contain`), the chosen row centred on open, the
  highlighted row kept in view; repositions on scroll/resize; measures where it landed and
  corrects for a containing block made by a transformed/filtered ancestor; clamps to an 8px
  viewport margin (375px phone, `build-05`). The availability editor no longer uses selects
  (time inputs since an earlier round), so the 96-option case is gone; the largest list is the
  ~400-zone timezone picker, rendered only while open.
- **Raw `<select>` in feature code:** none left to convert (all already use `Select`). Three
  layout rules that targeted `select` children now target `[data-slot=select]`
  (`StudentsList` bulk bar, `PeopleList` filter grid, `NotificationLogPage` filters); their two
  assertions in `StudentsList.test.tsx` follow.
- **Border grey.** Light `--input` stays `#938D83` (sand.500): 3.13:1 on the page, already the
  3:1 floor, so no lighter grey is allowed. Dark `--input` was ink.500 `#87918D` at 5.29:1 on the
  page, the "harsh" white outline. New dark value: `--muted-foreground` mixed 58% over
  `--background` = `#797E7C`, same ink hue, 4.16:1 on `--background`, 3.26:1 on `--card` and
  `--popover` (ink.600 fails on card at 2.88:1). Inputs and textareas already use `border-input`,
  so every field matches.
  - Where: `tokens/src/color.dark.tokens.json` + regenerated `tokens.css` (uncommitted, contrast
    gate and `node --test` green; to release as v0.4.1), and a temporary bridge block in
    `dashboard/src/index.css` (`:root.dark { --input: color-mix(...) }`) because the dashboard pins
    the package by git commit. Written as a token mix, not a hex, so `check-colors.mjs` stays
    clean. **Proposal:** cut tokens v0.4.1, re-pin dashboard (and marketing), delete the bridge.
  - New `dashboard/src/test/input-border.test.ts` holds the bridge to the manifest: it computes
    the mix from the pinned package's own colours and asserts >= the manifest minimum on every
    surface `--input` is asserted against, and softer than the value it replaces.
  - Not changed: `--input` on `--secondary` (not in the manifest) drops from 3.03 to 2.38 in dark;
    no Select sits on a secondary surface today (the `surface="secondary"` call sites are Buttons).
- **Tests.** `select.test.tsx` rewritten for the new structure (17 tests: classes on the
  wrapper, pointer open/pick/close, disabled options, full keyboard pattern, typeahead, outside
  click, disabled field, `selectOptions` through the native select, `register()` + `reset()`,
  Field invalid state, optgroups).
  Five other tests asserted a Select's layout/invalid classes on the `<select>` itself; they now
  read them from its `data-slot="select"` box: `StudentsList` (2), `UserFieldsSection`,
  `RegisterPage`, `SessionsList`, `ScheduleCalendar`. No `selectOptions` call and no e2e spec
  needed changing. Gates: `tsc` clean; vitest `--maxWorkers=3` 4408/4409 (the one failure,
  `RequestDialog` "creates a request…", is a 5 s timeout under machine load: 1.8 s and green
  alone and in a rerun); biome: 0 errors (7 pre-existing warnings); `check-colors.mjs`: no new
  findings (4 pre-existing, other areas).

- **Cycle 2 (Agent 3, 2026-11-02), after the gate (`dropdown-gate.md`) failed:**
  - **G-1 (P0) pointer picks.** The option's `mousedown` bubbled through the React portal to the
    field's `onMouseDown`, which closed the list before the click. Fixed twice over: the field
    ignores presses from outside its own DOM subtree (`e.currentTarget.contains(e.target)`), and
    the listbox stops its `mousedown` and `click` from bubbling (so a clickable row or card around
    a select never reacts to a pick either). Regression tests in `select.test.tsx` use real
    pointer sequences: `userEvent.click` (pointerdown, mousedown, mouseup, click) with a clickable
    row around the field, a `[TouchA]` tap, `mouseDown` + `mouseUp` + `click`, and a disabled
    option. Verified in the app: mouse pick on Students (AR dark 1440, `build-10`), a real touch
    tap on Trials at 375 (`{"open1":1,"val":"not_scheduled","open2":0}`, `build-11`/`-12`), and a
    pick inside the "Add a session" dialog (value `extra`, list closed, dialog still open).
  - **G-2 gap on filter grids.** Students/Teachers/Parents (`PeopleList`): an even two-column grid
    of full-width selects only on a phone (where the filters are folded behind a button anyway),
    and from `sm` up one wrapping row of content-sized (`w-auto`) selects, like Trials and
    Invoices. Sessions: the even grid below `lg`, a wrapping row from `lg` with `lg:w-auto`
    selects and `lg:w-40` date fields. Measured gap text-to-chevron on Sessions EN 1440: 8 px
    (18 px on Period, see G-4). This supersedes the "even columns" of ETQAN-QA-1003/1100 above
    `sm`/`lg` by the owner's request; the phone layout of those fixes is kept. Form selects stay
    full width with the chevron at the end (the normal form pattern, accepted by the gate).
  - **G-3 bidi.** The trigger text and each option's label are wrapped in `<bdi>` (inline, inside
    a block, so alignment still follows the field's start): `+cmd`, `-5 days`, `(GMT+2)` keep
    their order in RTL.
  - **G-4 width jumps.** A content-sized field reserves the width of its FIRST option ("Any
    status"), which is almost always the placeholder, via an invisible `aria-hidden` ghost in the
    same grid cell (`::before { content: attr(data-ghost) }`, so it adds no text content to tests
    or screen readers). Picking a shorter value no longer shifts the row (Students: 96 px before
    and after picking "أنثى"); a value longer than the placeholder still widens the field. Not the
    widest option: that would bring the long gap back.
