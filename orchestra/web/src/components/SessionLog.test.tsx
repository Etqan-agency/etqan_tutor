import { render } from "@testing-library/react";
import { vi } from "vitest";
import { SessionLog } from "./SessionLog";

let resets = 0;
const writes: string[] = [];
vi.mock("@xterm/xterm", () => ({
	Terminal: class {
		open() {}
		reset() {
			resets++;
			writes.length = 0;
		}
		write(text: string) {
			writes.push(text);
		}
		dispose() {}
	},
}));

let logData: { text: string } | undefined;
vi.mock("@/api/queries", () => ({
	useLog: () => ({ data: logData }),
}));

describe("SessionLog", () => {
	beforeEach(() => {
		resets = 0;
		writes.length = 0;
	});

	it("skips rewriting the terminal when the log text is unchanged since the last write", () => {
		logData = { text: "same" };
		const { rerender } = render(<SessionLog who="B3" />);
		expect(writes.join("")).toContain("same");
		expect(resets).toBe(1);

		// A fresh object with the same text, as a refetch would yield.
		logData = { text: "same" };
		rerender(<SessionLog who="B3" />);
		expect(resets).toBe(1);

		// Genuinely new text still rewrites.
		logData = { text: "different" };
		rerender(<SessionLog who="B3" />);
		expect(resets).toBe(2);
		expect(writes.join("")).toContain("different");
	});
});
