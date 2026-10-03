import { mockApi } from "@/test/api";
import { ApiError, get, post, resetToken } from "./client";

describe("client", () => {
	it("sends the page's token with every write", async () => {
		const calls = mockApi({ "POST /api/queue/next": { body: { ok: true } } });
		await post("/api/queue/next");
		expect(calls[0].headers["x-orchestra-token"]).toBe("test-token");
		expect(calls[0].headers["content-type"]).toBe("application/json");
	});

	it("asks the dev server for a token when the page has none", async () => {
		document.head.querySelector('meta[name="orchestra-token"]')?.remove();
		resetToken();
		const calls = mockApi({
			"GET /api/token": { body: { token: "dev-token" } },
			"POST /api/queue/next": { body: { ok: true } },
		});
		await post("/api/queue/next");
		expect(calls[1].headers["x-orchestra-token"]).toBe("dev-token");
	});

	it("turns a ledger refusal and a failed command into ApiError", async () => {
		mockApi({
			"POST /api/queue/next": {
				status: 409,
				body: { error: "B3a is in flight" },
			},
			"POST /api/phases/B3/stack": {
				status: 500,
				body: { ok: false, exit_code: 3, output_tail: "boom" },
			},
		});
		await expect(post("/api/queue/next")).rejects.toMatchObject({
			status: 409,
			message: "B3a is in flight",
		});
		const failure = await post("/api/phases/B3/stack", { up: true }).catch(
			(e: ApiError) => e,
		);
		expect(failure).toBeInstanceOf(ApiError);
		expect(failure).toMatchObject({
			message: "command failed (exit 3)",
			outputTail: "boom",
			exitCode: 3,
		});
	});

	it("reads JSON", async () => {
		mockApi({ "GET /api/ci": { body: { master: null, prs: [] } } });
		expect(await get("/api/ci")).toEqual({ master: null, prs: [] });
	});
});
