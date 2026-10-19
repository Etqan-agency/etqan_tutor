// QA campaign F02 UI smoke (qa/specs/F02-sign-in.md TC-001, TC-011, TC-015). Test-only.
// Academy `qa`; the people's UI language is Arabic, so labels match both ar and en.
import { createHmac } from "node:crypto";
import { mkdirSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { expect, type Page, test } from "@playwright/test";

const EVIDENCE = fileURLToPath(
	new URL("../../../qa/evidence/F02/pw", import.meta.url),
);
mkdirSync(EVIDENCE, { recursive: true });
const save = (name: string, data: unknown) =>
	writeFileSync(`${EVIDENCE}/${name}`, JSON.stringify(data, null, 2));

const QA = "http://qa.etqan.localhost";
const API = `${QA}/api/v1`;
const ADMIN = { email: "qa-admin@qa.etqan.test", password: "QA-Admin-2026!" };
const TEACHER = { email: "qa-teacher@qa.etqan.test", password: "QA-People-2026!" };
const STUDENT_ID = 10; // f02-c, "F02 Student c"

const L = {
	email: /email|البريد/i,
	password: /^(password|كلمة المرور)$/i,
	signIn: /^(sign in|تسجيل الدخول)$/i,
	account: /account menu|قائمة الحساب/i,
	signOut: /sign out|تسجيل الخروج/i,
	setUp: /^(set up|إعداد)$/i,
	code: /^(code|الرمز)/i,
	confirm: /^(confirm|تأكيد)$/i,
	saved: /i saved them|لقد حفظتها/i,
	verify: /^(verify|تحقق)$/i,
	signInAs: /sign in as|الدخول بحساب هذا الشخص/i,
	ret: /return to my account|العودة إلى حسابي/i,
};

function totp(secret: string, at = Date.now()): string {
	const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
	let bits = "";
	for (const c of secret.replace(/=+$/, "").toUpperCase())
		bits += alphabet.indexOf(c).toString(2).padStart(5, "0");
	const key = Buffer.from(
		bits.match(/.{8}/g)?.map((b) => Number.parseInt(b, 2)) ?? [],
	);
	const msg = Buffer.alloc(8);
	msg.writeBigUInt64BE(BigInt(Math.floor(at / 30_000)));
	const h = createHmac("sha1", key).update(msg).digest();
	const o = h[h.length - 1] & 15;
	return String((h.readUInt32BE(o) & 0x7fffffff) % 1_000_000).padStart(6, "0");
}
const nextWindow = () =>
	new Promise((r) => setTimeout(r, 30_000 - (Date.now() % 30_000) + 1_000));

async function uiLogin(page: Page, who: { email: string; password: string }) {
	await page.goto(`${QA}/app/login`);
	await page.getByRole("textbox", { name: L.email }).fill(who.email);
	await page.getByRole("textbox", { name: L.password }).fill(who.password);
	await page.getByRole("button", { name: L.signIn }).click();
}

async function signOut(page: Page) {
	await page.getByRole("button", { name: L.account }).click();
	await page.getByRole("menuitem", { name: L.signOut }).click();
	await expect(page).toHaveURL(/\/app\/login/);
}

test("TC-001 admin signs in, signs out, Back shows no data", async ({ page }) => {
	await uiLogin(page, ADMIN);
	await expect(page).not.toHaveURL(/\/app\/login/);
	const me1 = await page.request.get(`${API}/identity/me/`);
	expect(me1.status()).toBe(200);
	const cookies = await page.context().cookies(QA);
	const sid = cookies.find((c) => c.name === "sessionid");
	const csrf = cookies.find((c) => c.name === "csrftoken");
	await signOut(page);
	const me2 = await page.request.get(`${API}/identity/me/`);
	await page.goBack();
	await page.waitForTimeout(1500);
	const afterBack = page.url();
	const bodyText = await page.locator("body").innerText();
	save("tc001-ui.json", {
		meAfterLogin: me1.status(),
		sessionHttpOnly: sid?.httpOnly,
		csrfHttpOnly: csrf?.httpOnly,
		meAfterLogout: me2.status(),
		urlAfterBack: afterBack,
		adminNameVisibleAfterBack: bodyText.includes("QA Admin"),
	});
	expect(sid?.httpOnly).toBe(true);
	expect(csrf?.httpOnly).toBe(false);
	expect(me2.status()).toBe(403);
	expect(afterBack).toMatch(/\/app\/login/);
	expect(bodyText).not.toContain("QA Admin");
});

test("TC-011 teacher turns on 2FA in Account and signs in with a code", async ({
	page,
}) => {
	test.setTimeout(150_000);
	await uiLogin(page, TEACHER);
	await expect(page).not.toHaveURL(/\/app\/login/);
	await page.goto(`${QA}/app/account`);
	const [setup] = await Promise.all([
		page.waitForResponse((r) => r.url().endsWith("/identity/me/2fa/setup/")),
		page.getByRole("button", { name: L.setUp }).click(),
	]);
	const { secret } = await setup.json();
	await expect(page.getByText(secret)).toBeVisible();
	await page.getByRole("textbox", { name: L.code }).fill(totp(secret));
	const [confirm] = await Promise.all([
		page.waitForResponse((r) => r.url().endsWith("/identity/me/2fa/confirm/")),
		page.getByRole("button", { name: L.confirm }).click(),
	]);
	expect(confirm.status()).toBe(200);
	await page.getByRole("button", { name: L.saved }).click();
	await signOut(page);
	await uiLogin(page, TEACHER);
	await expect(page.getByRole("button", { name: L.verify })).toBeVisible();
	const half = await page.request.get(`${API}/identity/me/`);
	await nextWindow(); // the confirm spent this window's code
	await page.getByRole("textbox", { name: L.code }).fill(totp(secret));
	const [step2] = await Promise.all([
		page.waitForResponse((r) => r.url().endsWith("/identity/login/2fa/")),
		page.getByRole("button", { name: L.verify }).click(),
	]);
	await expect(page).not.toHaveURL(/\/app\/login/);
	const me = await page.request.get(`${API}/identity/me/`);
	// Cleanup: turn 2FA off again through the API with a fresh code.
	await nextWindow();
	const token =
		(await page.context().cookies(QA)).find((c) => c.name === "csrftoken")
			?.value ?? "";
	const off = await page.request.post(`${API}/identity/me/2fa/disable/`, {
		data: { code: totp(secret) },
		headers: { "X-CSRFToken": token, Referer: `${QA}/app/` },
	});
	save("tc011-ui.json", {
		confirm: confirm.status(),
		meWhileHalfOpen: half.status(),
		step2: step2.status(),
		meAfter: me.status(),
		cleanupDisable: off.status(),
	});
	expect(half.status()).toBe(403);
	expect(step2.status()).toBe(200);
	expect(me.status()).toBe(200);
	expect(off.status()).toBe(204);
});

test("TC-015 admin signs in as a student, sees the banner, and returns", async ({
	page,
}) => {
	await uiLogin(page, ADMIN);
	await expect(page).not.toHaveURL(/\/app\/login/);
	await page.goto(`${QA}/app/people/students/${STUDENT_ID}`);
	const [start] = await Promise.all([
		page.waitForResponse((r) => r.url().includes("/quick-login/")),
		page.getByRole("button", { name: L.signInAs }).click(),
	]);
	const banner = page.getByText(/F02 Student c/).filter({ hasText: /QA Admin/ });
	await expect(banner.first()).toBeVisible();
	const meAs = await (await page.request.get(`${API}/identity/me/`)).json();
	const [stop] = await Promise.all([
		page.waitForResponse((r) => r.url().endsWith("/impersonation/stop/")),
		page.getByRole("button", { name: L.ret }).click(),
	]);
	await expect(page.getByRole("button", { name: L.ret })).toHaveCount(0);
	const meBack = await (await page.request.get(`${API}/identity/me/`)).json();
	save("tc015-ui.json", {
		start: start.status(),
		meAs: { id: meAs.id, role: meAs.role, impersonator: meAs.impersonator },
		stop: stop.status(),
		meBack: { id: meBack.id, role: meBack.role, impersonator: meBack.impersonator },
		urlAfter: page.url(),
	});
	expect(start.status()).toBe(200);
	expect(meAs.id).toBe(STUDENT_ID);
	expect(meAs.impersonator?.id).toBe(1);
	expect(stop.status()).toBe(200);
	expect(meBack.id).toBe(1);
	expect(meBack.impersonator).toBeNull();
});
