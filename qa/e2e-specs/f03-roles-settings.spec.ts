// QA campaign F03 UI smoke (qa/specs/F03-roles-settings.md TC-023, TC-024). Test-only.
// Academy `qa`. The UI language is forced to English through localStorage.
import { mkdirSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { expect, type Page, test } from "@playwright/test";
import { acceptInvite } from "../fixtures";
import { manage } from "../manage";

const EVIDENCE = fileURLToPath(
	new URL("../../../qa/evidence/F03/pw", import.meta.url),
);
mkdirSync(EVIDENCE, { recursive: true });
const save = (name: string, data: unknown) =>
	writeFileSync(`${EVIDENCE}/${name}`, JSON.stringify(data, null, 2));

const QA = "http://qa.etqan.localhost";
const ADMIN = { email: "qa-admin@qa.etqan.test", password: "QA-Admin-2026!" };
const NO_ACCESS = "You don't have access to this page.";
const OFF = "This feature isn't enabled for your academy.";

async function adminLogin(page: Page) {
	await page.goto(`${QA}/app/login`);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));
	await page.reload();
	await page.getByRole("textbox", { name: /email/i }).fill(ADMIN.email);
	await page.getByRole("textbox", { name: /^password$/i }).fill(ADMIN.password);
	await page.getByRole("button", { name: /^sign in$/i }).click();
	await page.waitForURL((u) => !u.pathname.includes("/login"));
}

const api = (page: Page, path: string, method = "GET", body?: object) =>
	page.evaluate(
		async ({ path, method, body }) => {
			const csrf = document.cookie.match(/csrftoken=([^;]+)/)?.[1] ?? "";
			const r = await fetch(`/api/v1${path}`, {
				method,
				headers: { "Content-Type": "application/json", "X-CSRFToken": csrf },
				body: body ? JSON.stringify(body) : undefined,
			});
			return { status: r.status, json: await r.json().catch(() => null) };
		},
		{ path, method, body },
	);

test("TC-023 owner builds a role and hires staff; the staff app is narrowed and a retire bites at once", async ({
	page,
	browser,
}) => {
	const stamp = Date.now();
	const role = `F03 UI Desk ${stamp}`;
	const name = `F03 UI Staff ${stamp}`;
	const email = `f03-ui-${stamp}@qa.etqan.test`;
	await adminLogin(page);

	await page.goto(`${QA}/app/settings/roles`);
	await expect(page.getByRole("row", { name: /Supervisor/ })).toBeVisible();
	await page.getByRole("link", { name: "Add role" }).click();
	await page.getByLabel(/^Name \(Arabic\)/).fill(`استقبال ${stamp}`);
	await page.getByLabel(/^Name \(English\)/).fill(role);
	const students = page.getByRole("group", { name: "Students" });
	await students.getByRole("checkbox", { name: "view all", exact: true }).click();
	await students.getByRole("checkbox", { name: "view", exact: true }).click();
	await page.getByRole("button", { name: "Save role" }).click();
	await expect(page.getByText("Role saved.", { exact: true })).toBeVisible();
	await expect(page.getByRole("row", { name: new RegExp(role) })).toBeVisible();
	await page.screenshot({ path: `${EVIDENCE}/tc023-roles.png`, fullPage: true });

	const roles = await api(page, "/access/roles/");
	type Role = { id: number; name_en: string; permissions: string[] };
	const list = (roles.json?.results ?? roles.json) as Role[];
	const created = list.find(
		(r) => r.name_en === role,
	);
	expect(created?.permissions).toEqual(["student.view", "student.view_any"]);

	await page.goto(`${QA}/app/people/staff`);
	await page.getByRole("button", { name: "Add staff member" }).click();
	const dialog = page.getByRole("dialog");
	await dialog.getByLabel(/^Full name/).fill(name);
	await dialog.getByLabel(/^Email/).fill(email);
	await dialog.getByRole("checkbox", { name: role, exact: true }).click();
	await dialog.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page.getByText(`Invite sent to ${email}.`, { exact: true })).toBeVisible();

	const staff = await acceptInvite(browser, email, "F03-UiPass-2026!", name);
	await staff.evaluate(() => localStorage.setItem("etqan-locale", "en"));
	await staff.reload();
	const nav = staff.getByRole("navigation", { name: "Main navigation" });
	await expect(nav.getByRole("link", { name: "Students" })).toBeVisible();
	await expect(nav.getByRole("link", { name: "Invoices" })).toHaveCount(0);
	await expect(nav.getByRole("link", { name: "Roles" })).toHaveCount(0);
	await staff.goto(`${QA}/app/settings/roles`);
	await expect(staff.getByRole("heading", { level: 1, name: NO_ACCESS })).toBeVisible();
	await staff.goto(`${QA}/app/people/students`);
	await expect(staff.getByRole("link", { name: "New student" })).toHaveCount(0);
	await staff.screenshot({ path: `${EVIDENCE}/tc023-staff-students.png`, fullPage: true });

	// Admin retires the role: the staff member's next load is refused.
	const retire = await api(page, `/access/roles/${created?.id}/`, "PATCH", { is_active: false });
	expect(retire.status).toBe(200);
	await staff.reload();
	await expect(staff.getByRole("heading", { level: 1, name: NO_ACCESS })).toBeVisible();
	const after = await api(staff, "/people/students/");
	expect(after.status).toBe(403);
	save("tc023.json", { role: created, retire: retire.status, staffStudentsAfterRetire: after.status });
	await staff.context().close();
});

test("TC-024 settings save and survive reload; features are read-only; quick translate off shows FeatureOff", async ({
	page,
}) => {
	await adminLogin(page);
	await page.goto(`${QA}/app/settings/academy`);
	const grace = page.getByLabel("Renewal grace (days)");
	await grace.fill("5");
	await page.getByLabel("Default currency").selectOption("EUR");
	await page.getByRole("button", { name: "Save", exact: true }).first().click();
	await expect.poll(async () => (await api(page, "/academy/settings/")).json?.renewal_grace_days).toBe(5);
	await page.reload();
	await expect(page.getByLabel("Renewal grace (days)")).toHaveValue("5");
	await expect(page.getByLabel("Default currency")).toHaveValue("EUR");
	const saved = (await api(page, "/academy/settings/")).json;
	await page.screenshot({ path: `${EVIDENCE}/tc024-settings.png`, fullPage: true });

	await page.goto(`${QA}/app/settings/features`);
	await expect(page.getByRole("list", { name: "Money" })).toBeVisible();
	const toggles = await page.locator("main").getByRole("checkbox").count();
	const switches = await page.locator("main").getByRole("switch").count();
	expect(toggles + switches).toBe(0);

	manage("set_features", "qa", "--off", "quick_translate");
	try {
		await page.goto(`${QA}/app/settings/quick-translate`);
		await expect(page.getByRole("heading", { level: 1, name: OFF })).toBeVisible();
		const nav = page.getByRole("navigation", { name: "Main navigation" });
		await expect(nav.getByRole("link", { name: /Quick translate/i })).toHaveCount(0);
		await page.screenshot({ path: `${EVIDENCE}/tc024-featureoff.png`, fullPage: true });
	} finally {
		manage("set_features", "qa", "--on", "quick_translate");
	}
	await page.goto(`${QA}/app/settings/quick-translate`);
	await expect(page.getByRole("heading", { level: 1, name: /Quick translate/i })).toBeVisible();

	// Restore the baseline.
	const restore = await api(page, "/academy/settings/", "PATCH", {
		renewal_grace_days: 7,
		default_currency: "EGP",
	});
	expect(restore.status).toBe(200);
	save("tc024.json", { saved, toggles, switches, restored: restore.json });
});
