import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { createMemoryHistory, RouterProvider } from "@tanstack/react-router";
import { render } from "@testing-library/react";
import { makeRouter } from "@/router";

export function renderAt(path: string) {
	const client = new QueryClient({
		defaultOptions: { queries: { retry: false } },
	});
	const router = makeRouter(createMemoryHistory({ initialEntries: [path] }));
	const utils = render(
		<QueryClientProvider client={client}>
			<RouterProvider router={router} />
		</QueryClientProvider>,
	);
	return { ...utils, client, router };
}
