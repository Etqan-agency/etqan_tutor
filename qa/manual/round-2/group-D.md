# Round 2, group D: Missing information, behaviour and everything else (32 bugs)

Every bug below must end VERIFIED. Full details are in `qa/bug-register.md`.

- [x] ETQAN-QA-058 (P3, M02): The page asked for while signed out is forgotten: after sign-in the user lands on Home, not the deep link
- [x] ETQAN-QA-114 (P3, M03): A 5xx from `identity/me/` (server reload/deploy) signs the user out visually: the login page appears, with the host name instead of the academy name
- [x] ETQAN-QA-174 (P3, M04): Leaving a half-filled person form loses everything with no warning
- [x] ETQAN-QA-259 (P3, M07): Session page doesn't show which subscription it belongs to or how many lessons are left
- [x] ETQAN-QA-266 (P3, M07): Homework linked to a session never shows which session (no column in the list, nothing on the session page)
- [x] ETQAN-QA-304 (P3, M08): A second invoice for an already-invoiced subscription is created with no warning
- [x] ETQAN-QA-352 (P3, M09): Rates page is one 8,400-px column of teacher cards with no search or filter; per-student rates are only at the very bottom
- [x] ETQAN-QA-359 (P3, M09): Adjustments list doesn't flag adjustments in a currency the teacher is no longer paid in (they will never be paid)
- [x] ETQAN-QA-361 (P3, M09): Salary projection total subtracts a teacher's negative net (−1,000) from the academy's payroll total
- [x] ETQAN-QA-374 (P3, M09): Approve, pay and cancel-request dialogs for a withdrawal don't say which request (teacher, amount) they act on
- [x] ETQAN-QA-452 (P3, M15): Buying a paid recorded course (210.00 charged) leaves the family no receipt or invoice anywhere in the portal
- [x] ETQAN-QA-453 (P3, M15): Family never sees what it owes: no total due / unpaid filter on the invoices list and nothing about money on Home (student or parent)
- [x] ETQAN-QA-466 (P3, M15): Certificate print pages have no way back, and the admin's Arabic message is set in synthetic italics
- [x] ETQAN-QA-554 (P3, M05): Opening a deleted or unknown course shows a spinner forever
- [x] ETQAN-QA-557 (P3, M05): A price with more decimals than the currency allows is silently truncated (EGP 1500.559 saved as 1,500.55)
- [x] ETQAN-QA-558 (P3, M05): A package has no Delete action (courses do), although the API and docs offer DELETE with the in-use refusal
- [x] ETQAN-QA-575 (P3, M05): Subscription form accepts fewer weekly slots than the package's sessions per week, with no hint; the term then can't deliver the promised total
- [x] ETQAN-QA-601 (P3, M10): Chat thread is not its own scrolling panel: a long message or a few messages push the composer below the screen
- [x] ETQAN-QA-657 (P3, M11): Progress panel shows a topic by name only; the surah and verse range the office set (الملك ١–١٠) are not shown to the teacher, the office drawer or the student
- [x] ETQAN-QA-709 (P3, M13): Article slug-change warning gives no old address and no way to add the redirect it asks for
- [x] ETQAN-QA-763 (P3, M16): Visitor consultation booking, checkout and manage pages (/app/consult/…) have no academy name, header, language switch or link back to the site
- [x] ETQAN-QA-767 (P3, M16): Paying a payment link sends the payer no receipt, and the paid link page shows no date or reference
- [x] ETQAN-QA-803 (P3, M01): Add academy with a 200-character name (the field's own limit) crashes with a 500 DataError (varchar(120))
- [x] ETQAN-QA-817 (P3, M01): After adding a manual or credit line from an invoice, the operator lands on the global invoice-lines list, not back on the invoice
- [x] ETQAN-QA-162 (P4, M04): Teacher availability week starts on Monday in the Arabic UI (Egypt academy)
- [x] ETQAN-QA-362 (P4, M09): Withdrawals list (AR): the rejection reason is pushed to the far side of the Amount cell, away from the amount and note
- [x] ETQAN-QA-410 (P4, M14): My balance shows a total with no explanation of how it is made
- [x] ETQAN-QA-502 (P4, M12): Branding: logo, favicon and share-image pickers are bare native file inputs with no preview of the current image and no format/size hint
- [x] ETQAN-QA-559 (P4, M05): Editing a package doesn't say that existing subscriptions keep their old terms
- [x] ETQAN-QA-564 (P4, M05): Levels can be reordered only after filtering to one course; the default view shows no order controls and no hint
- [x] ETQAN-QA-566 (P4, M05): Educational content: the chosen course is forgotten on refresh (not in the URL)
- [x] ETQAN-QA-826 (P4, M01): Console home lists ~30 framework admins around the handful an Etqan operator uses; Tenants comes last
