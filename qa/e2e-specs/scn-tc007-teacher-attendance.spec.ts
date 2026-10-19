// QA campaign SCN (Agent 2): integrated scenario C, UI smoke 1 (SCN-TC-007). Test-only.
// Data from qa/evidence/SCN/scripts (SUB1 for "SCN Student A1", U1 = regular session today 10:00 Cairo).
import { mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { expect, type Page, test } from "@playwright/test";

const EVIDENCE = fileURLToPath(new URL("../../../qa/evidence/SCN/pw", import.meta.url));
mkdirSync(EVIDENCE, { recursive: true });
const QA = "http://qa.etqan.localhost";
const U1 = Number(process.env.SCN_U1);
const SUB1 = Number(process.env.SCN_SUB1);

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
		return { status: r.status, body: await r.json() };
	}, path);

test("SCN-TC-007 teacher marks U1 present in Teaching > Sessions; session completes and the package is consumed", async ({
	page,
}) => {
	expect(U1).toBeGreaterThan(0);
	const errors: string[] = [];
	page.on("response", (r) => r.status() >= 500 && errors.push(`${r.status()} ${r.url()}`));
	await login(page, "qa-teacher@qa.etqan.test", "QA-People-2026!");
	const before = await api(page, `sessions/${U1}/`);
	expect(before.body.status).toBe("scheduled");
	const subBefore = await api(page, `subscriptions/${SUB1}/`);
	await page.goto(`${QA}/app/teaching/sessions`);
	await expect(page.getByRole("tab", { name: /today/i })).toHaveAttribute("aria-selected", "true");
	const rows = page.getByRole("row").filter({ hasText: "SCN Student A1" }).filter({ has: page.getByRole("cell", { name: "Oct 19, 2026 10:00" }) });
	await expect(rows).toHaveCount(1);
	const picker = rows.getByLabel("Student attendance for SCN Student A1");
	await expect(picker).toBeEnabled();
	const marked = page.waitForResponse(
		(r) => r.url().includes(`/sessions/${U1}/attendance/`) && r.request().method() === "POST",
	);
	await picker.selectOption("present");
	expect((await marked).status()).toBe(200);
	await expect(picker).toHaveValue("present");
	await page.screenshot({ path: `${EVIDENCE}/tc007-teacher-present.png`, fullPage: true });
	const after = await api(page, `sessions/${U1}/`);
	expect(after.body.status).toBe("completed");
	expect(after.body.student_attendance).toBe("present");
	const subAfter = await api(page, `subscriptions/${SUB1}/`);
	expect(subAfter.body.sessions_remaining).toBe(subBefore.body.sessions_remaining - 1);
	expect(errors).toEqual([]);
});
