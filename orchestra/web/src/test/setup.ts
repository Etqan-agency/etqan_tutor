import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { afterEach, beforeEach, vi } from "vitest";
import { resetToken } from "@/api/client";

/** A controllable EventSource: tests call `FakeEventSource.last.emit("ledger")`. */
export class FakeEventSource {
	static last: FakeEventSource | null = null;
	onopen: (() => void) | null = null;
	onerror: (() => void) | null = null;
	private listeners = new Map<string, Array<() => void>>();
	readonly url: string;
	constructor(url: string) {
		this.url = url;
		FakeEventSource.last = this;
	}
	addEventListener(type: string, listener: () => void) {
		this.listeners.set(type, [...(this.listeners.get(type) ?? []), listener]);
	}
	emit(type: string) {
		for (const listener of this.listeners.get(type) ?? []) listener();
	}
	close() {}
}

beforeEach(() => {
	vi.stubGlobal("EventSource", FakeEventSource);
	const meta = document.createElement("meta");
	meta.name = "orchestra-token";
	meta.content = "test-token";
	document.head.append(meta);
	resetToken();
});

afterEach(() => {
	cleanup();
	document.head.querySelector('meta[name="orchestra-token"]')?.remove();
	vi.unstubAllGlobals();
	vi.restoreAllMocks();
});
