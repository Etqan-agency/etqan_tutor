import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import type { ComponentProps } from "react";
import { vi } from "vitest";
import { ActionDialog } from "./ActionDialog";
import { Field, inputClass } from "./Field";

function deferred<T>() {
	let resolve!: (value: T) => void;
	const promise = new Promise<T>((r) => {
		resolve = r;
	});
	return { promise, resolve };
}

function renderDialog(
	props: Partial<ComponentProps<typeof ActionDialog>> = {},
) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false } },
	});
	const run = props.run ?? vi.fn().mockResolvedValue(undefined);
	return render(
		<QueryClientProvider client={client}>
			<ActionDialog
				label="Open"
				title="Do the thing"
				command="do-the-thing"
				run={run}
				{...props}
			/>
		</QueryClientProvider>,
	);
}

describe("ActionDialog focus management", () => {
	it("focuses the first field when the dialog has one", async () => {
		renderDialog({
			children: (
				<Field label="Name">
					<input className={inputClass} />
				</Field>
			),
		});
		const user = userEvent.setup();
		await user.click(screen.getByRole("button", { name: "Open" }));
		expect(screen.getByLabelText("Name")).toHaveFocus();
	});

	it("focuses Cancel when the dialog has no fields", async () => {
		renderDialog();
		const user = userEvent.setup();
		await user.click(screen.getByRole("button", { name: "Open" }));
		expect(screen.getByRole("button", { name: "Cancel" })).toHaveFocus();
	});

	it("traps Tab inside the dialog, wrapping both directions", async () => {
		renderDialog({
			children: (
				<Field label="Name">
					<input className={inputClass} />
				</Field>
			),
		});
		const user = userEvent.setup();
		await user.click(screen.getByRole("button", { name: "Open" }));
		const field = screen.getByLabelText("Name");
		const cancel = screen.getByRole("button", { name: "Cancel" });
		const confirm = screen.getByRole("button", { name: "Confirm" });

		expect(field).toHaveFocus();
		await user.tab();
		expect(cancel).toHaveFocus();
		await user.tab();
		expect(confirm).toHaveFocus();
		await user.tab();
		expect(field).toHaveFocus();

		await user.tab({ shift: true });
		expect(confirm).toHaveFocus();
	});

	it("closes on Escape and returns focus to the button that opened it", async () => {
		renderDialog();
		const user = userEvent.setup();
		const opener = screen.getByRole("button", { name: "Open" });
		await user.click(opener);
		expect(screen.getByRole("dialog")).toBeInTheDocument();
		await user.keyboard("{Escape}");
		expect(screen.queryByRole("dialog")).toBeNull();
		expect(opener).toHaveFocus();
	});

	it("does nothing on Escape while a submit is pending", async () => {
		const work = deferred<void>();
		renderDialog({ run: vi.fn().mockReturnValue(work.promise) });
		const user = userEvent.setup();
		await user.click(screen.getByRole("button", { name: "Open" }));
		await user.click(screen.getByRole("button", { name: "Confirm" }));
		expect(
			await screen.findByRole("button", { name: "Working…" }),
		).toBeInTheDocument();

		await user.keyboard("{Escape}");
		expect(screen.getByRole("dialog")).toBeInTheDocument();

		work.resolve();
		await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
	});

	it("disables Confirm while pending so a second click cannot double-submit", async () => {
		const work = deferred<void>();
		const run = vi.fn().mockReturnValue(work.promise);
		renderDialog({ run });
		const user = userEvent.setup();
		await user.click(screen.getByRole("button", { name: "Open" }));
		await user.click(screen.getByRole("button", { name: "Confirm" }));
		const confirm = await screen.findByRole("button", { name: "Working…" });
		expect(confirm).toBeDisabled();

		await user.click(confirm);
		expect(run).toHaveBeenCalledTimes(1);

		work.resolve();
		await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
	});
});
