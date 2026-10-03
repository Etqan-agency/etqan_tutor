import {
	createRootRoute,
	createRoute,
	createRouter,
	type RouterHistory,
} from "@tanstack/react-router";
import { Layout } from "./Layout";
import { CoordinationPage } from "./pages/CoordinationPage";
import { EscalationsPage } from "./pages/EscalationsPage";
import { Overview } from "./pages/Overview";
import { PhasePage } from "./pages/PhasePage";
import { QueuePage } from "./pages/QueuePage";

const root = createRootRoute({ component: Layout });
const routeTree = root.addChildren([
	createRoute({ getParentRoute: () => root, path: "/", component: Overview }),
	createRoute({
		getParentRoute: () => root,
		path: "/phase/$code",
		component: PhasePage,
	}),
	createRoute({
		getParentRoute: () => root,
		path: "/queue",
		component: QueuePage,
	}),
	createRoute({
		getParentRoute: () => root,
		path: "/escalations",
		component: EscalationsPage,
	}),
	createRoute({
		getParentRoute: () => root,
		path: "/coordination",
		component: CoordinationPage,
	}),
]);

export function makeRouter(history?: RouterHistory) {
	return createRouter({ routeTree, history });
}

export const router = makeRouter();

declare module "@tanstack/react-router" {
	interface Register {
		router: typeof router;
	}
}
