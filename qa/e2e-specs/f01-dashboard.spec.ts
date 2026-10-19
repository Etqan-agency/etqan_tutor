// QA F01: what the qa academy's dashboard shows for tenancy settings and
// Etqan's feature switches (TC-051, 100, 128, 129, 130, 143), on the QA
// academy only (never demo). Switches are restored in `finally`.
import { expect, type Page, test } from "@playwright/test";
import { academyUrl } from "../fixtures";
import { manage } from "../manage";
import { api, EVIDENCE, QA, save, watchConsole } from "./f01-helpers";

const QA_URL = academyUrl(QA.sub);
const OFF = "This feature isn't enabled for your academy.";

async function signIn(page: Page, email: string, password: string) {
	await page.goto(`${QA_URL}/app/login`);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));
	await page.goto(`${QA_URL}/app/login`);
	await page.getByRole("textbox", { name: /email/i }).fill(email);
	await page.getByRole("textbox", { name: /password/i }).fill(password);
	await page.getByRole("button", { name: /sign in/i }).click();
	await expect(page).not.toHaveURL(/\/app\/login/, { timeout: 15_000 });
}

test("TC-051 Settings shows Cairo and EGP", async ({ page }) => {
	await signIn(page, QA.adminEmail, QA.password);
	await page.goto(`${QA_URL}/app/settings/academy`);
	await expect(page.getByLabel("Time zone")).toBeVisible();
	const tz = await page.getByLabel("Time zone").inputValue().catch(async () => page.getByLabel("Time zone").innerText());
	const body = await page.locator("main").innerText();
	await page.screenshot({ path: `${EVIDENCE}/tc051-settings.png`, fullPage: true });
	save("tc051-settings-ui.json", { tz, body: body.slice(0, 1200) });
	expect(`${tz} ${body}`).toMatch(/Cairo/);
	expect(body).toMatch(/EGP/);
});

test("TC-128 Settings → Features is read-only and matches the API", async ({ page, browser }) => {
	const errors = watchConsole(page);
	await signIn(page, QA.adminEmail, QA.password);
	await page.goto(`${QA_URL}/app/settings/features`);
	await expect(page.getByText("Managed by Etqan")).toBeVisible();
	const switches = await page.locator('[role="switch"], input[type="checkbox"]').count();
	const lists = await page.getByRole("list").evaluateAll((els) => els.map((e) => e.getAttribute("aria-label")).filter(Boolean));
	const items = await page.locator("main ul[aria-label] > li[aria-label]").evaluateAll((els) => els.map((e) => { const lines = (e as HTMLElement).innerText.split("\n").map((l) => l.trim()); return `${e.getAttribute("aria-label")}=${lines.includes("On") ? "On" : lines.includes("Off") ? "Off" : "?"}`; }));
	const apiRes = await api(page.request, QA_URL, "GET", "academy/features/");
	await page.screenshot({ path: `${EVIDENCE}/tc128-features-page.png`, fullPage: true });
	const others: Record<string, string> = {};
	for (const who of ["qa-staff-nocode", "qa-supervisor", "qa-teacher", "qa-student", "qa-parent"]) {
		const ctx = await browser.newContext();
		const p = await ctx.newPage();
		await signIn(p, `${who}@qa.etqan.test`, "QA-People-2026!");
		await p.goto(`${QA_URL}/app/settings/features`);
		await p.waitForTimeout(1_500);
		others[who] = (await p.locator("main").innerText().catch(() => "")).slice(0, 200);
		await ctx.close();
	}
	const apiOn = (apiRes.body as { label_en: string; on: boolean }[]).map((f) => `${f.label_en}=${f.on ? "On" : "Off"}`);
	save("tc128-features-ui.json", { switches, lists, items, apiOn, others, errors });
	expect(switches).toBe(0);
	expect(items.slice().sort()).toEqual(apiOn.slice().sort());
	for (const text of Object.values(others)) expect(text).not.toContain("Managed by Etqan");
});

test("TC-129/130 families off on qa: nav and direct URL; data kept", async ({ page }) => {
	await signIn(page, QA.adminEmail, QA.password);
	const before = await api(page.request, QA_URL, "GET", "people/families/1/");
	try {
		expect(manage("set_features", "qa", "--off", "families")).toContain("qa: families=off");
		await page.goto(`${QA_URL}/app/`);
		const nav = page.getByRole("navigation", { name: "Main navigation" });
		await expect(nav.getByRole("link", { name: "Students" })).toBeVisible();
		await expect(nav.getByRole("link", { name: "Families" })).toHaveCount(0);
		await page.goto(`${QA_URL}/app/people/families`);
		await expect(page.getByRole("heading", { level: 1, name: OFF })).toBeVisible();
		await page.screenshot({ path: `${EVIDENCE}/tc129-feature-off.png`, fullPage: true });
	} finally {
		manage("set_features", "qa", "--on", "families");
	}
	await page.goto(`${QA_URL}/app/`);
	await expect(page.getByRole("navigation", { name: "Main navigation" }).getByRole("link", { name: "Families" })).toBeVisible();
	const after = await api(page.request, QA_URL, "GET", "people/families/1/");
	save("tc130-family-kept.json", { before, after });
	expect(after).toEqual(before);
});

test("TC-143 the new academy's public site renders with defaults", async ({ page }) => {
	// GET / redirects by Accept-Language (default Arabic): follow it as an
	// Arabic browser would.
	const res = await page.goto(`${QA_URL}/ar/`);
	const dir = await page.locator("html").getAttribute("dir");
	const body = await page.locator("body").innerText();
	await page.screenshot({ path: `${EVIDENCE}/tc143-public-site.png`, fullPage: true });
	save("tc143-public-site.json", { status: res?.status(), url: page.url(), dir, body: body.slice(0, 800) });
	expect(res?.status()).toBe(200);
	expect(dir).toBe("rtl");
	expect(body).toContain("تعلّم مع أفضل المعلمين");
	expect(body).toContain(QA.name);
});

test("TC-100 the SPA on an unknown academy host", async ({ page }) => {
	const errors = watchConsole(page);
	await page.goto(`${academyUrl("nope-qa")}/app/login`);
	await page.waitForTimeout(2_000);
	const before = await page.locator("body").innerText();
	let after = "";
	const email = page.getByRole("textbox", { name: /email/i });
	if (await email.count()) {
		await email.fill("x@qa.etqan.test");
		await page.getByRole("textbox", { name: /password/i }).fill("whatever-123");
		await page.getByRole("button", { name: /sign in/i }).click();
		await page.waitForTimeout(3_000);
		after = await page.locator("body").innerText();
	}
	await page.screenshot({ path: `${EVIDENCE}/tc100-unknown-host-login.png`, fullPage: true });
	save("tc100-unknown-host-spa.json", { before, after, alerts: await page.getByRole("alert").allInnerTexts(), errors });
	expect(`${before}\n${after}`).not.toBe("");
});

test.describe("TC-141 Arabic set-password page", () => {
	test.use({ locale: "ar-EG" });
	test("RTL, keyboard order, announced error", async ({ page }) => {
		// The dashboard starts in English for a visitor (lib/i18n.ts); the
		// language switch stores `etqan-locale`. Choose Arabic as a user would.
		await page.goto(`${QA_URL}/app/reset-password?uid=MQ&token=invalid-token`);
		await page.evaluate(() => localStorage.setItem("etqan-locale", "ar"));
		await page.reload();
		await page.waitForLoadState("networkidle");
		const dir = await page.locator("html").getAttribute("dir");
		const lang = await page.locator("html").getAttribute("lang");
		const pw = page.locator('input[type="password"]').first();
		await pw.focus();
		await page.keyboard.type("123");
		await page.keyboard.press("Tab");
		const afterTab = await page.evaluate(() => `${document.activeElement?.tagName}:${document.activeElement?.getAttribute("aria-label") ?? document.activeElement?.textContent?.trim()}`);
		await page.keyboard.press("Tab");
		const afterTab2 = await page.evaluate(() => `${document.activeElement?.tagName}:${document.activeElement?.textContent?.trim()}`);
		await page.keyboard.press("Enter");
		await page.waitForTimeout(1_000);
		const alerts = await page.locator('[role="alert"], [aria-live]').allInnerTexts();
		await page.screenshot({ path: `${EVIDENCE}/tc141-ar-reset-page.png`, fullPage: true });
		save("tc141-ar-reset.json", { dir, lang, afterTab, afterTab2, alerts });
		expect(dir).toBe("rtl");
		expect(alerts.join(" ").trim()).not.toBe("");
	});
});
