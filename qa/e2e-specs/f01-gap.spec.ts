// QA campaign F01 gap review (qa/specs/F01-tenancy-provisioning.md, TC-159, TC-169).
// Test-only, gitignored-by-convention scratch spec for the QA campaign; not product code.
import { expect, type Page, test } from "@playwright/test";
import { BASE_URL } from "../fixtures";
import { QA, STAFF, save, staffLogin, watchConsole } from "./f01-helpers";

const QA_URL = `http://${QA.sub}.etqan.localhost`;
const API = `${QA_URL}/api/v1/`;
const SUPERVISOR = { email: "qa-supervisor@qa.etqan.test", password: "QA-People-2026!" };

async function cookie(page: Page, name: string) {
	const all = await page.context().cookies(QA_URL);
	return all.find((c) => c.name === name)?.value ?? "";
}

async function uiLogin(page: Page, who: { email: string; password: string }) {
	await page.getByRole("textbox", { name: /email|البريد/i }).fill(who.email);
	await page.getByRole("textbox", { name: /password|كلمة المرور/i }).fill(who.password);
	const [resp] = await Promise.all([
		page.waitForResponse((r) => r.url() === `${API}identity/login/` && r.request().method() === "POST"),
		page.getByRole("button", { name: /^(sign in|تسجيل الدخول)$/i }).click(),
	]);
	return {
		status: resp.status(),
		sentToken: (await resp.request().headerValue("x-csrftoken")) ?? "",
	};
}

/** A write the way the SPA's axios client makes it: X-CSRFToken read from the cookie at request time. */
async function spaStyleWrite(page: Page) {
	return page.evaluate(async () => {
		const tok = document.cookie.split("; ").find((c) => c.startsWith("csrftoken="))?.split("=")[1] ?? "";
		const me = await (await fetch("/api/v1/identity/me/", { credentials: "same-origin" })).json();
		const r = await fetch("/api/v1/identity/me/", {
			method: "PATCH",
			credentials: "same-origin",
			headers: { "Content-Type": "application/json", "X-CSRFToken": tok },
			body: JSON.stringify({ preferred_language: me.preferred_language }),
		});
		return { status: r.status, body: (await r.text()).slice(0, 120), tokenLen: tok.length };
	});
}

test("TC-159 CSRF token after sign-in, sign-out and a second sign-in in the same SPA page", async ({ page, context }) => {
	test.setTimeout(3 * 60_000);
	const errors = watchConsole(page);
	const out: Record<string, unknown> = {};
	await page.goto(`${QA_URL}/app/login`);
	const before = await cookie(page, "csrftoken");
	const QA_ADMIN = { email: QA.adminEmail, password: QA.password };
	const l1 = await uiLogin(page, QA_ADMIN);
	await expect(page).not.toHaveURL(/\/app\/login/);
	const after1 = await cookie(page, "csrftoken");
	out.step1 = { login: l1.status, sentHeader: l1.sentToken.length > 0, sentMatchesPreLoginCookie: l1.sentToken === before, rotated: before !== after1 };

	// Step 1: create a tag through the SPA without reloading.
	// A client-side route change (no reload): pushState + popstate, which the router follows.
	await page.evaluate(() => {
		(window as unknown as { __qa159: number }).__qa159 = 1;
		window.history.pushState({}, "", "/app/settings/tags");
		window.dispatchEvent(new PopStateEvent("popstate"));
	});
	await page.getByRole("button", { name: /add tag|إضافة وسم/i }).first().click();
	await page.getByLabel(/emoji|الرمز التعبيري/i).fill("🧪");
	await page.getByLabel(/arabic name|الاسم بالعربية/i).fill("وسم QA159");
	await page.getByLabel(/english name|الاسم بالإنجليزية/i).fill("QA159 tag");
	const [tagResp] = await Promise.all([
		page.waitForResponse((r) => r.url().startsWith(`${API}people/tags/`) && r.request().method() === "POST"),
		page.getByRole("button", { name: /save tag|حفظ الوسم/i }).click(),
	]);
	const tagHeader = (await tagResp.request().headerValue("x-csrftoken")) ?? "";
	out.noReload = await page.evaluate(() => (window as unknown as { __qa159?: number }).__qa159 === 1);
	out.tagCreate = { status: tagResp.status(), headerMatchesCookie: tagHeader === (await cookie(page, "csrftoken")), body: (await tagResp.text()).slice(0, 120) };

	// Step 2: sign out through the user menu, sign in as the supervisor in the same page.
	await page.getByRole("button", { name: /account|الحساب|حساب/i }).first().click();
	const [logoutResp] = await Promise.all([
		page.waitForResponse((r) => r.url() === `${API}identity/logout/` && r.request().method() === "POST"),
		page.getByRole("menuitem", { name: /sign out|تسجيل الخروج/i }).click(),
	]);
	await expect(page).toHaveURL(/\/app\/login/);
	const l2 = await uiLogin(page, SUPERVISOR);
	await expect(page).not.toHaveURL(/\/app\/login/);
	const w2 = await spaStyleWrite(page);
	out.step2 = { logout: logoutResp.status(), login: l2.status, sentHeader: l2.sentToken.length > 0, write: w2 };

	// Step 3: two tabs. Tab A on the login page, tab B signs in, then tab A signs in.
	await context.clearCookies();
	const tabA = page;
	const tabB = await context.newPage();
	await tabA.goto(`${QA_URL}/app/login`);
	await tabB.goto(`${QA_URL}/app/login`);
	const lB = await uiLogin(tabB, QA_ADMIN);
	const lA = await uiLogin(tabA, SUPERVISOR);
	await expect(tabA).not.toHaveURL(/\/app\/login/);
	const wA = await spaStyleWrite(tabA);
	out.step3 = { tabBLogin: lB.status, tabALogin: lA.status, tabAWrite: wA };
	out.csrfFailedSeen = errors.filter((e) => /CSRF/i.test(e));
	out.consoleErrors = errors;
	save("tc159-csrf-rotation.json", out);
	expect(l1.status).toBe(200);
	expect(tagResp.status()).toBe(201);
	expect(l2.status).toBe(200);
	expect(w2.status).toBe(200);
	expect(lB.status).toBe(200);
	expect(lA.status).toBe(200);
	expect(wA.status).toBe(200);
});

test("TC-169 Add-academy POST abandoned by the browser mid-provision", async ({ browser }) => {
	test.setTimeout(6 * 60_000);
	const ctx = await browser.newContext();
	const page = await ctx.newPage();
	await staffLogin(page, STAFF);
	await page.goto(`${BASE_URL}/admin/tenants/academy/add/`);
	const values: Record<string, string> = {
		name: "QA Tmp Abort",
		subdomain: "qa-tmp-abort",
		timezone: "UTC",
		currency: "USD",
		admin_email: "qa-tmp-abort-admin@qa.etqan.test",
		admin_full_name: "QA Abort Admin",
	};
	for (const [f, v] of Object.entries(values)) await page.locator(`[name="${f}"]`).fill(v);
	const started = Date.now();
	page.locator('[name="_save"]').click().catch(() => undefined);
	await page.waitForTimeout(3000);
	await page.close(); // abandon the request about 3 s in
	await ctx.close();
	const closedAt = Date.now() - started;
	await new Promise((r) => setTimeout(r, 30_000));

	// Resubmit the same form in a new browser context.
	const ctx2 = await browser.newContext();
	const p2 = await ctx2.newPage();
	await staffLogin(p2, STAFF);
	await p2.goto(`${BASE_URL}/admin/tenants/academy/add/`);
	for (const [f, v] of Object.entries(values)) await p2.locator(`[name="${f}"]`).fill(v);
	const [resp] = await Promise.all([
		p2.waitForResponse((r) => r.url().includes("/academy/add/") && r.request().method() === "POST", { timeout: 5 * 60_000 }),
		p2.locator('[name="_save"]').click(),
	]);
	await p2.waitForLoadState("domcontentloaded");
	const errorsText = await p2.locator(".errorlist").allInnerTexts();
	save("tc169-abort.json", { closedAtMs: closedAt, resubmitStatus: resp.status(), errors: errorsText, url: p2.url() });
	await ctx2.close();
	expect(errorsText.join(" ")).toMatch(/already taken/i);
});
