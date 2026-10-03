import { vi } from "vitest";

type Result = { status?: number; body: unknown };
type Route = Result | ((body: unknown) => Result);
export type Call = {
	method: string;
	path: string;
	body: unknown;
	headers: Record<string, string>;
};

/** Replace fetch with a table of `"METHOD /path"` → response; returns the calls made. */
export function mockApi(routes: Record<string, Route>): Call[] {
	const calls: Call[] = [];
	vi.stubGlobal(
		"fetch",
		vi.fn(async (input: RequestInfo | URL, init: RequestInit = {}) => {
			const method = (init.method ?? "GET").toUpperCase();
			const path = String(input);
			const body = init.body ? JSON.parse(String(init.body)) : undefined;
			calls.push({
				method,
				path,
				body,
				headers: Object.fromEntries(new Headers(init.headers).entries()),
			});
			const route = routes[`${method} ${path}`];
			if (route === undefined) {
				return new Response(
					JSON.stringify({ error: `no mock for ${method} ${path}` }),
					{ status: 404 },
				);
			}
			const result = typeof route === "function" ? route(body) : route;
			return new Response(JSON.stringify(result.body), {
				status: result.status ?? 200,
				headers: { "Content-Type": "application/json" },
			});
		}),
	);
	return calls;
}

/** The last write: after a successful action the page refetches, so the last call is a GET. */
export const lastPost = (calls: Call[]) =>
	calls.filter((c) => c.method === "POST").at(-1);
