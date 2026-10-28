
## Realistic layer (academy qa), created 2026-10-27T18:23:10Z by M02 data helper via API (admin session + CSRF)
All emails @qa.etqan.test, password QA-People-2026! (set via shell, email marked verified so sign-in works). Fictional.

### Teachers (role teacher)
| id | name | login |
|---|---|---|
| 228 | الشيخ أحمد الحداد (Ahmad Al-Haddad) | ahmad.haddad@ , availability Mon/Wed/Thu/Sat 16:00-21:00 |
| 229 | الأستاذة مريم الخطيب (Maryam Al-Khatib) | maryam.khatib@ |
| 230 | الأستاذ يوسف المنصوري (Yousef Al-Mansouri) | yousef.mansouri@ |

### Families (payer = parent)
| family id | name | parent (id, login) | children (id, login) |
|---|---|---|---|
| 13 | عائلة الشريف | 231 محمود الشريف, parent.sharif@ | 232 عمر الشريف student.sharif1@, 233 ليلى الشريف student.sharif2@, 234 زياد الشريف student.sharif3@ |
| 14 | عائلة النجار | 235 هدى النجار, parent.najjar@ | 236 آدم النجار student.najjar1@, 237 سلمى النجار student.najjar2@ |
| 15 | عائلة العتيبي | 238 فهد العتيبي, parent.otaibi@ | 239 خالد العتيبي student.otaibi1@, 240 نورة العتيبي student.otaibi2@, 241 ريان العتيبي student.otaibi3@ |
(Names are stored as "Arabic (English)".)

### Individual students
242 منى السيد (Mona Al-Sayed), 243 إبراهيم حسن, 244 فاطمة الزهراء, 245 Daniel Carter (US), 246 Aisha Rahman (US), 247 حمزة القاضي. Logins student.ind1@ .. student.ind6@.

### Catalogue
Courses: 7 حفظ القرآن الكريم / Quran Memorization; 8 التجويد للمبتدئين / Tajweed Basics; 9 اللغة العربية للناطقين بغيرها / Arabic for Non-Native Speakers.
Packages: 18 EGP 1,200.00 (2/wk, 45 min, 1 month); 19 USD 85.00 (same shape).

### Subscriptions (start 2026-10-27, weekly slots; sessions generated)
| sub | student | course | teacher | package | slots |
|---|---|---|---|---|---|
| 90 | 232 Omar | Quran | Ahmad | EGP | Mon+Thu 17:00 |
| 91 | 236 Adam | Tajweed | Maryam | EGP | Tue+Fri 18:00 |
| 92 | 239 Khalid | Quran | Yousef | EGP | Wed+Sat 19:00 |
| 93 | 245 Daniel | Arabic | Maryam | USD | Mon+Wed 20:00 |
(weekday numbers 0=Mon; times are academy-local Cairo)

### Invoices (auto-created on subscription)
INV-000154 (Omar, EGP 1200) PAID by bank transfer; INV-000157 (Daniel, USD 85) PAID cash; INV-000155 (Adam) and INV-000156 (Khalid) UNPAID, due +7 days.

### Notes
- People created through the API have no password and unverified email; the helper set passwords and verified email directly in the DB. Not a product path.
- Teacher role cannot call /schedule/today/ (403), unrelated to this data.
