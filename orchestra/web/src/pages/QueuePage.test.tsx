import { fireEvent, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { lastPost, mockApi } from "@/test/api";
import { makeState } from "@/test/fixtures";
import { renderAt } from "@/test/render";

function state(conductor: "busy" | "none" = "none") {
	return makeState(
		(l) => {
			for (const sid of ["B3a", "B3b", "B8a"]) {
				l.slices[sid] = {
					phase: sid.slice(0, 2),
					status: "queued",
					requires: [],
					plan_number: null,
					spec: null,
					plan: null,
					prs: null,
					bounces: 0,
				};
			}
			l.slices.B3a.status = "in-flight";
			l.slices.B3a.prs = "https://github.com/x/y/pull/9";
			l.in_flight = "B3a";
			l.queue = ["B3b", "B8a"];
		},
		{
			sessions: {
				conductor: { id: conductor === "busy" ? "cd" : null, state: conductor },
			},
		},
	);
}

const base = {
	"GET /api/state": { body: state() },
	"GET /api/ci": { body: { master: null, prs: [] } },
};

describe("QueuePage", () => {
	it("lists in flight then queued, and moves a slice up", async () => {
		const calls = mockApi({
			...base,
			"POST /api/queue/reorder": { body: { ok: true } },
		});
		renderAt("/queue");
		expect(await screen.findByText("In flight: B3a")).toBeInTheDocument();
		const rows = screen.getAllByRole("listitem").map((li) => li.textContent);
		expect(rows[0]).toContain("B3b");
		const user = userEvent.setup();
		await user.click(
			within(screen.getByRole("listitem", { name: "B8a" })).getByRole(
				"button",
				{ name: "Move up" },
			),
		);
		await user.click(
			within(screen.getByRole("dialog")).getByRole("button", {
				name: "Confirm",
			}),
		);
		await waitFor(() =>
			expect(lastPost(calls)).toMatchObject({
				path: "/api/queue/reorder",
				body: { slice: "B8a", direction: "up" },
			}),
		);
	});

	it("bounces with a reason and marks merged after typing the slice", async () => {
		const calls = mockApi({
			...base,
			"POST /api/queue/bounce": { body: { ok: true } },
			"POST /api/queue/merged": { body: { ok: true } },
		});
		renderAt("/queue");
		const user = userEvent.setup();
		await user.click(await screen.findByRole("button", { name: "Bounce" }));
		let dialog = screen.getByRole("dialog");
		expect(
			within(dialog).getByRole("button", { name: "Confirm" }),
		).toBeDisabled();
		await user.type(within(dialog).getByLabelText("Reason"), "e2e red");
		await user.click(within(dialog).getByRole("button", { name: "Confirm" }));
		await waitFor(() =>
			expect(lastPost(calls)?.body).toEqual({
				slice: "B3a",
				reason: "e2e red",
			}),
		);

		await user.click(screen.getByRole("button", { name: "Mark merged" }));
		dialog = screen.getByRole("dialog");
		await user.type(within(dialog).getByLabelText("backend head"), "abc1234");
		await user.type(
			within(dialog).getByLabelText("Type B3a to confirm"),
			"B3a",
		);
		await user.click(within(dialog).getByRole("button", { name: "Confirm" }));
		await waitFor(() =>
			expect(lastPost(calls)?.body).toEqual({
				slice: "B3a",
				heads: { backend: "abc1234" },
			}),
		);
	});

	it("JSON-escapes quotes in the bounce reason preview", async () => {
		mockApi(base);
		renderAt("/queue");
		const user = userEvent.setup();
		await user.click(await screen.findByRole("button", { name: "Bounce" }));
		const dialog = screen.getByRole("dialog");
		const input = within(dialog).getByLabelText("Reason");
		fireEvent.change(input, { target: { value: 'say "hi"' } });
		expect(dialog).toHaveTextContent(JSON.stringify('say "hi"'));
	});

	it("warns while the conductor is running", async () => {
		mockApi({ ...base, "GET /api/state": { body: state("busy") } });
		renderAt("/queue");
		const user = userEvent.setup();
		await user.click(await screen.findByRole("button", { name: "Bounce" }));
		expect(screen.getByRole("dialog")).toHaveTextContent(
			"The conductor is running and may act on this too.",
		);
	});
});
