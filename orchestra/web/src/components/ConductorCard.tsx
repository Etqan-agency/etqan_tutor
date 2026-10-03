import { useState } from "react";
import type { State } from "@/api/types";
import { Badge } from "@/ui/Badge";
import { Button } from "@/ui/Button";
import { Card } from "@/ui/Card";
import { sessionTone } from "@/ui/tones";
import { SessionControls } from "./SessionControls";
import { SessionLog } from "./SessionLog";

export function ConductorCard({ state }: { state: State }) {
	const session = state.sessions.conductor;
	const current = session?.state ?? "none";
	const [showLog, setShowLog] = useState(false);
	return (
		<Card
			title="Conductor"
			aside={<Badge tone={sessionTone[current]}>{`session ${current}`}</Badge>}
		>
			<p className="mb-3 text-sm text-muted-foreground">
				Merges the queue and starts eligible phases on its own.
			</p>
			<SessionControls who="conductor" session={session} />
			<div className="mt-3">
				<Button
					variant="ghost"
					size="sm"
					onClick={() => setShowLog((shown) => !shown)}
				>
					{showLog ? "Hide output" : "Show output"}
				</Button>
				{showLog && (
					<div className="mt-2">
						<SessionLog key="conductor" who="conductor" />
					</div>
				)}
			</div>
		</Card>
	);
}
