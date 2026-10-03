import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { lastPost, mockApi } from "@/test/api";
import { makeState } from "@/test/fixtures";
import { renderAt } from "@/test/render";

const ci = {
	master: {
		status: "completed",
		conclusion: "success",
		headSha: "abc1234",
		url: "u",
		createdAt: "t",
	},
	prs: [],
};

function launchedState() {
	return makeState(
		(l) => {
			Object.assign(l.phases.B3, {
				status: "build",
				slot: 2,
				worktree: "/wt/b3",
				current_slice: "B3a",
				current_task: "Task 4",
				session: "ab12",
			});
			l.queue.push("B3b");
			l.in_flight = "B3a";
		},
		{
			eligible: { free: 3, phases: ["B2", "B8", "B9"] },
			sessions: {
				B3: { id: "ab12", state: "busy" },
				conductor: { id: null, state: "none" },
			},
			stacks: { B3: true },
		},
	);
}

describe("Overview", () => {
	it("shows each slot, the conductor, the queue and CI", async () => {
		mockApi({
			"GET /api/state": { body: launchedState() },
			"GET /api/ci": { body: ci },
		});
		renderAt("/");
		const slot2 = (
			await screen.findByRole("link", { name: "B3 · Money depth" })
		).closest("section") as HTMLElement;
		expect(within(slot2).getByText("build")).toBeInTheDocument();
		expect(within(slot2).getByText("session busy")).toBeInTheDocument();
		expect(within(slot2).getByText("stack up")).toBeInTheDocument();
		expect(within(slot2).getByText("Task 4")).toBeInTheDocument();
		expect(screen.getAllByText("Free")).toHaveLength(3);
		expect(screen.getByText("In flight: B3a")).toBeInTheDocument();
		expect(screen.getByText("B3b")).toBeInTheDocument();
		expect(await screen.findByText("success")).toBeInTheDocument();
	});

	it("starts the conductor with the chosen mode", async () => {
		const calls = mockApi({
			"GET /api/state": { body: makeState() },
			"GET /api/ci": { body: ci },
			"POST /api/conductor/session/start": { body: { ok: true, id: "cd34" } },
		});
		renderAt("/");
		const user = userEvent.setup();
		await user.click(
			await screen.findByRole("button", { name: "Start conductor" }),
		);
		const dialog = screen.getByRole("dialog");
		expect(
			within(dialog).getByText("start-session.sh conductor --mode auto"),
		).toBeInTheDocument();
		await user.selectOptions(
			within(dialog).getByLabelText("Permission mode"),
			"plan",
		);
		expect(
			within(dialog).queryByRole("option", { name: "bypassPermissions" }),
		).toBeNull();
		await user.click(within(dialog).getByRole("button", { name: "Confirm" }));
		const start = calls.find((c) => c.method === "POST");
		expect(start?.body).toEqual({ mode: "plan", model: "", effort: "" });
		expect(screen.queryByRole("dialog")).toBeNull();
	});

	it("launches an eligible phase into a free slot and shows a failure's output", async () => {
		const calls = mockApi({
			"GET /api/state": { body: launchedState() },
			"GET /api/ci": { body: ci },
			"POST /api/phases/B8/launch": {
				status: 500,
				body: { ok: false, exit_code: 3, output_tail: "fatal: boom" },
			},
		});
		renderAt("/");
		const user = userEvent.setup();
		await user.click(await screen.findByRole("button", { name: "Launch B8" }));
		const dialog = screen.getByRole("dialog");
		expect(within(dialog).getByLabelText("Branch suffix")).toHaveValue(
			"b8a-marketing-extras",
		);
		const slots = within(within(dialog).getByLabelText("Slot"))
			.getAllByRole("option")
			.map((o) => o.textContent);
		expect(slots).toEqual(["1", "3", "4"]);
		await user.click(within(dialog).getByRole("button", { name: "Confirm" }));
		await waitFor(() =>
			expect(lastPost(calls)?.body).toEqual({
				suffix: "b8a-marketing-extras",
				slot: 1,
				mode: "auto",
			}),
		);
		expect(await within(dialog).findByRole("alert")).toHaveTextContent(
			"fatal: boom",
		);
	});
});
