// QA F01: the academy change page in the Etqan console: feature fieldsets
// (TC-125), Copy features (TC-126), Etqan-defaults suspension (TC-076/077/
// 080), timezone edit (TC-055) and a forged subdomain change (TC-025).
// Each test runs on its own with --grep; DB checks run between them.
import { expect, type Page, test } from "@playwright/test";
import { BASE_URL } from "../fixtures";
import { EVIDENCE, STAFF, save, staffLogin } from "./f01-helpers";

const ACADEMIES = `${BASE_URL}/admin/tenants/academy/`;
const IDS = { qaother: "4", qa: "5", tmp1: "6" };
const change = (id: string) => `${ACADEMIES}${id}/change/`;

async function saveForm(page: Page) {
	await page.locator('[name="_save"]').click();
	await page.waitForLoadState("domcontentloaded");
	await page.locator(".messagelist li, .errornote").first().waitFor();
	return {
		messages: (await page.locator(".messagelist li").allInnerTexts()).join(" | "),
		errors: (await page.locator(".errorlist").allInnerTexts()).join(" | "),
		errornote: (await page.locator(".errornote").allInnerTexts()).join(" | "),
	};
}

test("TC-125 feature fieldsets on qaother; tick only Chat", async ({ page }) => {
	await staffLogin(page, STAFF);
	await page.goto(change(IDS.qaother));
	const fieldsets = await page.locator("fieldset").evaluateAll((els) =>
		els.map((f) => ({
			title: f.querySelector("h2")?.textContent?.trim() ?? "",
			description: f.querySelector(".description")?.textContent?.trim() ?? "",
			boxes: f.querySelectorAll('input[type="checkbox"][name^="feature_"]').length,
		})),
	);
	const chatLabel = await page.locator('label[for="id_feature_internal_chat"]').innerText();
	const unbuilt = await page.locator(".field-feature_free_sessions").innerText();
	await page.screenshot({ path: `${EVIDENCE}/tc125-change-page.png`, fullPage: true });
	await page.locator('[name="feature_internal_chat"]').check();
	const result = await saveForm(page);
	save("tc125-fieldsets.json", { fieldsets, chatLabel, unbuilt, result });
	expect(fieldsets.filter((f) => f.title.startsWith("Features:")).map((f) => f.title)).toEqual([
		"Features: People", "Features: Teaching", "Features: Money",
		"Features: Communication", "Features: Content", "Features: Platform",
	]);
	expect(fieldsets.find((f) => f.title === "Features: People")?.description).toContain("Only Etqan switches these");
	expect(fieldsets.reduce((n, f) => n + f.boxes, 0)).toBe(88);
	expect(unbuilt).toContain("Takes effect when built.");
	expect(result.messages).toContain("was changed successfully");
});

test("TC-125b untick Chat on qaother", async ({ page }) => {
	await staffLogin(page, STAFF);
	await page.goto(change(IDS.qaother));
	await page.locator('[name="feature_internal_chat"]').uncheck();
	const result = await saveForm(page);
	save("tc125b-untick.json", result);
	expect(result.messages).toContain("was changed successfully");
});

test("TC-126 copy features from qa to qa-tmp-1", async ({ page }) => {
	await staffLogin(page, STAFF);
	const run = async (ids: string[], source?: string) => {
		await page.goto(ACADEMIES);
		for (const id of ids) await page.locator(`input[name="_selected_action"][value="${id}"]`).check();
		await page.locator('select[name="action"]').selectOption("copy_features");
		if (source) await page.locator('select[name="copy_from"]').selectOption({ label: source });
		await page.locator('button[name="index"]').click();
		await page.waitForLoadState("domcontentloaded");
		return (await page.locator(".messagelist li").allInnerTexts()).join(" | ");
	};
	const copied = await run([IDS.tmp1], "Etqan QA Academy");
	const noSource = await run([IDS.tmp1]);
	const self = await run([IDS.qa], "Etqan QA Academy");
	save("tc126-copy.json", { copied, noSource, self });
	expect(copied).toContain("Copied the features of Etqan QA Academy to 1 academies.");
	expect(noSource).toContain("Choose the academy to copy the features from.");
	expect(self).toContain("to 0 academies.");
});

async function defaultsForm(page: Page, on: boolean) {
	await staffLogin(page, STAFF);
	await page.goto(change(IDS.tmp1));
	const help = await page.locator(".field-etqan_defaults_suspended").innerText();
	const box = page.locator('[name="etqan_defaults_suspended"]');
	if (on) await box.check();
	else await box.uncheck();
	return { help, ...(await saveForm(page)) };
}

test("TC-076 suspending Etqan's defaults with no unpaid invoice is refused", async ({ page }) => {
	const r = await defaultsForm(page, true);
	save("tc076-defaults-refused.json", r);
	expect(r.help).toContain("No unpaid Etqan invoice.");
	expect(r.errors).toMatch(/30 days after issue/);
});

test("TC-077a invoice issued 29d23h ago: refused", async ({ page }) => {
	const r = await defaultsForm(page, true);
	save("tc077a-29d.json", r);
	expect(r.help).toContain("issued 29 days ago");
	expect(r.errors).toMatch(/30 days after issue/);
});

test("TC-077b invoice issued 30d+1min ago: allowed", async ({ page }) => {
	const r = await defaultsForm(page, true);
	save("tc077b-30d.json", r);
	expect(r.help).toContain("issued 30 days ago");
	expect(r.messages).toContain("was changed successfully");
});

test("TC-080 lifting the defaults suspension is always allowed", async ({ page }) => {
	const r = await defaultsForm(page, false);
	save("tc080-lift.json", r);
	expect(r.messages).toContain("was changed successfully");
});

test("TC-055 edit timezone on the change page", async ({ page }) => {
	await staffLogin(page, STAFF);
	await page.goto(change(IDS.tmp1));
	await page.locator('[name="timezone"]').fill("Asia/Riyadh");
	const r = await saveForm(page);
	save("tc055-timezone-edit.json", r);
	expect(r.messages).toContain("was changed successfully");
});

test("TC-025 a forged subdomain on the change form is ignored", async ({ page }) => {
	await staffLogin(page, STAFF);
	await page.goto(change(IDS.qa));
	await page.locator("#academy_form").evaluate((form) => {
		const input = document.createElement("input");
		input.type = "hidden";
		input.name = "subdomain";
		input.value = "hacked";
		form.appendChild(input);
		const schema = document.createElement("input");
		schema.type = "hidden";
		schema.name = "schema_name";
		schema.value = "academy_hacked";
		form.appendChild(schema);
	});
	const r = await saveForm(page);
	save("tc025-forged-subdomain.json", r);
	expect(r.messages).toContain("was changed successfully");
});
