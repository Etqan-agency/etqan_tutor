// QA F01: the first admin of the admin-created academy `qa` accepts the
// set-password email and signs in (TC-014, 016-018, 105, 110, 141, 142).
// Runs after f01-onboarding.spec.ts created `qa`; TC-110 must run while the
// qaother admin's invite is still unaccepted.
import { expect, test } from "@playwright/test";
import { academyUrl, INVITE } from "../fixtures";
import { latestLink } from "../mail";
import { api, EVIDENCE, QA, QAOTHER, save, watchConsole } from "./f01-helpers";

test.describe.configure({ mode: "serial" });

const QA_URL = academyUrl(QA.sub);
const QAOTHER_URL = academyUrl(QAOTHER.sub);
let invite = "";
const getInvite = async () => invite || (invite = await latestLink(QA.adminEmail, INVITE));

test("TC-014 the invite reaches Mailpit with the qa host", async () => {
	invite = await latestLink(QA.adminEmail, INVITE);
	save("tc014-invite-link.txt", invite);
	expect(new URL(invite).origin).toBe(QA_URL);
});

test("TC-110 qa's invite token is refused on qaother (pending admin, same pk)", async ({
	playwright,
}) => {
	const request = await playwright.request.newContext();
	await request.get(`${QAOTHER_URL}/api/v1/identity/csrf/`);
	const url = new URL(await getInvite());
	const res = await api(request, QAOTHER_URL, "POST", "identity/password/reset/confirm/", {
		uid: url.searchParams.get("uid"),
		token: url.searchParams.get("token"),
		new_password: "QA-Hijack-2026!x",
	});
	save("tc110-cross-tenant-token.json", res);
	expect(res.status).toBe(400);
	await request.dispose();
});

test("TC-016/017/141 the first admin sets a password and signs in", async ({
	browser,
}) => {
	const context = await browser.newContext();
	const page = await context.newPage();
	const errors = watchConsole(page);
	await page.goto(invite);
	const dir = await page.locator("html").getAttribute("dir");
	const lang = await page.locator("html").getAttribute("lang");
	// A weak password first: the error must be announced (TC-141).
	await page.getByLabel(/^new password/i).fill("123");
	let weakRequests = 0;
	page.on("request", (r) => { if (r.url().includes("password/reset/confirm/")) weakRequests++; });
	await page.getByRole("button", { name: "Reset password" }).click();
	await expect(page.getByRole("alert")).toBeVisible();
	const weak = { status: () => `client-side only, requests sent: ${weakRequests}` };
	const alerts = await page.locator('[role="alert"], [aria-live]').allInnerTexts();
	await page.screenshot({ path: `${EVIDENCE}/tc141-weak-password.png` });
	await page.getByLabel(/^new password/i).fill(QA.password);
	const [confirm] = await Promise.all([
		page.waitForResponse((r) => r.url().includes("password/reset/confirm/") && r.request().method() === "POST"),
		page.getByRole("button", { name: "Reset password" }).click(),
	]);
	await expect(page.getByText(/you can now sign in/i)).toBeVisible();
	save("tc016-confirm.json", { dir, lang, weakStatus: weak?.status() ?? null, alerts, status: confirm.status(), errors });
	expect(confirm.status()).toBe(200);

	await page.goto(`${QA_URL}/app/login`);
	await expect(page.locator("body")).toContainText(QA.name);
	const brand = await page.locator("body").innerText();
	await page.getByRole("textbox", { name: /email/i }).fill(QA.adminEmail);
	await page.getByRole("textbox", { name: /password/i }).fill(QA.password);
	await page.getByRole("button", { name: /sign in/i }).click();
	await expect(page.getByRole("heading", { level: 1, name: new RegExp(QA.adminName) })).toBeVisible();
	const me = await api(page.request, QA_URL, "GET", "identity/me/");
	const cookies = await context.cookies();
	await page.screenshot({ path: `${EVIDENCE}/tc017-dashboard.png`, fullPage: true });
	save("tc017-me.json", { me, cookies, loginPageHasBrand: brand.includes(QA.name), errors });
	expect(me.status).toBe(200);
	expect((me.body as { email: string }).email).toBe(QA.adminEmail);
	expect(brand).toContain(QA.name);
	await context.close();
});

test("TC-018 the invite link is single-use and a wrong token is refused", async ({
	playwright,
}) => {
	const request = await playwright.request.newContext();
	await request.get(`${QA_URL}/api/v1/identity/csrf/`);
	const url = new URL(await getInvite());
	const uid = url.searchParams.get("uid") ?? "";
	const token = url.searchParams.get("token") ?? "";
	const again = await api(request, QA_URL, "POST", "identity/password/reset/confirm/", { uid, token, new_password: "QA-Again-2026!x" });
	const flipped = token.slice(0, -1) + (token.endsWith("a") ? "b" : "a");
	const wrong = await api(request, QA_URL, "POST", "identity/password/reset/confirm/", { uid, token: flipped, new_password: "QA-Again-2026!x" });
	save("tc018-reuse.json", { again, wrong });
	expect(again.status).toBe(400);
	expect(wrong.status).toBe(400);
	await request.dispose();
});

test("TC-105/142 the qa admin cannot sign in on qaother; logins are branded", async ({
	page,
}) => {
	await page.goto(`${QAOTHER_URL}/app/login`);
	await expect(page.locator("body")).toContainText(QAOTHER.name);
	await page.getByRole("textbox", { name: /email/i }).fill(QA.adminEmail);
	await page.getByRole("textbox", { name: /password/i }).fill(QA.password);
	const [resp] = await Promise.all([
		page.waitForResponse((r) => r.url().includes("identity/login/") && r.request().method() === "POST"),
		page.getByRole("button", { name: /sign in/i }).click(),
	]);
	await expect(page.getByRole("alert")).toBeVisible();
	await expect(page).toHaveURL(/\/app\/login/);
	const alert = await page.getByRole("alert").innerText();
	await page.screenshot({ path: `${EVIDENCE}/tc105-qaother-refused.png` });
	save("tc105-login-qaother.json", { status: resp.status(), body: await resp.text(), alert });
	expect(resp.status()).toBe(400);
});
