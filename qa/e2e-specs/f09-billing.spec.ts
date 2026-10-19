// QA campaign F09 UI smoke (qa/specs/F09-student-billing.md TC-001, TC-021, TC-022). Test-only.
// Academy `qa` (EGP, Africa/Cairo). The UI language is forced to English through localStorage.
import { mkdirSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { expect, type Page, test } from "@playwright/test";
import { invoiceHeader } from "../fixtures";

const EVIDENCE = fileURLToPath(new URL("../../../qa/evidence/F09/pw", import.meta.url));
mkdirSync(EVIDENCE, { recursive: true });
const save = (name: string, data: unknown) =>
	writeFileSync(`${EVIDENCE}/${name}`, JSON.stringify(data, null, 2));

const QA = "http://qa.etqan.localhost";
const ADMIN = { email: "qa-admin@qa.etqan.test", password: "QA-Admin-2026!" };
const PARENT = { email: "qa-parent@qa.etqan.test", password: "QA-People-2026!" };

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

const dueOn = () => new Date(Date.now() + 7 * 86_400_000).toISOString().slice(0, 10);

test("TC-001 owner creates a manual invoice, opens it and prints it", async ({ page }) => {
	const stamp = Date.now();
	await login(page, ADMIN);
	await page.goto(`${QA}/app/billing/invoices/new`);
	await page.getByLabel("Find a student").fill("QA student");
	await page.getByLabel(/^Student/).selectOption({ label: "QA student" });
	await expect(page.getByLabel(/^Billed to/).locator("option:checked")).toContainText("QA Parent Three");
	await page.getByLabel(/^Amount/).fill("500.00");
	await page.getByLabel(/^Due/).fill(dueOn());
	await page.getByLabel(/^Description/).fill(`F09 UI ${stamp}`);
	await page.getByRole("button", { name: "Create invoice" }).click();
	await expect(page).toHaveURL(/\/app\/billing\/invoices\/\d+$/);
	const id = page.url().match(/invoices\/(\d+)$/)?.[1] ?? "";
	const number = (await page.getByRole("heading", { name: /^INV-\d{6}$/ }).textContent()) ?? "";
	await expect(invoiceHeader(page, number).getByText("Unpaid", { exact: true })).toBeVisible();
	const detail = await api(page, `/billing/invoices/${id}/`);
	expect(detail.status).toBe(200);
	expect(detail.json.amount_minor).toBe(50000);
	expect(detail.json.currency).toBe("EGP");
	expect(detail.json.payer.full_name).toBe("QA Parent Three");
	await page.screenshot({ path: `${EVIDENCE}/tc001-detail.png`, fullPage: true });
	await page.goto(`${QA}/app/invoices/${id}/print`);
	await expect(page.getByText(number).first()).toBeVisible();
	await expect(page.getByText(/500\.00/).first()).toBeVisible();
	await page.screenshot({ path: `${EVIDENCE}/tc001-print.png`, fullPage: true });
	save("tc001-ui.json", { id, number, detail: detail.json });
});

test("TC-021 parent applies a discount code from the family invoice page", async ({ page, browser }) => {
	const stamp = Date.now();
	await login(page, ADMIN);
	const batch = await api(page, "/vouchers/batches/", "POST", {
		kind: "discount", quantity: 1, valid_days: 30, discount_kind: "percent", discount_value: 10, note: `F09 UI ${stamp}`,
	});
	expect(batch.status).toBe(201);
	const codes = await api(page, `/vouchers/codes/?batch=${batch.json.id}`);
	const code: string = codes.json.results.find((c: { batch: { id: number } }) => c.batch.id === batch.json.id).code;
	const inv = await api(page, "/billing/invoices/", "POST", {
		student: 5, amount_minor: 20000, due_on: dueOn(), description: `F09 UI code ${stamp}`,
	});
	expect(inv.status).toBe(201);
	const ctx = await browser.newContext();
	const parent = await ctx.newPage();
	await login(parent, PARENT);
	await parent.goto(`${QA}/app/learning/codes`);
	await parent.getByLabel(/^Code/).fill(code.toLowerCase().replaceAll("-", " "));
	await parent.getByRole("button", { name: "Check" }).click();
	await expect(parent.getByText(/10\s?%/).first()).toBeVisible();
	await parent.screenshot({ path: `${EVIDENCE}/tc021-codes-check.png`, fullPage: true });
	await parent.goto(`${QA}/app/learning/invoices/${inv.json.id}`);
	await parent.getByRole("button", { name: "Apply a code" }).click();
	const dialog = parent.getByRole("dialog");
	await dialog.getByLabel(/^Code/).fill(code);
	await dialog.getByRole("button", { name: "Apply", exact: true }).click();
	await expect(parent.getByText("Discount of EGP 20.00 applied.", { exact: true })).toBeVisible();
	await expect(invoiceHeader(parent, inv.json.number).getByText("Partly paid", { exact: true })).toBeVisible();
	await expect(parent.locator("li").filter({ hasText: "· System code" })).toContainText(code);
	await parent.screenshot({ path: `${EVIDENCE}/tc021-invoice.png`, fullPage: true });
	const after = await api(page, `/billing/invoices/${inv.json.id}/`);
	expect(after.json.paid_minor).toBe(2000);
	expect(after.json.balance_minor).toBe(18000);
	expect(after.json.status).toBe("partial");
	save("tc021-ui.json", { code, invoice: after.json });
	await ctx.close();
});

test("TC-022 parent pays an invoice online through the simulator", async ({ page, browser }) => {
	const stamp = Date.now();
	await login(page, ADMIN);
	const inv = await api(page, "/billing/invoices/", "POST", {
		student: 5, amount_minor: 30000, due_on: dueOn(), description: `F09 UI online ${stamp}`,
	});
	expect(inv.status).toBe(201);
	const ctx = await browser.newContext();
	const parent = await ctx.newPage();
	await login(parent, PARENT);
	await parent.goto(`${QA}/app/learning/invoices/${inv.json.id}`);
	await parent.getByRole("button", { name: "Pay online with Stripe" }).click();
	const sheet = parent.getByRole("dialog");
	await expect(sheet.getByText("EGP 15.00")).toBeVisible(); // 5 % fee
	await expect(sheet.getByText("EGP 315.00")).toBeVisible();
	await sheet.getByRole("button", { name: "Continue to Stripe" }).click();
	await expect(parent).toHaveURL(/\/app\/pay\/simulate\//);
	await parent.getByRole("button", { name: "Pay", exact: true }).click();
	await expect(parent.getByText("Paid — thank you.")).toBeVisible();
	await parent.getByRole("link", { name: "Back to the invoice" }).click();
	await expect(invoiceHeader(parent, inv.json.number).getByText("Paid", { exact: true })).toBeVisible();
	await parent.screenshot({ path: `${EVIDENCE}/tc022-paid.png`, fullPage: true });
	const after = await api(page, `/billing/invoices/${inv.json.id}/`);
	expect(after.json.status).toBe("paid");
	const pay = after.json.payments[0];
	expect(pay.method).toBe("stripe");
	expect(pay.amount_minor).toBe(30000);
	expect(pay.fee_minor).toBe(1500);
	expect(pay.currency).toBe("EGP");
	save("tc022-ui.json", after.json);
	await ctx.close();
});
