// QA campaign F08 (Agent 2): sessions & attendance UI smoke on the live stack. Test-only.
// Data is prepared by qa/evidence/F08/scripts/ui0.sh (Sub C for "QA Student Two", session U1 started 10 min ago).
import { mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { expect, type Page, test } from "@playwright/test";

const EVIDENCE = fileURLToPath(new URL("../../../qa/evidence/F08/pw", import.meta.url));
mkdirSync(EVIDENCE, { recursive: true });
const QA = "http://qa.etqan.localhost";
const U1 = Number(process.env.F08_U1);
const SUBC = Number(process.env.F08_SUBC);

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

test.describe.configure({ mode: "serial" });

test("TC-001 teacher marks the student present: session completes, package consumed", async ({ page }) => {
	expect(U1).toBeGreaterThan(0);
	const errors: string[] = [];
	page.on("response", (r) => r.status() >= 500 && errors.push(`${r.status()} ${r.url()}`));
	await login(page, "qa-teacher@qa.etqan.test", "QA-People-2026!");
	const before = await api(page, `sessions/${U1}/`);
	expect(before.body.status).toBe("scheduled");
	await page.goto(`${QA}/app/teaching/sessions`);
	await expect(page.getByRole("tab", { name: /today/i })).toHaveAttribute("aria-selected", "true");
	const row = page.getByRole("row").filter({ hasText: "QA Student Two" });
	await expect(row).toHaveCount(1);
	const picker = row.getByLabel("Student attendance for QA Student Two");
	await expect(picker).toBeEnabled();
	const marked = page.waitForResponse((r) => r.url().includes(`/sessions/${U1}/attendance/`) && r.request().method() === "POST");
	await picker.selectOption("present");
	expect((await marked).status()).toBe(200);
	await expect(picker).toHaveValue("present");
	await page.screenshot({ path: `${EVIDENCE}/tc001-teacher-present.png`, fullPage: true });
	const after = await api(page, `sessions/${U1}/`);
	expect(after.body.status).toBe("completed");
	expect(after.body.student_attendance).toBe("present");
	// The "not set" option is disabled for a teacher (office-only undo).
	await expect(picker.locator('option[value="not_set"]')).toBeDisabled();
	expect(errors).toEqual([]);
});

test("TC-001/TC-020 admin sees the completed session and its activity entry by the teacher", async ({ page }) => {
	await login(page, "qa-admin@qa.etqan.test", "QA-Admin-2026!");
	const sub = await api(page, `subscriptions/${SUBC}/`);
	expect(sub.body.sessions_used).toBe(1);
	expect(sub.body.sessions_remaining).toBe(7);
	await page.goto(`${QA}/app/scheduling/sessions/${U1}`);
	await expect(page.getByRole("heading", { name: "Activity" })).toBeVisible();
	await expect(page.getByText(/QA teacher ·/).first()).toBeVisible();
	await page.screenshot({ path: `${EVIDENCE}/tc020-admin-session-activity.png`, fullPage: true });
});

test("TC-011 student sees own sessions read-only (no attendance controls, no activity)", async ({ page }) => {
	await login(page, "qa-student@qa.etqan.test", "QA-People-2026!");
	const own = await api(page, "sessions/?page_size=1");
	expect(own.status).toBe(200);
	const foreign = await api(page, `sessions/${U1}/`);
	expect(foreign.status).toBe(404);
	await page.goto(`${QA}/app/`);
	await expect(page.getByLabel(/^Student attendance for/)).toHaveCount(0);
	await page.screenshot({ path: `${EVIDENCE}/tc011-student-home.png`, fullPage: true });
});
