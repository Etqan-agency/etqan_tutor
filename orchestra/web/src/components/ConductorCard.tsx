import type { State } from "@/api/types";
import { Badge } from "@/ui/Badge";
import { Card } from "@/ui/Card";
import { sessionTone } from "@/ui/tones";
import { SessionControls } from "./SessionControls";

export function ConductorCard({ state }: { state: State }) {
	const session = state.sessions.conductor;
	const current = session?.state ?? "none";
	return (
		<Card
			title="Conductor"
			aside={<Badge tone={sessionTone[current]}>{`session ${current}`}</Badge>}
		>
			<p className="mb-3 text-sm text-muted-foreground">
				Merges the queue and starts eligible phases on its own.
			</p>
			<SessionControls who="conductor" session={session} />
		</Card>
	);
}
