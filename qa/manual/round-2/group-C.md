# Round 2, group C: Phone layouts and person pickers capped at 100 (24 bugs)

Every bug below must end VERIFIED. Full details are in `qa/bug-register.md`.

- [x] ETQAN-QA-118 (P3, M03): Phone: the teacher's "Today's sessions" table hides Attendance, Report and "I'm in" off-screen to the side
- [x] ETQAN-QA-171 (P3, M04): Registration review panel hides the registrant's phone, date of birth, gender and country; no link to the created student after approval
- [x] ETQAN-QA-173 (P3, M04): Phone (375): students list: nine filters fill the first screen and the 705 px table is squeezed into 341 px with a hidden sideways scroll
- [x] ETQAN-QA-202 (P3, M06): New subscription "Student" dropdown stops at the first 100 students with no hint; Arabic-named students are unreachable without the search box
- [x] ETQAN-QA-268 (P3, M07): Phone (375): admin "اليوم" table is 519 px in a 341 px box; names wrap into 3–5 lines and "التقدم"/"الحصة" are off-screen
- [x] ETQAN-QA-273 (P3, M07): "إضافة حصة" with kind "إضافية": the Student list stops at the first 100 active students, with no search; Arabic-named students can't get an extra session
- [x] ETQAN-QA-315 (P3, M08): Phone (375): invoices table is 754 px in 341 px (status, balance, due off-screen); filters fill the first screen; long transaction id runs past the card padding
- [x] ETQAN-QA-321 (P3, M08): English UI: Arabic local-method instructions are laid out LTR and scrambled (phone number jumps before "ثم أرسل … واتساب")
- [x] ETQAN-QA-369 (P3, M09): Phone (375): office payslips and withdrawals tables hide net, status and the action buttons behind a hidden sideways scroll
- [x] ETQAN-QA-371 (P3, M09): "إضافة أجر لطالب": student dropdown lists only the first 100 of 149 students, no search
- [x] ETQAN-QA-428 (P3, M14): Phone: students' levels table cuts the "فتح التقدّم" button at the screen edge and wraps names over 3 lines
- [x] ETQAN-QA-430 (P3, M14): Phone: teacher Homework table hides "الحالة", "تاريخ التكليف" and the only action "فتح" off-screen to the side
- [x] ETQAN-QA-457 (P3, M15): Phone (375): wallet statement table is 491 px in 293 px — amounts clipped, "الرصيد بعده" off-screen, invoice numbers broken over two lines
- [x] ETQAN-QA-472 (P3, M15): Phone receipt: payment amounts wrap onto their own line and read as belonging to the next payment
- [x] ETQAN-QA-663 (P3, M11): "إضافة تكريم": the Student dropdown lists only the first 100 students, no search; Arabic-named students can't be honoured
- [x] ETQAN-QA-779 (P3, M16): Contact/trial form: the phone error is shown in the success green under the button, the field is not marked, and "12" is told "digits only"
- [x] ETQAN-QA-818 (P3, M01): Etqan invoices list: five action inputs always shown in a cramped two-line bar, labels glued to the previous input; the table is cut off on the right
- [x] ETQAN-QA-178 (P4, M04): Parents list (EN): the "Invite pending" account pill wraps onto two lines
- [x] ETQAN-QA-317 (P4, M08): System codes (EN, 1440 px): the code wraps over two lines "SYS-NZE8E-" / "D46F1"
- [x] ETQAN-QA-652 (P4, M11): Homework detail dialog footer wraps to two rows: outline "حفظ" sits between "إغلاق" and the red "حذف الواجب", and the main "تحديد كمكتمل" drops alone below
- [x] ETQAN-QA-680 (P4, M11): Homework cards: the status chip moves under the title when the title wraps (else at the far end); English says "Completed" to students and "Complete" to teachers/office
- [x] ETQAN-QA-682 (P4, M11): Certificate detail dialog footer wraps to two rows: the main green "حفظ" drops alone under "إغلاق / إبطال الشهادة / حذف الشهادة"
- [x] ETQAN-QA-711 (P4, M13): Inquiries inbox: email and phone are plain text, not mailto:/tel: links
- [x] ETQAN-QA-822 (P4, M01): Periodic tasks list shows code names and cron strings with no description; the Last run column is cut off
