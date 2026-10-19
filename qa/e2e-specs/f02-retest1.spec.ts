// QA campaign F02 retest 1 (ETQAN-QA-018 UI): a weak new password is refused in Account with the
// server's field error, and the password stays unchanged. Test-only; academy `qa`, f02-a (student 8).
import { expect, test } from "@playwright/test";

const QA = "http://qa.etqan.localhost";
const WHO = { email: "f02-a@qa.etqan.test", password: "F02-Pass-2026!" };

test("QA-018 UI: Account change-password shows the validator error for 12345678", async ({
	page,
}) => {
	await page.goto(`${QA}/app/login`);
	await page.getByRole("textbox", { name: /email|البريد/i }).fill(WHO.email);
	await page
		.getByRole("textbox", { name: /^(password|كلمة المرور)$/i })
		.fill(WHO.password);
	await page.getByRole("button", { name: /^(sign in|تسجيل الدخول)$/i }).click();
	await expect(page).not.toHaveURL(/\/app\/login/);
	await page.goto(`${QA}/app/account`);
	await page.getByLabel(/current password|كلمة المرور الحالية/i).fill(WHO.password);
	await page.getByLabel(/new password|كلمة مرور جديدة/i).fill("12345678");
	const [resp] = await Promise.all([
		page.waitForResponse((r) => r.url().endsWith("/identity/me/password/")),
		page.getByRole("button", { name: /update password|تحديث كلمة المرور/i }).click(),
	]);
	expect(resp.status()).toBe(400);
	const body = await resp.json();
	const msg: string = body.new_password[0];
	await expect(page.getByText(msg)).toBeVisible();
	await page.screenshot({
		path: "../qa/evidence/F02/retest-1/qa018-ui.png",
		fullPage: true,
	});
	// The old password still signs in (API, fresh context).
	const ctx = await page.context().browser()?.newContext();
	const api = ctx?.request;
	const csrf = await api?.get(`${QA}/api/v1/identity/csrf/`);
	const token = csrf ? "" : "";
	const cookies = (await ctx?.cookies()) ?? [];
	const ck = cookies.find((c) => c.name === "csrftoken")?.value ?? token;
	const login = await api?.post(`${QA}/api/v1/identity/login/`, {
		data: WHO,
		headers: { "X-CSRFToken": ck, Referer: `${QA}/app/` },
	});
	expect(login?.status()).toBe(200);
	await ctx?.close();
});
