# Round 2, group B: RTL / mixed text order and missing confirmations (18 bugs)

Every bug below must end VERIFIED. Full details are in `qa/bug-register.md`.

- [x] ETQAN-QA-050 (P3, M02): Saving the profile switches the interface to the stored "Preferred language" even when the user did not change it; the "Saved." toast then shows in the old language
- [x] ETQAN-QA-052 (P3, M02): Change password: two quick clicks send two requests, show two "Password updated." toasts and send two security-alert emails
- [x] ETQAN-QA-065 (P3, M02): Arabic "Last sign-in" line on a person's page reads in the wrong order ("آخر دخول: Africa/Cairo · حاسوب · 192.168.65.1"): the time zone comes first and reads like a place
- [x] ETQAN-QA-120 (P3, M03): English UI: an "Arabic (English)" name is shown with the bracket part first ("Assalamu alaikum, (Maryam Al-Khatib) الأستاذة مريم الخطيب"); regression of the QA-111/112 name isolation
- [x] ETQAN-QA-216 (P3, M06): Expanded weekly calendar: mixed Arabic/Latin names wrap with the bracket and hyphen on the wrong side ("Adam Al-) آدم النجار" / "(Najjar")
- [x] ETQAN-QA-217 (P3, M06): Deleting a pause or a stopped weekly slot happens on one click, with no confirmation and no message
- [x] ETQAN-QA-218 (P3, M06): Weekly schedules list and admin Sessions list (AR): "Arabic (Latin)" names wrap with the bracket and hyphen on the wrong side ("Hamza Al-) حمزة القاضي" / "(Qadi")
- [x] ETQAN-QA-355 (P3, M09): "إصدار" is offered on a draft that can't be issued (missing rate, month not over, negative net); the refusal comes only after confirming an "irreversible" action
- [x] ETQAN-QA-623 (P3, M10): Arabic emails: the footer's home link is mirrored ("/http://qa.etqan.localhost") since the email became RTL
- [x] ETQAN-QA-683 (P3, M11): Certificates (AR): "Arabic (English)" student names wrap with the bracket and hyphen on the wrong side on the print page, the public verification page and the office list
- [x] ETQAN-QA-712 (P3, M13): "وضع علامة كمُعالج" acts on one click with no toast and no way back; the handled view doesn't show who handled it or when
- [x] ETQAN-QA-121 (P4, M03): Phone, family invoices list: the status badge ("Void", "Partly paid", "Paid") floats mid-card under the balance, aligned to nothing
- [x] ETQAN-QA-272 (P4, M07): Wording of two cycle-1 strings: the attendance-undo dialog's keep button says "إبقاؤها", and an ended session with no link says "لا يوجد رابط بعد"
- [x] ETQAN-QA-320 (P4, M08): Arabic toast after applying a discount code ends with two full stops: "طُبّق خصم بقيمة 100.00 ج.م.."
- [x] ETQAN-QA-414 (P4, M14): Delete-homework confirmation opens over the homework dialog without dimming it; the two cards blend
- [x] ETQAN-QA-421 (P4, M14): "Confirm receipt" is a red danger-style button
- [x] ETQAN-QA-574 (P4, M05): New country-price row shows "السعر ()" with empty brackets and currency "—"
- [x] ETQAN-QA-626 (P4, M10): A chat conversation with no messages opens as a blank thread (no "no messages yet" line)
