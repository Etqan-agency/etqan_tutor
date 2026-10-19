// QA campaign F06 retest 1 (Agent 2): ETQAN-QA-041 mitigation (timezone-change warning) on the live stack. Test-only.
import { mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { expect, type Page, test } from "@playwright/test";

const EVIDENCE = fileURLToPath(new URL("../../../qa/evidence/F06/retest-1", import.meta.url));
mkdirSync(EVIDENCE, { recursive: true });
const QA = "http://qa.etqan.localhost";

async function login(page: Page) {
	await page.goto(`${QA}/app/login`);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));
	await page.reload();
	await page.getByRole("textbox", { name: /email/i }).fill("qa-admin@qa.etqan.test");
	await page.getByRole("textbox", { name: /^password$/i }).fill("QA-Admin-2026!");
	await page.getByRole("button", { name: /^sign in$/i }).click();
	await page.waitForURL((u) => !u.pathname.includes("/login"));
}

test("QA-041 settings form warns that existing lessons keep their time", async ({ page }) => {
	const errors: string[] = [];
	page.on("response", (r) => r.status() >= 500 && errors.push(`${r.status()} ${r.url()}`));
	await login(page);
	await page.goto(`${QA}/app/settings/academy`);
	const tz = page.getByLabel("Time zone");
	await expect(tz).toHaveValue("Africa/Cairo");
	await expect(page.getByText(/keep their current time/)).toHaveCount(0);
	await tz.selectOption("Asia/Riyadh");
	await expect(page.getByRole("status").filter({ hasText: /keep their current time/ })).toBeVisible();
	await page.screenshot({ path: `${EVIDENCE}/qa041-warning.png`, fullPage: true });
	await tz.selectOption("Africa/Cairo");
	await expect(page.getByText(/keep their current time/)).toHaveCount(0);
	// nothing saved
	const saved = await page.evaluate(async () => (await fetch("/api/v1/academy/settings/")).json());
	expect(saved.timezone).toBe("Africa/Cairo");
	expect(errors).toEqual([]);
});
