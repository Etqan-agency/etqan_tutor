// QA campaign F01 helpers (qa/specs/F01-tenancy-provisioning.md). Test-only.
import { mkdirSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { type APIRequestContext, expect, type Page } from "@playwright/test";
import { BASE_URL } from "../fixtures";

/** qa/evidence/F01/pw in the meta repo (dashboard/e2e/qa -> ../../../qa). */
export const EVIDENCE =
	process.env.QA_EVIDENCE_DIR ??
	fileURLToPath(new URL("../../../qa/evidence/F01/pw", import.meta.url));
mkdirSync(EVIDENCE, { recursive: true });

export function save(name: string, data: unknown) {
	writeFileSync(
		`${EVIDENCE}/${name}`,
		typeof data === "string" ? data : JSON.stringify(data, null, 2),
	);
}

export const STAFF = {
	email: "ops@qa.etqan.test",
	password: "QA-Etqan-Staff-2026!",
};
export const STAFF_VIEW = {
	email: "ops-view@qa.etqan.test",
	password: "QA-Etqan-View-2026!",
};
export const STAFF_NOPERM = {
	email: "ops-noperm@qa.etqan.test",
	password: "QA-Etqan-NoPerm-2026!",
};
export const QA = {
	sub: "qa",
	name: "Etqan QA Academy",
	adminEmail: "qa-admin@qa.etqan.test",
	adminName: "QA Admin",
	password: "QA-Admin-2026!",
};
export const QAOTHER = {
	sub: "qaother",
	name: "Etqan QA Other",
	adminEmail: "qaother-admin@qa.etqan.test",
	adminName: "QA Other Admin",
	password: "QA-Other-2026!",
};

/** Collect console errors and failed requests of a page. */
export function watchConsole(page: Page): string[] {
	const errors: string[] = [];
	page.on("console", (msg) => {
		if (msg.type() === "error") errors.push(`console: ${msg.text()}`);
	});
	page.on("pageerror", (err) => errors.push(`pageerror: ${err.message}`));
	return errors;
}

export async function staffLogin(
	page: Page,
	who: { email: string; password: string },
) {
	await page.goto(`${BASE_URL}/admin/login/`);
	await page.locator("#id_username").fill(who.email);
	await page.locator("#id_password").fill(who.password);
	await page.getByRole("button", { name: /log in/i }).click();
}

/** A JSON API call on an academy with the request context's cookies, sending
 * the csrftoken cookie back as X-CSRFToken (as the dashboard does). */
export async function api(
	request: APIRequestContext,
	origin: string,
	method: "GET" | "POST" | "PUT" | "PATCH" | "DELETE",
	path: string,
	data?: object,
	cookies?: { name: string; value: string }[],
) {
	const jar =
		cookies ?? (await request.storageState()).cookies.filter((c) =>
			origin.includes(c.domain.replace(/^\./, "")),
		);
	const csrf = jar.find((c) => c.name === "csrftoken")?.value ?? "";
	const res = await request.fetch(`${origin}/api/v1/${path}`, {
		method,
		headers: { "X-CSRFToken": csrf, Referer: `${origin}/app/` },
		data,
	});
	let body: unknown;
	try {
		body = await res.json();
	} catch {
		body = await res.text().catch(() => "");
	}
	return { status: res.status(), body };
}

export async function expectNoServerError(page: Page) {
	await expect(page.locator("body")).not.toContainText("Server Error (500)");
}
