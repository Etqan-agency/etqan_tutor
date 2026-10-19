// QA campaign F10 retest-1 UI check for ETQAN-QA-029. Test-only.
// Academy `qa` (EGP, Africa/Cairo). The UI language is forced to English through localStorage.
import { mkdirSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import AxeBuilder from "@axe-core/playwright";
import { expect, type Page, test } from "@playwright/test";

const EVIDENCE = fileURLToPath(new URL("../../../qa/evidence/F10/retest-1", import.meta.url));
mkdirSync(EVIDENCE, { recursive: true });
const save = (name: string, data: unknown) =>
	writeFileSync(`${EVIDENCE}/${name}`, JSON.stringify(data, null, 2));

const QA = "http://qa.etqan.localhost";
const ADMIN = { email: "qa-admin@qa.etqan.test", password: "QA-Admin-2026!" };
const T1 = { email: "qa-teacher@qa.etqan.test", password: "QA-People-2026!" };
const T2 = { email: "qa-teacher8@qa.etqan.test", password: "QA-People-2026!" };
const T13_ID = 47;
const T2_ID = 42;

async function login(page: Page, who: { email: string; password: string }) {
	await page.goto(`${QA}/app/login`);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));
	await page.reload();
	await page.getByRole("textbox", { name: /email/i }).fill(who.email);
	await page.getByRole("textbox", { name: /^password$/i }).fill(who.password);
	await page.getByRole("button", { name: /^sign in$/i }).click();
	await page.waitForURL((u) => !u.pathname.includes("/login"));
}

const api = (page: Page, path: string, method = "GET", body?: object) =>
	page.evaluate(
		async ({ path, method, body }) => {
			const csrf = document.cookie.match(/csrftoken=([^;]+)/)?.[1] ?? "";
			const r = await fetch(`/api/v1${path}`, {
				method,
				headers: { "Content-Type": "application/json", "X-CSRFToken": csrf },
				body: body ? JSON.stringify(body) : undefined,
			});
			return { status: r.status, json: await r.json().catch(() => null) };
		},
		{ path, method, body },
	);

const today = () =>
	new Intl.DateTimeFormat("en-CA", { timeZone: "Africa/Cairo" }).format(new Date());


test("QA-029 UI: mark paid before the payslip's month shows the paid_on error, month start is accepted", async ({ page }) => {
	await login(page, ADMIN);
	const made = await api(page, "/sessions/extra/", "POST", { student: 5, course: 1, teacher: T13_ID, occurs_on: "2026-02-16", start_time: "09:00", minutes: 60 });
	expect(made.status).toBe(201);
	expect((await api(page, `/sessions/${made.json.session.id}/attendance/`, "POST", { student_attendance: "present", teacher_attendance: "present" })).status).toBe(200);
	expect((await api(page, "/payroll/payslips/generate/", "POST", { year: 2026, month: 2 })).status).toBe(200);
	const slip = (await api(page, `/payroll/payslips/?year=2026&month=2&teacher=${T13_ID}`)).json.results[0];
	expect(slip.status).toBe("draft");
	expect((await api(page, `/payroll/payslips/${slip.id}/issue/`, "POST", {})).status).toBe(200);
	await page.goto(`${QA}/app/payroll/payslips/${slip.id}`);
	await page.getByRole("button", { name: "Mark paid" }).click();
	const dlg = page.getByRole("dialog");
	await dlg.getByLabel("Paid on").fill("2026-01-31");
	await dlg.getByRole("button", { name: "Mark paid" }).click();
	await expect(dlg.getByText("A payslip can't be paid before the month it pays.")).toBeVisible();
	await page.screenshot({ path: `${EVIDENCE}/qa029-ui-refused.png`, fullPage: true });
	const mid = await api(page, `/payroll/payslips/${slip.id}/`);
	expect(mid.json.status).toBe("issued");
	await dlg.getByLabel("Paid on").fill("2026-02-01");
	await dlg.getByRole("button", { name: "Mark paid" }).click();
	await expect(page.getByText("Payslip marked paid.", { exact: true })).toBeVisible();
	const after = await api(page, `/payroll/payslips/${slip.id}/`);
	expect(after.json.status).toBe("paid");
	expect(after.json.paid_on).toBe("2026-02-01");
	await page.screenshot({ path: `${EVIDENCE}/qa029-ui-paid.png`, fullPage: true });
	save("qa029-ui.json", { id: slip.id, number: slip.number, mid: mid.json.status, after: { status: after.json.status, paid_on: after.json.paid_on, net_minor: after.json.net_minor } });
});
