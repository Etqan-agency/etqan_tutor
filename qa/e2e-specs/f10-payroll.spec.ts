// QA campaign F10 UI smoke (qa/specs/F10-payroll.md TC-025, TC-026, S4). Test-only.
// Academy `qa` (EGP, Africa/Cairo). The UI language is forced to English through localStorage.
import { mkdirSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import AxeBuilder from "@axe-core/playwright";
import { expect, type Page, test } from "@playwright/test";

const EVIDENCE = fileURLToPath(new URL("../../../qa/evidence/F10/pw", import.meta.url));
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

async function pickMonth(page: Page, year: number, month: number) {
	await page.goto(`${QA}/app/payroll/payslips`);
	await page.locator("#payslips-year").selectOption(String(year));
	await page.locator("#payslips-month").selectOption(String(month));
}

test("TC-025 office generates, issues and pays a month in the dashboard", async ({ page }) => {
	const errors: string[] = [];
	page.on("console", (m) => m.type() === "error" && errors.push(m.text()));
	const bad: string[] = [];
	page.on("response", (r) => r.status() >= 400 && bad.push(`${r.status()} ${r.url()}`));
	await login(page, ADMIN);
	// Fresh data: one completed 60-minute March session for T13 (rate 6000), through the scheduling API.
	const made = await api(page, "/sessions/extra/", "POST", { student: 5, course: 1, teacher: T13_ID, occurs_on: "2026-03-15", start_time: "09:00", minutes: 60 });
	expect(made.status).toBe(201);
	const marked = await api(page, `/sessions/${made.json.session.id}/attendance/`, "POST", { student_attendance: "present", teacher_attendance: "present" });
	expect(marked.status).toBe(200);
	await pickMonth(page, 2026, 3);
	await page.getByRole("button", { name: "Generate" }).click();
	await expect(page.getByText(/New: \d+\. Updated: \d+\. Removed: \d+\./)).toBeVisible();
	const list = await api(page, `/payroll/payslips/?year=2026&month=3&teacher=${T13_ID}`);
	const slip = list.json.results[0];
	expect(slip.status).toBe("draft");
	expect(slip.net_minor).toBe(6000);
	expect(slip.currency).toBe("EGP");
	await page.goto(`${QA}/app/payroll/payslips/${slip.id}`);
	await expect(page.getByRole("heading", { name: slip.number })).toBeVisible();
	await expect(page.getByText("60.00").first()).toBeVisible();
	const axe = await new AxeBuilder({ page }).analyze();
	const serious = axe.violations.filter((v) => ["serious", "critical"].includes(v.impact ?? ""));
	await page.getByRole("button", { name: "Issue" }).click();
	await page.getByRole("alertdialog").getByRole("button", { name: "Issue this payslip" }).click();
	await expect(page.getByText("Payslip issued.", { exact: true })).toBeVisible();
	await page.getByRole("button", { name: "Mark paid" }).click();
	const dlg = page.getByRole("dialog");
	await dlg.getByLabel("Paid on").fill(today());
	await dlg.getByLabel("Notes").fill("F10 UI cash");
	await dlg.getByRole("button", { name: "Mark paid" }).click();
	await expect(page.getByText("Payslip marked paid.", { exact: true })).toBeVisible();
	const after = await api(page, `/payroll/payslips/${slip.id}/`);
	expect(after.json.status).toBe("paid");
	expect(after.json.paid_on).toBe(today());
	expect(after.json.net_minor).toBe(6000);
	await page.screenshot({ path: `${EVIDENCE}/tc025-paid.png`, fullPage: true });
	await page.goto(`${QA}/app/payslips/${slip.id}/print`);
	await expect(page.getByText(slip.number).first()).toBeVisible();
	await page.screenshot({ path: `${EVIDENCE}/tc025-print.png`, fullPage: true });
	const pages: Record<string, boolean> = {};
	for (const p of ["rates", "adjustments", "settings"]) {
		await page.goto(`${QA}/app/payroll/${p}`);
		await page.waitForLoadState("networkidle");
		pages[p] = !(await page.getByText(/Couldn't load/).count());
	}
	save("tc025-ui.json", { slip: after.json, serious, pages, consoleErrors: errors, failedResponses: bad });
	expect(Object.values(pages).every(Boolean)).toBe(true);
	expect(serious).toEqual([]);
});

test("TC-026 teacher confirms receipt, requests and cancels a withdrawal", async ({ page }) => {
	await login(page, T2);
	const mine = await api(page, "/payroll/payslips/");
	const paid = mine.json.results.find((p: { status: string; acknowledged_at: string | null }) => p.status === "paid" && !p.acknowledged_at);
	expect(paid).toBeTruthy();
	expect(mine.json.results.every((p: { status: string }) => p.status !== "draft")).toBe(true);
	await page.goto(`${QA}/app/teaching/payslips/${paid.id}`);
	await page.getByRole("button", { name: "Confirm receipt" }).click();
	await page.getByRole("alertdialog").getByRole("button", { name: "Confirm you received this pay" }).click();
	await expect(page.getByText("Receipt confirmed.", { exact: true })).toBeVisible();
	const ack = await api(page, `/payroll/payslips/${paid.id}/`);
	expect(ack.json.acknowledged_at).toBeTruthy();
	const nav = await page.getByRole("link", { name: /^Payroll$/ }).count();
	await page.context().clearCookies();
	await login(page, T1);
	const before = await api(page, "/payroll/balances/");
	await page.goto(`${QA}/app/teaching/balance`);
	const avail = before.json[0].available_minor as number;
	await expect(page.getByText((avail / 100).toFixed(2)).first()).toBeVisible();
	await page.getByRole("button", { name: "Request a withdrawal" }).click();
	const dlg = page.getByRole("dialog");
	await dlg.getByLabel(/^Amount/).fill("10.00");
	await dlg.getByRole("button", { name: "Send request" }).click();
	await expect(page.getByText("Withdrawal request sent.", { exact: true })).toBeVisible();
	const w = await api(page, "/payroll/withdrawals/");
	const req = w.json.results[0];
	expect(req.amount_minor).toBe(1000);
	expect(req.status).toBe("under_review");
	await page.getByRole("button", { name: "Cancel request" }).first().click();
	await page.getByRole("alertdialog").getByRole("button", { name: "Cancel this request" }).click();
	// The row leaves "under review" and the confirm button unmounts: record whether the success toast shows.
	const toastSeen = await page.getByText("Request cancelled.", { exact: true }).first().waitFor({ timeout: 4000 }).then(() => true, () => false);
	save("tc026-cancel-toast.json", { toastSeen });
	const w2 = await api(page, `/payroll/withdrawals/${req.id}/`);
	expect(w2.json.status).toBe("cancelled");
	await page.screenshot({ path: `${EVIDENCE}/tc026-balance.png`, fullPage: true });
	save("tc026-ui.json", { acknowledged: ack.json.acknowledged_at, teacherPayrollNavLinks: nav, request: w2.json, balanceBefore: before.json, t2Id: T2_ID });
	expect(nav).toBe(0);
});

test("S4 unpaid-sessions warning after Generate, and after a reload", async ({ page }) => {
	await login(page, ADMIN);
	await pickMonth(page, 2026, 9);
	await page.getByRole("button", { name: "Generate" }).click();
	const warn = page.getByText(/were completed after their payslip was issued/);
	await expect(warn).toBeVisible();
	const text = await warn.textContent();
	await page.screenshot({ path: `${EVIDENCE}/s4-after-generate.png`, fullPage: true });
	await page.reload();
	await page.waitForLoadState("networkidle");
	const afterReload = await page.getByText(/were completed after their payslip was issued/).count();
	save("s4-ui.json", { warning: text, visibleAfterReload: afterReload > 0 });
	expect(text).toContain("QA teacher");
});
