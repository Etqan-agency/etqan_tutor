import { Link } from "@tanstack/react-router";
import { SLOTS } from "@/api/queries";
import type { Phase, Session, State } from "@/api/types";
import { Badge } from "@/ui/Badge";
import { Card } from "@/ui/Card";
import { phaseTone, sessionTone } from "@/ui/tones";

function SlotCard({
	slot,
	code,
	phase,
	session,
	stackUp,
}: {
	slot: number;
	code: string;
	phase: Phase;
	session?: Session;
	stackUp: boolean;
}) {
	const state = session?.state ?? "none";
	return (
		<Card
			title={
				<Link
					to="/phase/$code"
					params={{ code }}
					className="hover:underline"
				>{`${code} · ${phase.title}`}</Link>
			}
			aside={`Slot ${slot}`}
		>
			<div className="flex flex-wrap gap-2">
				<Badge tone={phaseTone[phase.status]}>{phase.status}</Badge>
				<Badge tone={sessionTone[state]}>{`session ${state}`}</Badge>
				<Badge
					tone={stackUp ? "success" : "neutral"}
				>{`stack ${stackUp ? "up" : "down"}`}</Badge>
			</div>
			<dl className="mt-3 grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-sm">
				<dt className="text-muted-foreground">Slice</dt>
				<dd>{phase.current_slice ?? "—"}</dd>
				<dt className="text-muted-foreground">Task</dt>
				<dd>{phase.current_task ?? "—"}</dd>
			</dl>
		</Card>
	);
}

export function SlotCards({ state }: { state: State }) {
	const bySlot = new Map<number, string>();
	for (const [code, phase] of Object.entries(state.ledger.phases)) {
		if (phase.slot !== null && phase.status !== "merged")
			bySlot.set(phase.slot, code);
	}
	return (
		<div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
			{SLOTS.map((slot) => {
				const code = bySlot.get(slot);
				return code ? (
					<SlotCard
						key={slot}
						slot={slot}
						code={code}
						phase={state.ledger.phases[code]}
						session={state.sessions[code]}
						stackUp={state.stacks[code] ?? false}
					/>
				) : (
					<Card key={slot} title={`Slot ${slot}`}>
						<p className="text-sm text-muted-foreground">Free</p>
					</Card>
				);
			})}
		</div>
	);
}
