import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { lastPost, mockApi } from "@/test/api";
import { makeState } from "@/test/fixtures";
import { renderAt } from "@/test/render";

describe("CoordinationPage", () => {
	it("adds a decision, force-releases a claim and closes a request", async () => {
		const state = makeState((l) => {
			l.shared_decisions.push({
				id: "D1",
				phase: "B2",
				decision: "R7 dropped",
				affects: ["B4"],
				source: "PO-2",
			});
			l.claims.push({
				target: "etqan.catalogue.models",
				phase: "B3",
				reason: "price",
				since: "2026-10-03T10:00:00+00:00",
			});
			l.requests.push({
				id: "R1",
				from: "B4",
				app: "scheduling",
				to_owner: "B2",
				what: "a field",
				status: "open",
			});
		});
		const calls = mockApi({
			"GET /api/state": { body: state },
			"GET /api/ci": { body: { master: null, prs: [] } },
			"POST /api/decisions": { body: { ok: true, id: "D2" } },
			"POST /api/claims/release": { body: { ok: true } },
			"POST /api/requests/R1/done": { body: { ok: true } },
		});
		renderAt("/coordination");
		expect(await screen.findByText("R7 dropped")).toBeInTheDocument();
		expect(screen.getByText("scheduling → B2")).toBeInTheDocument();
		const user = userEvent.setup();

		await user.click(screen.getByRole("button", { name: "Add decision" }));
		let dialog = screen.getByRole("dialog");
		await user.selectOptions(within(dialog).getByLabelText("Phase"), "B3");
		await user.type(
			within(dialog).getByLabelText("Decision"),
			"Wallet on Student",
		);
		await user.click(within(dialog).getByRole("checkbox", { name: "B4" }));
		await user.type(within(dialog).getByLabelText("Source"), "audit §2");
		await user.click(within(dialog).getByRole("button", { name: "Confirm" }));
		await waitFor(() =>
			expect(lastPost(calls)?.body).toEqual({
				phase: "B3",
				text: "Wallet on Student",
				affects: ["B4"],
				source: "audit §2",
			}),
		);

		await user.click(screen.getByRole("button", { name: "Force release" }));
		dialog = screen.getByRole("dialog");
		await user.type(
			within(dialog).getByLabelText("Type etqan.catalogue.models to confirm"),
			"etqan.catalogue.models",
		);
		await user.click(within(dialog).getByRole("button", { name: "Confirm" }));
		await waitFor(() =>
			expect(lastPost(calls)?.body).toEqual({
				target: "etqan.catalogue.models",
			}),
		);

		await user.click(screen.getByRole("button", { name: "Mark done" }));
		await user.click(
			within(screen.getByRole("dialog")).getByRole("button", {
				name: "Confirm",
			}),
		);
		await waitFor(() =>
			expect(lastPost(calls)?.path).toBe("/api/requests/R1/done"),
		);
	});
});
