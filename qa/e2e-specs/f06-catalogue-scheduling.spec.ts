// QA campaign F06 UI smoke (qa/specs/F06-catalogue-subscriptions-scheduling.md TC-006, TC-014, TC-023). Test-only.
// Academy `qa` (EGP, Africa/Cairo). UI language forced to English through localStorage.
import { mkdirSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { expect, type Page, test } from "@playwright/test";

const EVIDENCE = fileURLToPath(new URL("../../../qa/evidence/F06/pw", import.meta.url));
mkdirSync(EVIDENCE, { recursive: true });
const save = (name: string, data: unknown) =>
	writeFileSync(`${EVIDENCE}/${name}`, JSON.stringify(data, null, 2));

const QA = "http://qa.etqan.localhost";
const ADMIN = { email: "qa-admin@qa.etqan.test", password: "QA-Admin-2026!" };
const P1 = 3; // QA6 Pkg 2x1m (EGP 150000)
const C1 = 3; // QA6 Quran
const STUDENT4 = 215;
const stamp = Date.now().toString().slice(-6);

async function login(page: Page) {
	await page.goto(`${QA}/app/login`);
	await page.evaluate(() => localStorage.setItem("etqan-locale", "en"));
	await page.reload();
	await page.getByRole("textbox", { name: /email/i }).fill(ADMIN.email);
	await page.getByRole("textbox", { name: /^password$/i }).fill(ADMIN.password);
	await page.getByRole("button", { name: /^sign in$/i }).click();
	await page.waitForURL((u) => !u.pathname.includes("/login"));
}

const api = (page: Page, path: string, method = "GET", body?: unknown) =>
	page.evaluate(
		async ({ path, method, body }) => {
			const csrf = document.cookie.match(/csrftoken=([^;]+)/)?.[1] ?? "";
			const r = await fetch(`/api/v1${path}`, {
				method,
				headers: { "Content-Type": "application/json", "X-CSRFToken": csrf },
				body: body === undefined ? undefined : JSON.stringify(body),
			});
			return { status: r.status, json: await r.json().catch(() => null) };
		},
		{ path, method, body },
	);

function watch(page: Page) {
	const errors: string[] = [];
	page.on("console", (m) => m.type() === "error" && errors.push(m.text()));
	page.on("response", (r) => r.status() >= 500 && errors.push(`${r.status()} ${r.url()}`));
	return errors;
}

test.describe.configure({ mode: "serial" });

test("TC-006 country prices: UI shows major units, API stores minor units", async ({ page }) => {
	const errors = watch(page);
	await login(page);
	// start from a known list: SA only
	expect((await api(page, `/catalogue/packages/${P1}/country-prices/`, "PUT", [
		{ country: "SA", price_minor: 5000, currency: "SAR" },
	])).status).toBe(200);
	await page.goto(`${QA}/app/catalogue/packages/${P1}`);
	await expect(page.getByRole("heading", { name: "Prices by country" })).toBeVisible();
	const row1 = page.getByRole("group", { name: "Country price 1" });
	await expect(row1.getByLabel(/^Country/)).toHaveValue("SA");
	await expect(row1.getByLabel(/^Price \(SAR\)/)).toHaveValue("50.00");
	await page.getByRole("button", { name: "Add country" }).click();
	const row2 = page.getByRole("group", { name: "Country price 2" });
	await row2.getByLabel(/^Country/).selectOption("AE");
	await row2.getByLabel(/^Currency/).selectOption("AED");
	await row2.getByLabel(/^Price/).fill("40.00");
	await page.getByRole("button", { name: "Save prices" }).click();
	await expect(page.getByText("Prices saved.")).toBeVisible();
	await page.reload();
	await expect(page.getByRole("group", { name: "Country price 1" }).getByLabel(/^Country/)).toHaveValue("AE");
	await expect(page.getByRole("group", { name: "Country price 1" }).getByLabel(/^Price \(AED\)/)).toHaveValue("40.00");
	await page.screenshot({ path: `${EVIDENCE}/tc006-country-prices.png`, fullPage: true });
	const got = await api(page, `/catalogue/packages/${P1}/country-prices/`);
	save("tc006-api.json", got);
	expect(got.json).toEqual([
		{ country: "AE", price_minor: 4000, currency: "AED" },
		{ country: "SA", price_minor: 5000, currency: "SAR" },
	]);
	// restore SA only
	await api(page, `/catalogue/packages/${P1}/country-prices/`, "PUT", [
		{ country: "SA", price_minor: 5000, currency: "SAR" },
	]);
	save("tc006-errors.json", errors);
	expect(errors.filter((e) => /^5\d\d /.test(e))).toEqual([]);
});

test("TC-014 renew, cancel the renewal, renew again, archive an ended one", async ({ page }) => {
	const errors = watch(page);
	await login(page);
	const made = await api(page, "/subscriptions/", "POST", {
		student: STUDENT4, course: C1, teacher: 7, package: P1, starts_on: "2026-10-19",
		price_minor: 0, slots: [{ weekdays: [6], start_time: "22:00" }], notes: `QA6 UI ${stamp}`,
	});
	expect(made.status).toBe(201);
	const id = made.json.id as number;
	await page.goto(`${QA}/app/scheduling/subscriptions/${id}`);
	await page.getByRole("button", { name: "Renew", exact: true }).click();
	const dlg = page.getByRole("dialog").or(page.getByRole("alertdialog"));
	await expect(dlg.getByRole("heading", { name: "Renew subscription" })).toBeVisible();
	await dlg.getByRole("button", { name: "Renew", exact: true }).click();
	// the UI moves to the renewal's page, which links back to the previous term
	await expect(page.getByRole("link", { name: "Open the previous term" })).toBeVisible();
	await expect(page).not.toHaveURL(new RegExp(`/subscriptions/${id}$`));
	const after1 = await api(page, `/subscriptions/${id}/`);
	const r1 = after1.json.renewal?.id ?? after1.json.renewal;
	expect(r1).toBeTruthy();
	const ren1 = await api(page, `/subscriptions/${r1}/`);
	expect(ren1.json.starts_on).toBe("2026-11-19");
	expect(after1.json.status).toBe("active");
	await page.screenshot({ path: `${EVIDENCE}/tc014-renewed.png`, fullPage: true });
	// second renew through the API is refused
	const second = await api(page, `/subscriptions/${id}/renew/`, "POST", {});
	expect(second.status).toBe(409);
	expect(second.json.code).toBe("scheduling.already_renewed");
	// cancel the renewal in the UI
	await page.goto(`${QA}/app/scheduling/subscriptions/${r1}`);
	await page.getByRole("button", { name: "Cancel subscription" }).click();
	await page.getByRole("alertdialog").getByRole("button", { name: "Cancel subscription" }).click();
	await expect(page.getByText("Subscription cancelled.", { exact: true })).toBeVisible();
	// renew the original again in the UI: allowed now
	await page.goto(`${QA}/app/scheduling/subscriptions/${id}`);
	await page.getByRole("button", { name: "Renew", exact: true }).click();
	await page.getByRole("dialog").or(page.getByRole("alertdialog")).getByRole("button", { name: "Renew", exact: true }).click();
	await expect(page.getByRole("link", { name: "Open the previous term" })).toBeVisible();
	const after2 = await api(page, `/subscriptions/${id}/`);
	const r2 = after2.json.renewal?.id ?? after2.json.renewal;
	expect(r2).toBeTruthy();
	expect(r2).not.toBe(r1);
	// archive: a live one is refused, the cancelled renewal (nothing to come) is archived in the UI
	const live = await api(page, `/subscriptions/${id}/archive/`, "POST", {});
	expect(live.status).toBeGreaterThanOrEqual(400);
	await page.goto(`${QA}/app/scheduling/subscriptions/${r1}`);
	await page.getByRole("button", { name: "Archive (delete keeping records)" }).click();
	await page.getByRole("alertdialog").getByRole("button", { name: "Archive subscription" }).click();
	await expect(page.getByText(/^Archived on .+ by QA Admin\.$/)).toBeVisible();
	await page.screenshot({ path: `${EVIDENCE}/tc014-archived.png`, fullPage: true });
	const renewArchived = await api(page, `/subscriptions/${r1}/renew/`, "POST", {});
	save("tc014-api.json", { id, r1, r2, second, live, renewArchived, errors });
	expect(renewArchived.status).toBe(409);
	expect(errors.filter((e) => /^5\d\d /.test(e))).toEqual([]);
});

test("TC-023 study group created in the UI, one-group rule", async ({ page }) => {
	const errors = watch(page);
	await login(page);
	const name = `QA6 Group UI ${stamp}`;
	await page.goto(`${QA}/app/people/groups`);
	await page.getByRole("button", { name: "Add study group" }).click();
	const dialog = page.getByRole("dialog");
	await dialog.getByLabel(/^Name/).fill(name);
	for (const s of ["QA6 Student 1", "QA6 Student 4"]) {
		await dialog.getByLabel("Find a student").fill(s);
		await dialog.getByRole("button", { name: `Add ${s}` }).click();
	}
	await dialog.getByRole("button", { name: "Save study group" }).click();
	await expect(dialog).toBeHidden();
	await page.reload();
	await page.getByRole("searchbox").fill(name);
	const row = page.getByRole("row", { name: new RegExp(name) });
	await expect(row).toContainText("QA6 Student 1");
	await expect(row).toContainText("QA6 Student 4");
	await page.screenshot({ path: `${EVIDENCE}/tc023-group.png`, fullPage: true });
	const list = await api(page, `/groups/?q=${encodeURIComponent(name)}`);
	const g = (list.json.results ?? list.json)[0];
	const dup = await api(page, "/groups/", "POST", { name: `${name} dup`, student_ids: [212] });
	save("tc023-api.json", { list, dup, errors });
	expect(dup.status).toBe(400);
	expect(g.members.map((m: { id: number }) => m.id).sort()).toEqual([212, 215]);
	expect((await api(page, `/groups/${g.id}/`, "DELETE")).status).toBe(204);
	expect(errors.filter((e) => /^5\d\d /.test(e))).toEqual([]);
});
