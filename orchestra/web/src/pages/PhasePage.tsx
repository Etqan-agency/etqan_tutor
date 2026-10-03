import { useParams } from "@tanstack/react-router";
import { useOrchestraState } from "@/api/queries";
import { PhaseControls } from "@/components/PhaseControls";
import { SessionControls } from "@/components/SessionControls";
import { SessionLog } from "@/components/SessionLog";
import { SlicesTable } from "@/components/SlicesTable";
import { Badge } from "@/ui/Badge";
import { Button } from "@/ui/Button";
import { Card } from "@/ui/Card";
import { ErrorBox } from "@/ui/ErrorBox";
import { phaseTone, sessionTone } from "@/ui/tones";

export function PhasePage() {
	const { code } = useParams({ from: "/phase/$code" });
	const { data, error } = useOrchestraState();
	if (error) return <ErrorBox error={error} />;
	if (!data) return <p className="text-sm text-muted-foreground">Loading…</p>;
	const phase = data.ledger.phases[code];
	if (!phase) return <p>{`No phase ${code}.`}</p>;
	const session = data.sessions[code];
	return (
		<div className="space-y-6">
			<header className="space-y-2">
				<h1 className="text-xl font-semibold">{`${code} · ${phase.title}`}</h1>
				<div className="flex flex-wrap items-center gap-2 text-sm">
					<Badge tone={phaseTone[phase.status]}>{phase.status}</Badge>
					<Badge
						tone={sessionTone[session?.state ?? "none"]}
					>{`session ${session?.state ?? "none"}`}</Badge>
					<span>{`Slot ${phase.slot ?? "—"}`}</span>
					{phase.branch && <span className="font-mono">{phase.branch}</span>}
					{phase.worktree && (
						<Button
							variant="ghost"
							size="sm"
							onClick={() =>
								navigator.clipboard?.writeText(phase.worktree ?? "")
							}
						>
							{`Copy path ${phase.worktree}`}
						</Button>
					)}
				</div>
			</header>
			<Card title="Session">
				<SessionControls key={code} who={code} session={session} />
			</Card>
			<Card title="Phase">
				<PhaseControls
					key={code}
					code={code}
					ledger={data.ledger}
					stackUp={data.stacks[code] ?? false}
				/>
			</Card>
			<Card title="Slices">
				<SlicesTable ledger={data.ledger} code={code} />
			</Card>
			<Card>
				<SessionLog key={code} who={code} />
			</Card>
		</div>
	);
}
