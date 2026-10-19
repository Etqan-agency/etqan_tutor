// QA F01: the real customer-onboarding entry point. Etqan staff add an
// academy in the Django admin; its first admin gets the set-password email,
// sets a password and signs in. Cases TC-010, 011, 014, 016-022, 025, 105,
// 110, 140, 142 of qa/specs/F01-tenancy-provisioning.md. Creates the kept QA
// academy `qa` (run once; a second run sees "already taken" and fails at the
// happy path on purpose).
import { expect, type Page, test } from "@playwright/test";
import { academyUrl, BASE_URL, INVITE } from "../fixtures";
import { latestLink } from "../mail";
import {
	api,
	EVIDENCE,
	expectNoServerError,
	QA,
	QAOTHER,
	STAFF,
	save,
	staffLogin,
	watchConsole,
} from "./f01-helpers";

test.describe.configure({ mode: "serial" });

const QA_URL = academyUrl(QA.sub);
const QAOTHER_URL = academyUrl(QAOTHER.sub);
const ADD = `${BASE_URL}/admin/tenants/academy/add/`;
const SUBDOMAIN_RULE =
	"Use 1-32 lowercase letters, digits or hyphens; it cannot start or end with a hyphen.";

async function fillAdd(
	page: Page,
	values: Partial<Record<string, string>> = {},
) {
	const v = {
		name: "QA Form Probe",
		subdomain: "qa-tmp-probe",
		timezone: "Africa/Cairo",
		currency: "EGP",
		plan_label: "QA Tier 1",
		plan_notes: "",
		admin_email: "qa-tmp-probe-admin@qa.etqan.test",
		admin_full_name: "QA Probe",
		...values,
	};
	await page.goto(ADD);
	for (const [field, value] of Object.entries(v)) {
		await page.locator(`[name="${field}"]`).fill(value ?? "");
	}
	return v;
}

async function fieldErrors(page: Page, field: string): Promise<string> {
	const row = page.locator(`.field-${field}`);
	return (await row.locator(".errorlist").allInnerTexts()).join(" | ");
}

let invite = "";

test("TC-010 Etqan staff sign in to the console on the base domain", async ({
	page,
}) => {
	const errors = watchConsole(page);
	await page.goto(`${BASE_URL}/admin/login/`);
	await page.locator("#id_username").fill(STAFF.email);
	await page.locator("#id_password").fill(STAFF.password);
	const [response] = await Promise.all([
		page.waitForResponse(
			(r) => r.url().includes("/admin/login/") && r.request().method() === "POST",
		),
		page.getByRole("button", { name: /log in/i }).click(),
	]);
	const setCookie = (await response.headersArray())
		.filter((h) => h.name.toLowerCase() === "set-cookie")
		.map((h) => h.value);
	await expect(page.locator("#site-name")).toHaveText("Etqan — academies");
	await expect(page.getByRole("link", { name: "Academies", exact: true })).toBeVisible();
	await expect(page.getByRole("link", { name: "Domains", exact: true })).toBeVisible();
	const cookies = await page.context().cookies();
	const session = cookies.find((c) => c.name === "sessionid");
	save("tc010-login.json", { status: response.status(), setCookie, cookies, errors });
	expect(session?.domain).toBe("etqan.localhost");
	expect(setCookie.join("\n")).not.toMatch(/Domain=/i);
	await page.screenshot({ path: `${EVIDENCE}/tc010-admin-index.png` });
});

test("TC-011/019-022/140 the Add-academy form: fields and every error path", async ({
	page,
}) => {
	test.setTimeout(5 * 60_000);
	await staffLogin(page, STAFF);
	await page.goto(ADD);
	const names = await page
		.locator("#academy_form [name]")
		.evaluateAll((els) =>
			els
				.map((e) => e.getAttribute("name") ?? "")
				.filter((n) => !["csrfmiddlewaretoken", "_save", "_addanother", "_continue"].includes(n)),
		);
	const help = await page.locator(".field-admin_email .help, .field-admin_email div.help").allInnerTexts();
	const timezoneTag = await page.locator('[name="timezone"]').evaluate((e) => `${e.tagName}:${e.getAttribute("type")}`);
	save("tc011-add-form-fields.json", { names, help, timezoneTag });
	expect(names.sort()).toEqual(
		["admin_email", "admin_full_name", "currency", "name", "plan_label", "plan_notes", "subdomain", "timezone"].sort(),
	);
	expect(names.some((n) => n.startsWith("feature_") || n.startsWith("domains-"))).toBe(false);
	await page.screenshot({ path: `${EVIDENCE}/tc011-add-form.png`, fullPage: true });

	const cases: { group: string; field: string; input: Record<string, string>; expect: RegExp }[] = [];
	const bad = ["QA2", "-qa2", "qa2-", "q_a", "q.a", "qa a", "قا", "a".repeat(33), "qа", "ｑａ"];
	for (const s of bad) cases.push({ group: "TC-019", field: "subdomain", input: { subdomain: s }, expect: new RegExp(`${SUBDOMAIN_RULE.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}|valid “slug”`) });
	for (const s of ["", "   "]) cases.push({ group: "TC-019", field: "subdomain", input: { subdomain: s }, expect: /required|Use 1-32/ });
	for (const s of ["www", "admin", "api", "app", "public", "static", "media", "mail", "flower", "sites", "etqan"]) cases.push({ group: "TC-020", field: "subdomain", input: { subdomain: s }, expect: /This subdomain is reserved\./ });
	cases.push({ group: "TC-021", field: "subdomain", input: { subdomain: "demo" }, expect: /This subdomain is already taken\./ });
	cases.push({ group: "TC-021", field: "subdomain", input: { subdomain: "qaother" }, expect: /This subdomain is already taken\./ });
	for (const e of ["", "not-an-email", "a@b"]) cases.push({ group: "TC-022", field: "admin_email", input: { admin_email: e }, expect: /required|valid email/i });
	cases.push({ group: "TC-023", field: "name", input: { name: "" }, expect: /required/i });
	cases.push({ group: "TC-023", field: "name", input: { name: "N".repeat(201) }, expect: /at most|characters/i });

	const results = [];
	for (const c of cases) {
		const filled = await fillAdd(page, c.input);
		// Bypass the browser's own maxlength/required/type=email checks so the
		// server-side validation is what is tested.
		await page.locator("#academy_form").evaluate((f) => f.setAttribute("novalidate", ""));
		await page.locator('[name="name"]').evaluate((e, v) => { (e as HTMLInputElement).removeAttribute("maxlength"); (e as HTMLInputElement).value = v; }, filled.name);
		const [resp] = await Promise.all([
			page.waitForResponse((r) => r.url().includes("/academy/add/") && r.request().method() === "POST"),
			page.locator('[name="_save"]').click(),
		]);
		await page.waitForLoadState("domcontentloaded");
		await page.locator(".errornote").waitFor({ timeout: 10_000 }).catch(() => {});
		const errornote = await page.locator(".errornote").allInnerTexts();
		const err = await fieldErrors(page, c.field);
		const kept = await page.locator(`[name="${c.field}"]`).inputValue();
		const r = { ...c, expect: String(c.expect), errornote, status: resp.status(), url: page.url(), error: err, kept, keptOk: kept === (filled as Record<string, string>)[c.field] || c.field === "subdomain" };
		results.push(r);
		expect.soft(resp.status(), JSON.stringify(c.input)).toBe(200);
		expect.soft(err, JSON.stringify(c.input)).toMatch(c.expect);
		expect.soft(page.url(), JSON.stringify(c.input)).toContain("/academy/add/");
	}
	save("tc019-022-form-errors.json", results);
});

test("TC-011 add 'Etqan QA Academy' (qa) through the Add form", async ({
	page,
}) => {
	test.setTimeout(6 * 60_000);
	const errors = watchConsole(page);
	await staffLogin(page, STAFF);
	await fillAdd(page, {
		name: QA.name,
		subdomain: QA.sub,
		timezone: "Africa/Cairo",
		currency: "EGP",
		plan_label: "QA Tier 1",
		plan_notes: "QA campaign F01 kept academy",
		admin_email: QA.adminEmail,
		admin_full_name: QA.adminName,
	});
	const started = Date.now();
	const [resp] = await Promise.all([
		page.waitForResponse(
			(r) => r.url().includes("/academy/add/") && r.request().method() === "POST",
			{ timeout: 5 * 60_000 },
		),
		page.locator('[name="_save"]').click(),
	]);
	const postMs = Date.now() - started;
	await expectNoServerError(page);
	const success = page.locator(".messagelist .success");
	await expect(success).toContainText(`The academy “${QA.name}” was added successfully`);
	await expect(page).toHaveURL(/\/admin\/tenants\/academy\/$/);
	const row = page.locator("#result_list tr", { hasText: QA.name });
	await expect(row).toContainText(/active/i);
	await expect(row).toContainText("EGP");
	await page.screenshot({ path: `${EVIDENCE}/tc011-added.png`, fullPage: true });
	save("tc011-add.json", { status: resp.status(), postMs, startedAt: new Date(started).toISOString(), message: await success.innerText(), row: await row.innerText(), errors });

	// TC-011 UI: the change page shows the domain inline and the features.
	await row.getByRole("link", { name: QA.name }).click();
	await expect(page.locator("body")).toContainText("qa.etqan.localhost");
	const fieldsets = await page.locator("fieldset h2").allInnerTexts();
	const readonly = await page.locator(".field-subdomain .readonly, .field-schema_name .readonly, .field-created_at .readonly").allInnerTexts();
	const subdomainInput = await page.locator('[name="subdomain"]').count();
	save("tc011-change-page.json", { fieldsets, readonly, subdomainInput, url: page.url() });
	expect(fieldsets.filter((t) => t.startsWith("Features:"))).toEqual([
		"Features: People", "Features: Teaching", "Features: Money",
		"Features: Communication", "Features: Content", "Features: Platform",
	]);
	expect(subdomainInput).toBe(0);
	await page.screenshot({ path: `${EVIDENCE}/tc011-change-page.png`, fullPage: true });
});
