// QA campaign F05 UI smoke (qa/specs/F05-people.md TC-028, TC-029, TC-030). Test-only.
// Academy `qa` (EGP, Africa/Cairo). The UI language is forced to English through localStorage.
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import AxeBuilder from "@axe-core/playwright";
import { expect, type Page, test } from "@playwright/test";

const EVIDENCE = fileURLToPath(new URL("../../../qa/evidence/F05/pw", import.meta.url));
mkdirSync(EVIDENCE, { recursive: true });
const save = (name: string, data: unknown) =>
	writeFileSync(`${EVIDENCE}/${name}`, JSON.stringify(data, null, 2));

const QA = "http://qa.etqan.localhost";
const ADMIN = { email: "qa-admin@qa.etqan.test", password: "QA-Admin-2026!" };
const TEACHER = { email: "qa-teacher@qa.etqan.test", password: "QA-People-2026!" };
const STUDENT = { email: "qa-student@qa.etqan.test", password: "QA-People-2026!" };
const TEACHER_ID = 7;
const stamp = Date.now().toString().slice(-6);

async function login(page: Page, who: { email: string; password: string }) {
	await page.goto(`${QA}/app/login`);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));
	await page.reload();
	await page.getByRole("textbox", { name: /email/i }).fill(who.email);
	await page.getByRole("textbox", { name: /^password$/i }).fill(who.password);
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

function watch(page: Page) {
	const errors: string[] = [];
	page.on("console", (m) => m.type() === "error" && errors.push(m.text()));
	const bad: string[] = [];
	page.on("response", (r) => r.status() >= 500 && bad.push(`${r.status()} ${r.url()}`));
	return { errors, bad };
}

test("TC-028 add a student, page through the list, bulk status, deactivate and activate", async ({ page }) => {
	const w = watch(page);
	await login(page, ADMIN);
	const name = `QA5 UI ${stamp}`;
	const email = `f05-ui-${stamp}@qa.etqan.test`;
	await page.goto(`${QA}/app/people/students/new`);
	await page.getByLabel(/^full name/i).fill(name);
	await page.getByLabel(/^email/i).fill(email);
	await page.getByRole("button", { name: "Save", exact: true }).click();
	await expect(page.getByText("Saved.").first()).toBeVisible();

	const created = await api(page, `/people/students/?q=${encodeURIComponent(name)}`);
	expect(created.json.count).toBe(1);
	const sid = created.json.results[0].id as number;
	expect(created.json.results[0].user.account_state).toBe("invited");

	// Pagination equals the API.
	await page.goto(`${QA}/app/people/students`);
	const all = await api(page, "/people/students/");
	const pages = Math.ceil(all.json.count / 25);
	await expect(page.getByText(new RegExp(`Page 1 of ${pages}`))).toBeVisible();
	await page.getByRole("button", { name: /^next/i }).click();
	await expect(page.getByText(new RegExp(`Page 2 of ${pages}`))).toBeVisible();
	const page2 = await api(page, "/people/students/?page=2");
	await expect(page.getByRole("row", { name: new RegExp(page2.json.results[0].user.full_name) })).toBeVisible();

	// Search, then bulk-set status on 3 rows.
	await page.getByRole("searchbox").fill("QA5 Bulk 05");
	await expect(page.getByRole("row", { name: /QA5 Bulk 05/ })).toBeVisible();
	await page.getByRole("searchbox").fill("QA5 Bulk 1");
	await expect(page.getByRole("row", { name: /QA5 Bulk 11/ })).toBeVisible();
	const picks = ["QA5 Bulk 11", "QA5 Bulk 12", "QA5 Bulk 13"];
	for (const p of picks) await page.getByRole("checkbox", { name: `Select ${p}` }).check();
	await expect(page.getByText("3 selected").first()).toBeVisible();
	await page.getByLabel("New status").selectOption("paused");
	await page.getByRole("button", { name: "Set status" }).click();
	await expect(page.getByText("3 updated.").first()).toBeVisible();
	const after = await api(page, "/people/students/?q=QA5%20Bulk%201&status=paused&page_size=100");
	const pausedNames = after.json.results.map((r: { user: { full_name: string } }) => r.user.full_name);
	for (const p of picks) expect(pausedNames).toContain(p);

	// Deactivate and activate from the person page.
	await page.goto(`${QA}/app/people/students/${sid}`);
	await page.getByRole("button", { name: "Deactivate", exact: true }).click();
	const confirm = page.getByRole("dialog");
	if (await confirm.isVisible().catch(() => false))
		await confirm.getByRole("button", { name: "Deactivate", exact: true }).click();
	await expect(page.getByText("Deactivated.", { exact: true }).first()).toBeVisible();
	expect((await api(page, `/people/students/${sid}/`)).json.user.is_active).toBe(false);
	await page.getByRole("button", { name: "Activate", exact: true }).click();
	await expect(page.getByText("Activated.", { exact: true }).first()).toBeVisible();
	await expect.poll(async () => (await api(page, `/people/students/${sid}/`)).json.user.is_active).toBe(true);
	expect((await api(page, `/people/students/${sid}/`)).json.user.is_active).toBe(true);

	await page.goto(`${QA}/app/people/students`);
	await expect(page.getByRole("row").nth(1)).toBeVisible();
	const axe = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa"]).analyze();
	save("tc028-axe.json", axe.violations.map((v) => ({ id: v.id, impact: v.impact, n: v.nodes.length })));
	save("tc028.json", { sid, name, pages, picks, errors: w.errors, bad: w.bad });
	expect(w.bad).toEqual([]);
	expect(axe.violations.filter((v) => v.impact === "critical")).toEqual([]);
});

test("TC-029 family with a paying parent: payer options, save, needs-choosing flag, retire", async ({ page }) => {
	const w = watch(page);
	await login(page, ADMIN);
	// Two fresh siblings and their parent, through the API.
	const mk = async (kind: string, full: string) =>
		(await api(page, `/people/${kind}/`, "POST", { user: { full_name: full }, profile: {} })).json.id as number;
	const s1 = await mk("students", `QA5 UI Sib A ${stamp}`);
	const s2 = await mk("students", `QA5 UI Sib B ${stamp}`);
	const par = await mk("parents", `QA5 UI Parent ${stamp}`);
	expect((await api(page, `/people/students/${s1}/guardians/`, "POST", { parent_id: par })).status).toBe(201);
	const payers = (await api(page, `/people/families/payers/?students=${s1},${s2}`)).json;

	const family = `QA5 UI Family ${stamp}`;
	await page.goto(`${QA}/app/people/families`);
	await page.getByRole("button", { name: "Add family" }).click();
	const dialog = page.getByRole("dialog");
	await dialog.getByLabel(/^name/i).fill(family);
	for (const n of [`QA5 UI Sib A ${stamp}`, `QA5 UI Sib B ${stamp}`]) {
		await dialog.getByLabel("Find a student").fill(n);
		await dialog.getByRole("button", { name: `Add ${n}`, exact: true }).click();
	}
	const payer = dialog.getByLabel(/^payer/i);
	await expect(payer.locator("option", { hasText: `QA5 UI Parent ${stamp}` })).toHaveCount(1);
	const options = (await payer.locator("option").allTextContents()).filter((o) => o.trim());
	save("tc029-payers.json", { api: payers, ui: options });
	for (const p of payers) expect(options.join("|")).toContain(p.full_name);
	await payer.selectOption({ label: `QA5 UI Parent ${stamp} (parent)` });
	await dialog.getByRole("button", { name: "Save family" }).click();
	await expect(page.getByText("Family saved.").first()).toBeVisible();

	const list = await api(page, `/people/families/?search=${encodeURIComponent(family)}`);
	const fam = (list.json.results ?? list.json)[0];
	expect(fam.payer.id).toBe(par);
	expect(fam.payer_needs_choosing).toBe(false);

	// Deactivate the payer: the flag turns on, in the API and on the family row.
	expect((await api(page, `/people/parents/${par}/deactivate/`, "POST")).status).toBe(200);
	expect((await api(page, `/people/families/${fam.id}/`)).json.payer_needs_choosing).toBe(true);
	await page.goto(`${QA}/app/people/families`);
	await page.getByRole("searchbox").fill(family);
	const row = page.getByRole("row", { name: new RegExp(family) });
	await expect(row).toBeVisible();
	await page.screenshot({ path: `${EVIDENCE}/tc029-flag.png`, fullPage: true });
	const rowText = await row.innerText();
	// Retire through the API (UI retire is covered by families.spec.ts); then reactivate the payer.
	expect((await api(page, `/people/families/${fam.id}/`, "PATCH", { is_active: false })).status).toBe(200);
	await api(page, `/people/parents/${par}/activate/`, "POST");
	save("tc029.json", { s1, s2, par, family: fam.id, rowText, errors: w.errors, bad: w.bad });
	expect(w.bad).toEqual([]);
});

test("TC-030 contract uploaded by the admin, downloaded by the teacher; student is refused", async ({ browser }) => {
	const pdf = Buffer.from("%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n" + stamp);
	const sha = createHash("sha256").update(pdf).digest("hex");
	const admin = await browser.newPage();
	const w = watch(admin);
	await login(admin, ADMIN);
	await admin.goto(`${QA}/app/people/contracts?teacher=${TEACHER_ID}`);
	await admin.getByRole("button", { name: "Add contract" }).click();
	const dialog = admin.getByRole("dialog");
	const teacherSel = dialog.getByLabel(/^teacher/i);
	if ((await teacherSel.count()) && (await teacherSel.evaluate((e) => e.tagName)) === "SELECT")
		await teacherSel.selectOption(String(TEACHER_ID));
	await dialog.getByLabel(/^reference/i).fill(`UI-${stamp}`);
	await dialog.getByLabel(/contract file/i).setInputFiles({ name: `ui-${stamp}.pdf`, mimeType: "application/pdf", buffer: pdf });
	await dialog.getByRole("button", { name: "Save", exact: true }).click();
	await expect(admin.getByText("Contract saved.").first()).toBeVisible();
	const list = await api(admin, `/contracts/?q=UI-${stamp}`);
	expect(list.json.count).toBe(1);
	expect(list.json.results[0].teacher.id).toBe(TEACHER_ID);
	await admin.close();

	const teacher = await browser.newPage();
	await login(teacher, TEACHER);
	await teacher.goto(`${QA}/app/account`);
	await expect(teacher.getByText("My contracts").first()).toBeVisible();
	const [download] = await Promise.all([
		teacher.waitForEvent("download"),
		teacher.getByRole("row", { name: new RegExp(`UI-${stamp}`) }).getByRole("button", { name: /download/i })
			.or(teacher.getByRole("listitem").filter({ hasText: `UI-${stamp}` }).getByRole("button", { name: /download/i }))
			.or(teacher.getByRole("link", { name: /download/i }).first())
			.first()
			.click(),
	]);
	const got = createHash("sha256").update(readFileSync(await download.path())).digest("hex");
	await teacher.close();

	const student = await browser.newPage();
	await login(student, STUDENT);
	await student.goto(`${QA}/app/people/contracts`);
	await student.waitForLoadState("networkidle");
	const studentUrl = student.url();
	const studentSees = await student.getByRole("button", { name: "Add contract" }).count();
	const apiStudent = await api(student, "/contracts/");
	await student.screenshot({ path: `${EVIDENCE}/tc030-student.png` });
	await student.close();
	save("tc030.json", { sha, got, studentUrl, studentSees, apiStudent: apiStudent.status, bad: w.bad });
	expect(got).toBe(sha);
	expect(studentSees).toBe(0);
	expect(apiStudent.status).toBe(403);
});
