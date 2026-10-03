import { screen, waitFor } from "@testing-library/react";
import { mockApi } from "@/test/api";
import { makeState } from "@/test/fixtures";
import { renderAt } from "@/test/render";
import { FakeEventSource } from "@/test/setup";

describe("Layout", () => {
	it("counts open escalations and shows the live connection", async () => {
		const state = makeState((l) => {
			l.escalations.push(
				{
					id: "E1",
					phase: "B3",
					kind: "money",
					question: "keys?",
					status: "open",
					answer: null,
				},
				{
					id: "E2",
					phase: "B3",
					kind: "money",
					question: "x",
					status: "resolved",
					answer: "y",
				},
			);
		});
		mockApi({
			"GET /api/state": { body: state },
			"GET /api/ci": { body: { master: null, prs: [] } },
		});
		renderAt("/");
		expect(
			await screen.findByRole("link", { name: /Escalations 1/ }),
		).toBeInTheDocument();
		expect(screen.getByText("Reconnecting…")).toBeInTheDocument();
		FakeEventSource.last?.onopen?.();
		expect(await screen.findByText("Live")).toBeInTheDocument();
	});

	it("refetches the state when the server says the ledger changed", async () => {
		const calls = mockApi({
			"GET /api/state": { body: makeState() },
			"GET /api/ci": { body: { master: null, prs: [] } },
		});
		renderAt("/");
		await screen.findByText("Slot 1");
		const before = calls.filter((c) => c.path === "/api/state").length;
		FakeEventSource.last?.emit("ledger");
		await waitFor(() =>
			expect(
				calls.filter((c) => c.path === "/api/state").length,
			).toBeGreaterThan(before),
		);
	});
});
