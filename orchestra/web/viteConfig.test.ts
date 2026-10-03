import { describe, expect, it } from "vitest";
import config from "./vite.config";

describe("vite.config", () => {
	it("binds the dev server to loopback with no foreign CORS", () => {
		expect(config.server?.host).toBe("127.0.0.1");
		expect(config.server?.allowedHosts).toEqual(["127.0.0.1", "localhost"]);
		expect(config.server?.cors).toBe(false);
	});

	it("blocks framing, since the dev server serves the page itself", () => {
		expect(config.server?.headers).toEqual({
			"X-Frame-Options": "DENY",
			"Content-Security-Policy": "frame-ancestors 'none'",
		});
	});
});
