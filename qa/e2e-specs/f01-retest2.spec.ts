// QA F01 retest 2 (ETQAN-QA-013, ETQAN-QA-014): Etqan console UI smoke.
// Test-only, QA campaign. Targets qa-tmp-1 only; run each test on its own
// with --grep and --workers=1. DB checks are done outside, in psql.
import { expect, type Page, test } from "@playwright/test";
import { BASE_URL } from "../fixtures";
import { EVIDENCE, STAFF, save, staffLogin } from "./f01-helpers";

const ACADEMIES = `${BASE_URL}/admin/tenants/academy/`;
const STAFF_VIEW_ALL = {
	email: "ops-view-all@qa.etqan.test",
	password: "QA-Etqan-ViewAll-2026!",
};
const shot = (page: Page, name: string) =>
	page.screenshot({ path: `${EVIDENCE}/${name}.png`, fullPage: true });

async function idOf(page: Page, text: string): Promise<string> {
	await page.goto(`${ACADEMIES}?q=${encodeURIComponent(text)}`);
	const href = await page
		.locator("#result_list tbody tr th a")
		.filter({ hasText: text })
		.first()
		.getAttribute("href");
	return (href ?? "").match(/\/(\d+)\/change\//)?.[1] ?? "";
}

test("R2-TC-151 view-only staff are offered no action on any console list", async ({ page }) => {
	await staffLogin(page, STAFF_VIEW_ALL);
	const lists = [
		"etqan_billing/etqaninvoice",
		"account/emailaddress",
		"django_celery_beat/periodictask",
		"integrations/platformaccount",
		"identity/teacherprofile",
		"tenants/academy",
		"tenants/domain",
	];
	const out: Record<string, { status: number; actions: string[]; checkboxes: number }> = {};
	for (const l of lists) {
		const res = await page.goto(`${BASE_URL}/admin/${l}/`);
		out[l] = {
			status: res?.status() ?? 0,
			actions: (await page.locator('select[name="action"] option').allInnerTexts()).filter(
				(a) => !a.startsWith("-"),
			),
			checkboxes: await page.locator('input[name="_selected_action"]').count(),
		};
		if (l === "etqan_billing/etqaninvoice" || l === "django_celery_beat/periodictask")
			await shot(page, `r2-tc151-${l.replace("/", "-")}`);
	}
	save("r2-tc151-view-all-ui.json", out);
	for (const l of lists) {
		expect(out[l].status, l).toBe(200);
		expect(out[l].actions, l).toEqual([]);
		expect(out[l].checkboxes, l).toBe(0);
	}
});

test("R2-TC-152 a stale change page in a second tab undoes nothing", async ({ browser }) => {
	const context = await browser.newContext();
	const tabA = await context.newPage();
	await staffLogin(tabA, STAFF);
	const id = await idOf(tabA, "QA Tmp One");
	await tabA.goto(`${ACADEMIES}${id}/change/`);
	const shownA = {
		status: await tabA.locator('select[name="status"]').inputValue(),
		families: await tabA.locator('input[name="feature_families"]').isChecked(),
	};

	// Tab B: suspend with the action, then untick Family accounts on a fresh page.
	const tabB = await context.newPage();
	await tabB.goto(ACADEMIES);
	await tabB.locator(`input[name="_selected_action"][value="${id}"]`).check();
	await tabB.locator('select[name="action"]').selectOption("suspend_academies");
	await tabB.locator('button[name="index"]').click();
	await tabB.locator(".messagelist li").first().waitFor();
	const suspendMsg = (await tabB.locator(".messagelist li").allInnerTexts()).join(" | ");
	await tabB.goto(`${ACADEMIES}${id}/change/`);
	await tabB.locator('input[name="feature_families"]').uncheck();
	await tabB.locator('[name="_save"]').click();
	await tabB.locator(".messagelist li").first().waitFor();
	const tabBMsg = (await tabB.locator(".messagelist li").allInnerTexts()).join(" | ");

	// Tab A (still showing active + families on): change only Plan notes.
	await tabA.locator('textarea[name="plan_notes"]').fill("QA-R2-UI-stale-edit");
	await tabA.locator('[name="_save"]').click();
	await tabA.locator(".messagelist li").first().waitFor();
	const tabAMsg = (await tabA.locator(".messagelist li").allInnerTexts()).join(" | ");

	await tabA.goto(`${ACADEMIES}${id}/change/`);
	const after = {
		status: await tabA.locator('select[name="status"]').inputValue(),
		families: await tabA.locator('input[name="feature_families"]').isChecked(),
		planNotes: await tabA.locator('textarea[name="plan_notes"]').inputValue(),
	};
	await shot(tabA, "r2-tc152-after-stale-save");
	await tabA.goto(`${ACADEMIES}${id}/history/`);
	const history = await tabA.locator("#change-history").innerText();
	save("r2-tc152-ui.json", { id, shownA, suspendMsg, tabBMsg, tabAMsg, after, history });
	await context.close();

	expect(shownA).toEqual({ status: "active", families: true });
	expect(suspendMsg).toContain("Suspended 1 academies.");
	expect(tabAMsg).toMatch(/was changed successfully/);
	expect(after).toEqual({ status: "suspended", families: false, planNotes: "QA-R2-UI-stale-edit" });
	expect(history.split("\n").find((l) => l.includes("QA-R2") || l.includes("Plan notes"))).toBeTruthy();
});
