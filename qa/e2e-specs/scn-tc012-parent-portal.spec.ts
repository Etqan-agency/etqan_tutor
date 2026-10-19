// QA campaign SCN (Agent 2): integrated scenario D, UI smoke 2 (SCN-TC-012). Test-only.
// Parent "SCN Parent A" (FAM-A: SCN Student A1, A2). Data from qa/evidence/SCN/scripts (TC-007, TC-011).
import { mkdirSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { expect, type Page, test } from "@playwright/test";

const EVIDENCE = fileURLToPath(new URL("../../../qa/evidence/SCN/pw", import.meta.url));
mkdirSync(EVIDENCE, { recursive: true });
const QA = "http://qa.etqan.localhost";
const INV1 = Number(process.env.SCN_INV1);
const INVB = Number(process.env.SCN_INVB);
const SB1X = Number(process.env.SCN_SB1X);

async function login(page: Page, email: string, password: string) {
	await page.goto(`${QA}/app/login`);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));
	await page.reload();
	await page.getByRole("textbox", { name: /email/i }).fill(email);
	await page.getByRole("textbox", { name: /^password$/i }).fill(password);
	await page.getByRole("button", { name: /^sign in$/i }).click();
	await page.waitForURL((u) => !u.pathname.includes("/login"));
}

const api = (page: Page, path: string) =>
	page.evaluate(async (p) => {
		const r = await fetch(`/api/v1/${p}`);
		return { status: r.status, body: await r.json().catch(() => null) };
	}, path);

test.describe.configure({ mode: "serial" });

test("SCN-TC-012 parent sees the children's sessions and attendance, the invoice with the wallet payment; FAM-B is not found", async ({
	page,
}) => {
	const errors: string[] = [];
	page.on("response", (r) => r.status() >= 500 && errors.push(`${r.status()} ${r.url()}`));
	await login(page, "scn-parent-a@qa.etqan.test", "QA-People-2026!");

	// Sessions page
	await page.goto(`${QA}/app/learning/sessions`);
	await expect(page.getByRole("heading", { name: "My sessions" })).toBeVisible();
	const item = (text: string) => {
		const [date, time, who] = text.split("|");
		const sp = "[\\s\\u00a0\\u202f]*";
		return page.getByRole("listitem").filter({ hasText: new RegExp(`${date.replace(/ /g, sp)}${sp}${time}${sp}${who}`) });
	};
	await expect(item("Oct 19, 2026|10:00|SCN Student A1")).toContainText("Present");
	await expect(item("Oct 19, 2026|11:00|SCN Student A1")).toContainText("Absent");
	await expect(item("Oct 19, 2026|12:00|SCN Student A1")).toContainText("Excused");
	// Local Cairo wall clock on both sides of the 2026-10-30 DST change.
	await expect(item("Nov 2, 2026|18:00|SCN Student A1")).toHaveCount(1);
	await expect(item("Oct 20, 2026|17:00|SCN Student A2")).toHaveCount(1);
	await expect(item("Oct 30, 2026|17:00|SCN Student A2")).toHaveCount(1);
	await page.screenshot({ path: `${EVIDENCE}/tc012-parent-sessions.png`, fullPage: true });
	const bodyText = await page.locator("main").innerText();
	writeFileSync(`${EVIDENCE}/tc012-parent-sessions.txt`, bodyText);
	expect(bodyText).not.toContain("SCN Student B1");
	const own = await api(page, "sessions/?page_size=100");
	const shown = await page.getByRole("listitem").filter({ hasText: /SCN Student A[12]/ }).count();
	writeFileSync(`${EVIDENCE}/tc012-parent-sessions-count.txt`, `api count ${own.body.count}, list items ${shown}\n`);

	// Invoices page
	await page.goto(`${QA}/app/learning/invoices`);
	await expect(page.getByText("INV-000146").first()).toBeVisible();
	await page.screenshot({ path: `${EVIDENCE}/tc012-parent-invoices.png`, fullPage: true });
	const invText = await page.locator("main").innerText();
	writeFileSync(`${EVIDENCE}/tc012-parent-invoices.txt`, invText);
	expect(invText).not.toContain("INV-000149");

	// Invoice detail: 1,500.00 total, 300.00 paid from the wallet, balance from the API
	await page.goto(`${QA}/app/learning/invoices/${INV1}`);
	await expect(page.getByText("INV-000146").first()).toBeVisible();
	const detail = await api(page, `billing/invoices/${INV1}/`);
	expect(detail.status).toBe(200);
	const detText = await page.locator("main").innerText();
	writeFileSync(`${EVIDENCE}/tc012-parent-invoice-detail.txt`, `${detText}\n---API---\n${JSON.stringify(detail.body)}`);
	await page.screenshot({ path: `${EVIDENCE}/tc012-parent-invoice-detail.png`, fullPage: true });
	expect(detText).toMatch(/1,500\.00/);
	const bal = (detail.body.balance_minor / 100).toLocaleString("en-US", { minimumFractionDigits: 2 });
	expect(detText).toContain(bal);

	// FAM-B invoice and session URLs show not-found and no data
	await page.goto(`${QA}/app/learning/invoices/${INVB}`);
	await expect(page.locator("main")).not.toContainText("Loading", { timeout: 20000 });
	const nf = await page.locator("main").innerText();
	writeFileSync(`${EVIDENCE}/tc012-parent-famb-invoice.txt`, nf);
	await page.screenshot({ path: `${EVIDENCE}/tc012-parent-famb-invoice.png`, fullPage: true });
	expect(nf).not.toContain("INV-000149");
	expect(nf).not.toContain("SCN Student B1");
	expect((await api(page, `sessions/${SB1X}/`)).status).toBe(404);
	expect(errors).toEqual([]);
});
