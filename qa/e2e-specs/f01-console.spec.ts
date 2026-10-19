// QA F01: the Etqan console (Django admin) on throwaway academy qa-tmp-1 and
// on qaother/qa read-only. Each test is one case and is run on its own with
// --grep, in the order the runbook in qa/specs/F01 Results gives, because
// API/DB checks run between them. Never targets demo or other.
import { expect, type Page, test } from "@playwright/test";
import { academyUrl, BASE_URL } from "../fixtures";
import {
	EVIDENCE,
	STAFF,
	STAFF_NOPERM,
	STAFF_VIEW,
	save,
	staffLogin,
	watchConsole,
} from "./f01-helpers";

const ACADEMIES = `${BASE_URL}/admin/tenants/academy/`;
const DOMAINS = `${BASE_URL}/admin/tenants/domain/`;
const shot = (page: Page, name: string) =>
	page.screenshot({ path: `${EVIDENCE}/${name}.png`, fullPage: true });

async function idOf(page: Page, list: string, text: string): Promise<string> {
	await page.goto(`${list}?q=${encodeURIComponent(text)}`);
	const href = await page
		.locator("#result_list tbody tr th a, #result_list tbody tr td a")
		.filter({ hasText: new RegExp(`^${text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}$`) })
		.first()
		.getAttribute("href");
	return (href ?? "").match(/\/(\d+)\/change\//)?.[1] ?? "";
}

async function runAction(
	page: Page,
	list: string,
	ids: string[],
	action: string,
	extra?: (page: Page) => Promise<void>,
) {
	await page.goto(list);
	for (const id of ids) {
		await page.locator(`input[name="_selected_action"][value="${id}"]`).check();
	}
	await page.locator('select[name="action"]').selectOption(action);
	if (extra) await extra(page);
	await page.locator('button[name="index"]').click();
	await page.waitForLoadState("domcontentloaded");
	return (await page.locator(".messagelist li").allInnerTexts()).join(" | ");
}

/** Submit a changelist action with a forged id list (no checkbox needed). */
async function forgeAction(page: Page, list: string, ids: string[], action: string) {
	await page.goto(list);
	const csrf = await page.locator('input[name="csrfmiddlewaretoken"]').first().inputValue();
	const form = new URLSearchParams({ csrfmiddlewaretoken: csrf, action, index: "0" });
	for (const id of ids) form.append("_selected_action", id);
	const res = await page.request.post(list, {
		headers: { "Content-Type": "application/x-www-form-urlencoded", Referer: list },
		data: form.toString(),
	});
	return { status: res.status(), body: (await res.text()).match(/<ul class="messagelist">[\s\S]*?<\/ul>/)?.[0] ?? "" };
}

test("TC-064 suspend qa-tmp-1 with the admin action", async ({ page }) => {
	await staffLogin(page, STAFF);
	const id = await idOf(page, ACADEMIES, "QA Tmp One");
	const message = await runAction(page, ACADEMIES, [id], "suspend_academies");
	const row = await page.locator("#result_list tr", { hasText: "qa-tmp-1" }).innerText();
	await shot(page, "tc064-suspended");
	save("tc064-suspend.json", { id, message, row });
	expect(message).toContain("Suspended 1 academies.");
	expect(row).toMatch(/Suspended/);
});

test("TC-071 the suspended academy's dashboard login", async ({ page }) => {
	const errors = watchConsole(page);
	await page.goto(`${academyUrl("qa-tmp-1")}/app/login`);
	await page.waitForTimeout(2_000);
	const before = await page.locator("body").innerText();
	await shot(page, "tc071-suspended-login-page");
	let after = "";
	let alerts: string[] = [];
	const email = page.getByRole("textbox", { name: /email/i });
	if (await email.count()) {
		await email.fill("qa-admin@qa.etqan.test");
		await page.getByRole("textbox", { name: /password/i }).fill("QA-Tmp1-2026!");
		await page.getByRole("button", { name: /sign in/i }).click();
		await page.waitForTimeout(2_000);
		after = await page.locator("body").innerText();
		alerts = await page.getByRole("alert").allInnerTexts();
		await shot(page, "tc071-suspended-after-submit");
	}
	save("tc071-suspended-ui.json", { before, after, alerts, errors, url: page.url() });
	// Documented intent (tenancy.md): the academy is suspended; the user
	// should be told so (S5).
	expect(`${before} ${after} ${alerts.join(" ")}`).toMatch(/suspend|موقوف|معلق/i);
});

test("TC-072 reactivate qa-tmp-1", async ({ page }) => {
	await staffLogin(page, STAFF);
	const id = await idOf(page, ACADEMIES, "QA Tmp One");
	const message = await runAction(page, ACADEMIES, [id], "reactivate_academies");
	const row = await page.locator("#result_list tr", { hasText: "qa-tmp-1" }).innerText();
	save("tc072-reactivate.json", { id, message, row });
	expect(message).toContain("Reactivated 1 academies.");
	expect(row).toMatch(/Active/);
});

test("TC-074 suspend through the change form's status field", async ({ page }) => {
	await staffLogin(page, STAFF);
	const id = await idOf(page, ACADEMIES, "QA Tmp One");
	await page.goto(`${ACADEMIES}${id}/change/`);
	await page.locator('select[name="status"]').selectOption("suspended");
	await page.locator('[name="_save"]').click();
	await page.locator(".messagelist li").first().waitFor();
	const message = (await page.locator(".messagelist li").allInnerTexts()).join(" | ");
	save("tc074-change-form-suspend.json", { id, message });
	expect(message).toMatch(/was changed successfully/);
});

test("TC-074b reactivate through the change form", async ({ page }) => {
	await staffLogin(page, STAFF);
	const id = await idOf(page, ACADEMIES, "QA Tmp One");
	await page.goto(`${ACADEMIES}${id}/change/`);
	await page.locator('select[name="status"]').selectOption("active");
	await page.locator('[name="_save"]').click();
	await expect(page.locator(".messagelist li").first()).toContainText("was changed successfully");
});

test("TC-073/075/127/137 public rows hidden, no deletes, forged actions", async ({ page }) => {
	await staffLogin(page, STAFF);
	await page.goto(ACADEMIES);
	const names = await page.locator("#result_list tbody tr th, #result_list tbody tr td.field-name").allInnerTexts();
	const actions = await page.locator('select[name="action"] option').allInnerTexts();
	const copyFrom = await page.locator('select[name="copy_from"] option').allInnerTexts();
	const publicChange = await page.goto(`${ACADEMIES}1/change/`);
	const publicChangeUrl = page.url();
	const publicChangeText = (await page.locator(".messagelist, #content").first().innerText()).slice(0, 300);
	const forged = await forgeAction(page, ACADEMIES, ["1"], "suspend_academies");
	const id = await idOf(page, ACADEMIES, "QA Tmp One");
	const del = await page.request.get(`${ACADEMIES}${id}/delete/`);
	await page.goto(`${ACADEMIES}${id}/change/`);
	const deleteLink = await page.locator("a.deletelink").count();
	await page.goto(DOMAINS);
	const domainRows = await page.locator("#result_list tbody tr").allInnerTexts();
	const domainActions = await page.locator('select[name="action"] option').allInnerTexts();
	const domainId = await idOf(page, DOMAINS, "qa-tmp-1.etqan.localhost");
	const domainDel = await page.request.get(`${DOMAINS}${domainId}/delete/`);
	const pubDomain = await page.request.get(`${DOMAINS}1/change/`, { maxRedirects: 0 });
	const result = {
		names, actions, copyFrom, publicChange: publicChange?.status(), publicChangeUrl, publicChangeText,
		forged, academyDelete: del.status(), deleteLink, domainRows, domainActions, domainDelete: domainDel.status(),
		publicDomainChange: { status: pubDomain.status(), location: pubDomain.headers().location ?? "" },
	};
	save("tc073-075-127-137.json", result);
	expect(names.join(" ")).not.toMatch(/^Etqan$/m);
	expect(names).not.toContain("Etqan");
	expect(copyFrom).not.toContain("Etqan");
	expect(actions.join(" ")).not.toMatch(/delete/i);
	expect(forged.body).toContain("Suspended 0 academies.");
	expect(del.status()).toBe(403);
	expect(deleteLink).toBe(0);
	expect(domainRows.map((r) => r.trim().split("\t")[0])).not.toEqual(expect.arrayContaining(["etqan.localhost"]));
	expect(domainRows.map((r) => r.trim().split("\t")[0]).filter((d) => ["etqan.localhost", "localhost", "127.0.0.1"].includes(d))).toEqual([]);
	expect(domainDel.status()).toBe(403);
});

test("TC-133 a view-only Etqan staff member can't change anything", async ({ page }) => {
	await staffLogin(page, STAFF_VIEW);
	await page.goto(ACADEMIES);
	const actions = await page.locator('select[name="action"] option').allInnerTexts();
	const addLink = await page.locator("a.addlink").count();
	const id = await idOf(page, ACADEMIES, "Etqan QA Academy");
	await page.goto(`${ACADEMIES}${id}/change/`);
	const saveButtons = await page.locator('[name="_save"]').count();
	const checkboxes = await page.locator('input[type="checkbox"][name^="feature_"]').count();
	await shot(page, "tc133-view-only-change-page");
	const csrf = await page.evaluate(() => document.cookie.match(/csrftoken=([^;]+)/)?.[1] ?? "");
	const forged = await page.request.post(`${ACADEMIES}${id}/change/`, {
		headers: { "Content-Type": "application/x-www-form-urlencoded", Referer: `${ACADEMIES}${id}/change/` },
		data: new URLSearchParams({ csrfmiddlewaretoken: csrf, name: "Hacked", status: "suspended", timezone: "UTC", currency: "USD", feature_chat: "on", _save: "Save" }).toString(),
	});
	const add = await page.request.get(`${ACADEMIES}add/`);
	const forgedAction = await page.request.post(ACADEMIES, {
		headers: { "Content-Type": "application/x-www-form-urlencoded", Referer: ACADEMIES },
		data: new URLSearchParams({ csrfmiddlewaretoken: csrf, action: "suspend_academies", index: "0", _selected_action: id }).toString(),
	});
	const domainAdd = await page.request.get(`${DOMAINS}add/`);
	const result = { actions, addLink, saveButtons, checkboxes, forgedChange: forged.status(), add: add.status(), forgedAction: forgedAction.status(), forgedActionMsg: (await forgedAction.text()).match(/<ul class="messagelist">[\s\S]*?<\/ul>/)?.[0] ?? "", domainAdd: domainAdd.status() };
	save("tc133-view-only.json", result);
	expect(saveButtons).toBe(0);
	expect(addLink).toBe(0);
	expect(forged.status()).toBe(403);
	expect(add.status()).toBe(403);
	expect(domainAdd.status()).toBe(403);
	expect(actions.filter((a) => !a.startsWith("-"))).toEqual([]);
});

test("TC-134 is_staff with no permissions sees nothing", async ({ page }) => {
	await staffLogin(page, STAFF_NOPERM);
	const index = await page.locator("#content").innerText();
	const urls = [ACADEMIES, `${ACADEMIES}add/`, `${ACADEMIES}5/change/`, DOMAINS, `${DOMAINS}add/`];
	const statuses: Record<string, number> = {};
	for (const u of urls) statuses[u] = (await page.request.get(u)).status();
	save("tc134-noperm.json", { index, statuses });
	expect(index).toMatch(/don.t have permission/i);
	for (const s of Object.values(statuses)) expect(s).toBe(403);
});

test("TC-135 anonymous admin URLs redirect to the login", async ({ request }) => {
	const res = await request.get(ACADEMIES, { maxRedirects: 0 });
	save("tc135-anon.json", { status: res.status(), location: res.headers().location });
	expect(res.status()).toBe(302);
	expect(res.headers().location).toMatch(/\/admin\/login\/\?next=/);
});

async function addDomain(page: Page, tenant: string, domain: string) {
	await page.goto(`${DOMAINS}add/`);
	await page.locator('select[name="tenant"]').selectOption({ label: tenant });
	await page.locator('[name="domain"]').fill(domain);
	await page.locator('[name="domain"]').evaluate((e) => e.removeAttribute("maxlength"));
	const [resp] = await Promise.all([
		page.waitForResponse((r) => r.url().includes("/domain/add/") && r.request().method() === "POST"),
		page.locator('[name="_save"]').click(),
	]);
	await page.waitForLoadState("domcontentloaded");
	const body = await page.locator("body").innerText();
	return {
		tenant, domain, status: resp.status(), url: page.url(),
		errors: (await page.locator(".errorlist").allInnerTexts()).join(" | "),
		messages: (await page.locator(".messagelist li").allInnerTexts()).join(" | "),
		serverError: /Server Error|Traceback|ValidationError at/.test(body) ? body.slice(0, 300) : "",
	};
}

test("TC-082/083/084/085 add custom domains: normalised, refused, invalid, duplicate", async ({ page }) => {
	test.setTimeout(3 * 60_000);
	await staffLogin(page, STAFF);
	await page.goto(`${DOMAINS}add/`);
	const help = await page.locator(".field-domain .help, .field-domain div.help").allInnerTexts();
	const tenants = await page.locator('select[name="tenant"] option').allInnerTexts();
	const fields = await page.locator("#domain_form [name]").evaluateAll((els) => els.map((e) => e.getAttribute("name")));
	const results = [];
	results.push({ tc: "TC-082", ...(await addDomain(page, "QA Tmp One", "QA-Academy.TEST.")) });
	for (const d of ["etqan.localhost", "x.etqan.localhost", "qa.etqan.localhost"]) results.push({ tc: "TC-083", ...(await addDomain(page, "QA Tmp One", d)) });
	for (const d of ["bad_host", "nodot", "-x.com", "a..com", "http://x.com", `${"a".repeat(63)}.${"b".repeat(63)}.${"c".repeat(63)}.${"d".repeat(58)}.com`]) results.push({ tc: "TC-084", ...(await addDomain(page, "QA Tmp One", d)) });
	results.push({ tc: "TC-085", ...(await addDomain(page, "QA Tmp One", "qa-academy.test")) });
	results.push({ tc: "TC-085", ...(await addDomain(page, "Etqan QA Academy", "qa-academy.test")) });
	results.push({ tc: "TC-085", ...(await addDomain(page, "QA Tmp One", "localhost")) });
	results.push({ tc: "TC-087", ...(await addDomain(page, "QA Tmp One", "localtest.me")) });
	save("tc082-085-domain-add.json", { help, tenants, fields, results });
	expect(tenants).not.toContain("Etqan");
	expect(help.join(" ")).toContain("sites.etqan.localhost");
	for (const r of results) expect.soft(r.status, `${r.tc} ${r.domain}`).toBeLessThan(500);
});

test("TC-087/092 check DNS on pending domains; make primary refused", async ({ page }) => {
	await staffLogin(page, STAFF);
	const a = await idOf(page, DOMAINS, "qa-academy.test");
	const b = await idOf(page, DOMAINS, "localtest.me");
	const dns = await runAction(page, DOMAINS, [a, b], "check_dns");
	const primary = await runAction(page, DOMAINS, [a], "make_primary_action");
	save("tc087-092.json", { ids: [a, b], dns, primary });
	await shot(page, "tc087-092-messages");
	expect(dns).toContain("qa-academy.test");
	expect(dns).toContain("sites.etqan.localhost");
	expect(primary).toContain("Only an active domain can be primary.");
});

test("TC-091 make the active custom domain primary", async ({ page }) => {
	await staffLogin(page, STAFF);
	const a = await idOf(page, DOMAINS, "qa-academy.test");
	const msg = await runAction(page, DOMAINS, [a], "make_primary_action");
	save("tc091-make-primary.json", { id: a, msg });
	expect(msg).not.toMatch(/Only an active/);
});

test("TC-093/094 disable the primary custom domain; the subdomain can't be disabled", async ({ page }) => {
	await staffLogin(page, STAFF);
	const a = await idOf(page, DOMAINS, "qa-academy.test");
	const sub = await idOf(page, DOMAINS, "qa-tmp-1.etqan.localhost");
	const disable = await runAction(page, DOMAINS, [a], "disable_action");
	const disableSub = await runAction(page, DOMAINS, [sub], "disable_action");
	const recheck = await runAction(page, DOMAINS, [a, sub], "check_dns");
	save("tc093-094-095.json", { ids: [a, sub], disable, disableSub, recheck });
	expect(disableSub).toContain("The academy's own subdomain cannot be disabled.");
});

test("TC-133b a view-only staff member runs Copy features and Suspend from the UI", async ({ page }) => {
	await staffLogin(page, STAFF_VIEW);
	const id = await idOf(page, ACADEMIES, "QA Tmp One");
	await page.goto(ACADEMIES);
	const checkbox = page.locator(`input[name="_selected_action"][value="${id}"]`);
	const offered = await checkbox.count();
	const copy = await runAction(page, ACADEMIES, [id], "copy_features", async (p) => {
		await p.locator('select[name="copy_from"]').selectOption({ label: "Etqan QA Other" });
	});
	const suspend = await runAction(page, ACADEMIES, [id], "suspend_academies");
	await shot(page, "tc133b-view-only-suspended");
	const reactivate = await runAction(page, ACADEMIES, [id], "reactivate_academies");
	save("tc133b-view-only-actions.json", { id, offered, copy, suspend, reactivate });
	expect(suspend, "a view-only staff member must not suspend").not.toContain("Suspended 1");
	expect(copy, "a view-only staff member must not copy features").not.toContain("Copied");
});
