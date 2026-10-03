import { Link } from "@tanstack/react-router";
import type { Ledger } from "@/api/types";
import { Card } from "@/ui/Card";

export function QueueStrip({ ledger }: { ledger: Ledger }) {
	return (
		<Card
			title="Merge queue"
			aside={
				<Link to="/queue" className="hover:underline">
					Open queue
				</Link>
			}
		>
			<p className="text-sm font-medium">{`In flight: ${ledger.in_flight ?? "—"}`}</p>
			{ledger.queue.length === 0 ? (
				<p className="mt-2 text-sm text-muted-foreground">Nothing queued.</p>
			) : (
				<ol className="mt-2 flex flex-wrap gap-2 text-sm">
					{ledger.queue.map((sid) => (
						<li key={sid} className="rounded-md bg-muted px-2 py-0.5">
							{sid}
						</li>
					))}
				</ol>
			)}
		</Card>
	);
}
