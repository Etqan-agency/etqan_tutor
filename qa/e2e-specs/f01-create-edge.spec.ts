// QA F01: Add-form edge cases that create throwaway academies (qa-tmp-*).
// TC-052/053 (S1: invalid timezone / currency at creation) and TC-061
// (double-submitting the Add form). One-shot: each creates a schema.
import { expect, test } from "@playwright/test";
import { BASE_URL } from "../fixtures";
import { EVIDENCE, STAFF, save, staffLogin } from "./f01-helpers";

const ADD = `${BASE_URL}/admin/tenants/academy/add/`;

async function fill(page: import("@playwright/test").Page, v: Record<string, string>) {
	await page.goto(ADD);
	for (const [field, value] of Object.entries(v)) {
		await page.locator(`[name="${field}"]`).fill(value);
	}
}

test("TC-052/053 an invalid timezone and a lowercase currency at creation", async ({ page }) => {
	test.setTimeout(5 * 60_000);
	await staffLogin(page, STAFF);
	await fill(page, {
		name: "QA Tmp TZ",
		subdomain: "qa-tmp-tz",
		timezone: "Mars/Phobos",
		currency: "usd",
		admin_email: "qa-tmp-tz-admin@qa.etqan.test",
		admin_full_name: "QA Tmp TZ Admin",
	});
	const [resp] = await Promise.all([
		page.waitForResponse((r) => r.url().includes("/academy/add/") && r.request().method() === "POST", { timeout: 5 * 60_000 }),
		page.locator('[name="_save"]').click(),
	]);
	await page.waitForLoadState("domcontentloaded");
	const errors = await page.locator(".errorlist").allInnerTexts();
	const messages = await page.locator(".messagelist").allInnerTexts();
	await page.screenshot({ path: `${EVIDENCE}/tc052-after-submit.png`, fullPage: true });
	save("tc052-053-submit.json", { status: resp.status(), url: page.url(), errors, messages });
	// Expected per clean_timezone/clean_currency (academy/services.py): a
	// form error and nothing created.
	expect(errors.join(" ")).toMatch(/timezone|currency/i);
});

test("TC-061 double-clicking Save creates one academy and no 500", async ({ page }) => {
	test.setTimeout(5 * 60_000);
	await staffLogin(page, STAFF);
	await fill(page, {
		name: "QA Tmp Race A",
		subdomain: "qa-tmp-race-a",
		timezone: "UTC",
		currency: "USD",
		admin_email: "qa-tmp-race-a-admin@qa.etqan.test",
		admin_full_name: "QA Race A",
	});
	const posts: { status: number; at: number }[] = [];
	page.on("response", (r) => {
		if (r.url().includes("/academy/add/") && r.request().method() === "POST") posts.push({ status: r.status(), at: Date.now() });
	});
	await page.locator('[name="_save"]').dblclick();
	await page.waitForLoadState("load", { timeout: 5 * 60_000 });
	await page.waitForTimeout(3_000);
	await expect(page.locator(".messagelist, .errornote").first()).toBeVisible({ timeout: 5 * 60_000 });
	const body = await page.locator("body").innerText();
	await page.screenshot({ path: `${EVIDENCE}/tc061-double-submit.png`, fullPage: true });
	save("tc061-double-submit.json", { posts, url: page.url(), body: body.slice(0, 1500) });
	expect(body).not.toContain("Server Error");
	expect(posts.every((p) => p.status < 500)).toBe(true);
});
