import { Link, Outlet } from "@tanstack/react-router";
import { useLiveUpdates } from "@/api/events";
import { useOrchestraState } from "@/api/queries";
import { Badge } from "@/ui/Badge";

const linkClass = "text-muted-foreground hover:text-foreground";
const active = { className: "font-semibold text-foreground" };

export function Layout() {
	const connected = useLiveUpdates();
	const { data } = useOrchestraState();
	const open =
		data?.ledger.escalations.filter((e) => e.status === "open").length ?? 0;
	return (
		<div className="min-h-screen bg-background text-foreground">
			<header className="border-b border-border bg-card">
				<div className="mx-auto flex max-w-7xl items-center gap-6 px-4 py-3">
					<span className="font-semibold">Orchestra</span>
					<nav className="flex items-center gap-4 text-sm">
						<Link
							to="/"
							className={linkClass}
							activeProps={active}
							activeOptions={{ exact: true }}
						>
							Overview
						</Link>
						<Link to="/queue" className={linkClass} activeProps={active}>
							Queue
						</Link>
						<Link to="/escalations" className={linkClass} activeProps={active}>
							Escalations{" "}
							<Badge tone={open ? "destructive" : "neutral"}>{open}</Badge>
						</Link>
						<Link to="/coordination" className={linkClass} activeProps={active}>
							Coordination
						</Link>
					</nav>
					<span className="ml-auto flex items-center gap-2 text-xs text-muted-foreground">
						<span
							aria-hidden="true"
							className={`size-2 rounded-full ${connected ? "bg-success" : "bg-destructive"}`}
						/>
						{connected ? "Live" : "Reconnecting…"}
					</span>
				</div>
			</header>
			<main className="mx-auto max-w-7xl px-4 py-6">
				<Outlet />
			</main>
		</div>
	);
}
