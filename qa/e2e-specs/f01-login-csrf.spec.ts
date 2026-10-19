// ETQAN-QA-006 (found by F01 TC-114): signing in is CSRF-checked (ADR-0003).
// A fresh browser still signs in through the dashboard, and a form on another
// page cannot sign the browser into an account. Test-only (QA campaign).
import { expect, test } from "@playwright/test";
import { QAOTHER, save, watchConsole } from "./f01-helpers";

const QAOTHER_URL = `http://${QAOTHER.sub}.etqan.localhost`;
const LOGIN_API = `${QAOTHER_URL}/api/v1/identity/login/`;

test("QA-006 a fresh browser signs in through the dashboard", async ({
	page,
}) => {
	const errors = watchConsole(page);
	await page.goto(`${QAOTHER_URL}/app/login`);
	await page.getByRole("textbox", { name: /email/i }).fill(QAOTHER.adminEmail);
	await page.getByRole("textbox", { name: /password/i }).fill(QAOTHER.password);
	const [resp] = await Promise.all([
		page.waitForResponse(
			(r) => r.url() === LOGIN_API && r.request().method() === "POST",
		),
		page.getByRole("button", { name: /sign in/i }).click(),
	]);
	const sentToken = (await resp.request().headerValue("x-csrftoken")) ?? "";
	await expect(page).not.toHaveURL(/\/app\/login/);
	const me = await page.request.get(`${QAOTHER_URL}/api/v1/identity/me/`);
	save("qa006-ui-login.json", {
		loginStatus: resp.status(),
		sentCsrfHeader: sentToken.length > 0,
		meStatus: me.status(),
		url: page.url(),
		errors,
	});
	expect(resp.status()).toBe(200);
	expect(sentToken.length).toBeGreaterThan(0);
	expect(me.status()).toBe(200);
});

test("QA-006 a form on another page cannot sign the browser in", async ({
	page,
}) => {
	// The attacker's page: a plain form that posts the attacker's credentials.
	await page.setContent(`
		<form method="post" action="${LOGIN_API}">
			<input name="email" value="${QAOTHER.adminEmail}">
			<input name="password" value="${QAOTHER.password}">
			<button>go</button>
		</form>`);
	const [resp] = await Promise.all([
		page.waitForResponse((r) => r.url() === LOGIN_API),
		page.getByRole("button", { name: "go" }).click(),
	]);
	const body = await resp.text();
	const cookies = await page.context().cookies(QAOTHER_URL);
	const me = await page.request.get(`${QAOTHER_URL}/api/v1/identity/me/`);
	save("qa006-cross-site-form.json", {
		status: resp.status(),
		body,
		sessionCookie: cookies.some((c) => c.name === "sessionid"),
		meStatus: me.status(),
	});
	expect(resp.status()).toBe(403);
	expect(body).toContain("CSRF Failed");
	expect(cookies.some((c) => c.name === "sessionid")).toBe(false);
	expect([401, 403]).toContain(me.status());
});
