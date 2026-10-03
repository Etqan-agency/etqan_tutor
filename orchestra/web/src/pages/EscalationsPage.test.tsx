import { fireEvent, screen, waitFor, within } from "@testing-library/react";
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
		expect(
			await screen.findByRole("heading", { level: 1, name: "Escalations" }),
		).toBeInTheDocument();
		const open = screen.getByRole("region", { name: "Open" });
		expect(
			within(open).getByRole("heading", { level: 2, name: "Open" }),
		).toBeInTheDocument();
		expect(within(open).getByText("Live Stripe keys?")).toBeInTheDocument();
		const resolved = screen.getByRole("region", { name: "Resolved" });
		expect(
			within(resolved).getByRole("heading", { level: 2, name: "Resolved" }),
		).toBeInTheDocument();
		expect(within(resolved).getByText("Yes")).toBeInTheDocument();
		const user = userEvent.setup();
		await user.click(within(open).getByRole("button", { name: "Answer" }));
		const dialog = screen.getByRole("dialog");
		await user.type(
			within(dialog).getByLabelText("Your answer"),
			"Use test keys",
		);
		await user.click(within(dialog).getByRole("button", { name: "Confirm" }));
		await waitFor(() =>
			expect(lastPost(calls)?.body).toEqual({ answer: "Use test keys" }),
		);
	});

	it("JSON-escapes quotes and newlines in the answer command preview", async () => {
		const state = makeState((l) => {
			l.escalations.push({
				id: "E2",
				phase: "B3",
				kind: "money",
				question: "Live Stripe keys?",
				status: "open",
				answer: null,
			});
		});
		mockApi({
			"GET /api/state": { body: state },
			"GET /api/ci": { body: { master: null, prs: [] } },
		});
		renderAt("/escalations");
		const user = userEvent.setup();
		await user.click(await screen.findByRole("button", { name: "Answer" }));
		const dialog = screen.getByRole("dialog");
		const textarea = within(dialog).getByLabelText("Your answer");
		fireEvent.change(textarea, { target: { value: 'say "hi"\nbye' } });
		expect(dialog).toHaveTextContent(JSON.stringify('say "hi"\nbye'));
	});
});
