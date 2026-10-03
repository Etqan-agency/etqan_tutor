import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { lastPost, mockApi } from "@/test/api";
import { makeState } from "@/test/fixtures";
import { renderAt } from "@/test/render";

describe("EscalationsPage", () => {
	it("lists open ones first and answers one", async () => {
		const state = makeState((l) => {
			l.escalations.push(
				{
					id: "E1",
					phase: "B3",
					kind: "money",
					question: "Old?",
					status: "resolved",
					answer: "Yes",
				},
				{
					id: "E2",
					phase: "B3",
					kind: "money",
					question: "Live Stripe keys?",
					status: "open",
					answer: null,
				},
			);
		});
		const calls = mockApi({
			"GET /api/state": { body: state },
			"GET /api/ci": { body: { master: null, prs: [] } },
			"POST /api/escalations/E2/resolve": { body: { ok: true } },
		});
		renderAt("/escalations");
		const open = await screen.findByRole("region", { name: "Open" });
		expect(within(open).getByText("Live Stripe keys?")).toBeInTheDocument();
		expect(
			within(screen.getByRole("region", { name: "Resolved" })).getByText("Yes"),
		).toBeInTheDocument();
		const user = userEvent.setup();
		await user.click(within(open).getByRole("button", { name: "Answer" }));
		await user.type(
			within(screen.getByRole("dialog")).getByLabelText("Your answer"),
			"Use test keys",
		);
		await user.click(
			within(screen.getByRole("dialog")).getByRole("button", {
				name: "Confirm",
			}),
		);
		await waitFor(() =>
			expect(lastPost(calls)?.body).toEqual({ answer: "Use test keys" }),
		);
	});
});
