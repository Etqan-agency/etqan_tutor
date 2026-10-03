import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { vi } from "vitest";
import { lastPost, mockApi } from "@/test/api";
import { makeState } from "@/test/fixtures";
import { renderAt } from "@/test/render";

const writes: string[] = [];
vi.mock("@xterm/xterm", () => ({
	Terminal: class {
		open() {}
		reset() {
			writes.length = 0;
		}
		write(text: string) {
			writes.push(text);
		}
		dispose() {}
	},
}));

function state() {
	return makeState(
		(l) => {
			Object.assign(l.phases.B3, {
				status: "build",
				slot: 2,
				worktree: "/wt/b3",
				branch: "feat/b3a-money",
				session: "ab12",
			});
			Object.assign(l.phases.B2, {
				status: "build",
				slot: 1,
				worktree: "/wt/b2",
			});
			l.slices.B3a = {
				phase: "B3",
				status: "merged",
				requires: [],
				plan_number: 16,
				spec: null,
				plan: null,
				prs: "https://github.com/x/y/pull/9",
				bounces: 0,
			};
			l.slices.B3b = {
				phase: "B3",
				status: "build",
				requires: ["B3a", "B2a"],
				plan_number: 17,
				spec: null,
				plan: null,
				prs: null,
				bounces: 1,
			};
		},
		{
			sessions: {
				B3: { id: "ab12", state: "busy" },
				conductor: { id: null, state: "none" },
			},
			stacks: { B3: true },
		},
	);
}

const routes = (extra = {}) => ({
	"GET /api/state": { body: state() },
	"GET /api/ci": { body: { master: null, prs: [] } },
	"GET /api/phases/B3/log": { body: { text: "\u001b[1mhello\u001b[0m" } },
	...extra,
});

describe("PhasePage", () => {
	it("shows the phase, its slices with their requirements, and its live log", async () => {
		mockApi(routes());
		renderAt("/phase/B3");
		expect(
			await screen.findByRole("heading", { name: "B3 · Money depth" }),
		).toBeInTheDocument();
		expect(screen.getByText("feat/b3a-money")).toBeInTheDocument();
		const b3b = screen.getByRole("row", { name: /B3b/ });
		expect(within(b3b).getByText("B3a ✓")).toBeInTheDocument();
		expect(within(b3b).getByText("B2a ✗")).toBeInTheDocument();
		expect(screen.getByRole("link", { name: "#9" })).toHaveAttribute(
			"href",
			"https://github.com/x/y/pull/9",
		);
		await vi.waitFor(() => expect(writes.join("")).toContain("hello"));
	});

	it("moves the phase to a free slot", async () => {
		const calls = mockApi(
			routes({ "POST /api/phases/B3/slot": { body: { ok: true } } }),
		);
		renderAt("/phase/B3");
		const user = userEvent.setup();
		await user.click(await screen.findByRole("button", { name: "Move slot" }));
		const dialog = screen.getByRole("dialog");
		const options = within(within(dialog).getByLabelText("New slot"))
			.getAllByRole("option")
			.map((o) => o.textContent);
		expect(options).toEqual(["Release the slot", "3", "4"]);
		await user.selectOptions(within(dialog).getByLabelText("New slot"), "4");
		await user.click(within(dialog).getByRole("button", { name: "Confirm" }));
		await waitFor(() =>
			expect(lastPost(calls)).toMatchObject({
				path: "/api/phases/B3/slot",
				body: { slot: 4 },
			}),
		);
	});

	it("tears down only after the phase code is typed", async () => {
		const calls = mockApi(
			routes({
				"POST /api/phases/B3/teardown": {
					body: { ok: true, status: "waiting-deps" },
				},
			}),
		);
		renderAt("/phase/B3");
		const user = userEvent.setup();
		await user.click(await screen.findByRole("button", { name: "Tear down" }));
		const dialog = screen.getByRole("dialog");
		const confirm = within(dialog).getByRole("button", { name: "Confirm" });
		expect(confirm).toBeDisabled();
		await user.type(within(dialog).getByLabelText("Type B3 to confirm"), "B3");
		await user.click(confirm);
		await waitFor(() =>
			expect(lastPost(calls)).toMatchObject({
				path: "/api/phases/B3/teardown",
				body: { confirm: "B3" },
			}),
		);
	});

	it("pauses, sets status and switches the stack", async () => {
		const calls = mockApi(
			routes({
				"POST /api/phases/B3/status": { body: { ok: true } },
				"POST /api/phases/B3/stack": { body: { ok: true } },
			}),
		);
		renderAt("/phase/B3");
		const user = userEvent.setup();
		await user.click(await screen.findByRole("button", { name: "Pause" }));
		await user.click(
			within(screen.getByRole("dialog")).getByRole("button", {
				name: "Confirm",
			}),
		);
		await waitFor(() =>
			expect(lastPost(calls)?.body).toEqual({ status: "paused" }),
		);
		await user.click(screen.getByRole("button", { name: "Stack down" }));
		await user.click(
			within(screen.getByRole("dialog")).getByRole("button", {
				name: "Confirm",
			}),
		);
		await waitFor(() =>
			expect(lastPost(calls)).toMatchObject({
				path: "/api/phases/B3/stack",
				body: { up: false },
			}),
		);
	});

	it("says so for an unknown phase", async () => {
		mockApi(routes());
		renderAt("/phase/B99");
		expect(await screen.findByText("No phase B99.")).toBeInTheDocument();
	});

	it("keeps Tear down enabled for a waiting-deps phase with no worktree (an unrecorded launch)", async () => {
		mockApi({
			"GET /api/state": {
				body: makeState((l) => {
					Object.assign(l.phases.B2, {
						status: "waiting-deps",
						slot: null,
						worktree: null,
					});
				}),
			},
			"GET /api/ci": { body: { master: null, prs: [] } },
			"GET /api/phases/B2/log": { body: { text: "" } },
		});
		renderAt("/phase/B2");
		expect(
			await screen.findByRole("button", { name: "Tear down" }),
		).toBeEnabled();
	});

	it("names the exact teardown commands for a launched phase with a session", async () => {
		mockApi(routes());
		renderAt("/phase/B3");
		const user = userEvent.setup();
		await user.click(await screen.findByRole("button", { name: "Tear down" }));
		const dialog = screen.getByRole("dialog");
		expect(dialog.querySelector("pre")?.textContent).toBe(
			"claude stop ab12\nteardown-phase.sh B3\nledger.py phase B3 --status waiting-deps --slot 0 --worktree none --branch none --session none",
		);
	});

	it("omits the claude stop line for an unlaunched phase with no session", async () => {
		mockApi({
			"GET /api/state": { body: makeState() },
			"GET /api/ci": { body: { master: null, prs: [] } },
			"GET /api/phases/B2/log": { body: { text: "" } },
		});
		renderAt("/phase/B2");
		const user = userEvent.setup();
		await user.click(await screen.findByRole("button", { name: "Tear down" }));
		const dialog = screen.getByRole("dialog");
		expect(dialog.querySelector("pre")?.textContent).toBe(
			"teardown-phase.sh B2 (only if an unrecorded worktree exists)\nledger.py phase B2 --status waiting-deps --slot 0 --worktree none --branch none --session none",
		);
	});

	it("resets per-phase control state when navigating between phases", async () => {
		mockApi({
			"GET /api/state": { body: state() },
			"GET /api/ci": { body: { master: null, prs: [] } },
			"GET /api/phases/B3/log": { body: { text: "" } },
			"GET /api/phases/B2/log": { body: { text: "" } },
		});
		const { router } = renderAt("/phase/B3");
		const user = userEvent.setup();
		await user.click(await screen.findByRole("button", { name: "Set status" }));
		await user.selectOptions(
			within(screen.getByRole("dialog")).getByLabelText("Status"),
			"paused",
		);
		await user.click(
			within(screen.getByRole("dialog")).getByRole("button", {
				name: "Cancel",
			}),
		);
		await router.navigate({ to: "/phase/$code", params: { code: "B2" } });
		await user.click(await screen.findByRole("button", { name: "Set status" }));
		expect(
			within(screen.getByRole("dialog")).getByLabelText("Status"),
		).toHaveValue("build");
	});
});
