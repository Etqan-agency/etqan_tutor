import { useOrchestraState } from "@/api/queries";
import { CiPanel } from "@/components/CiPanel";
import { ConductorCard } from "@/components/ConductorCard";
import { EligiblePhases } from "@/components/EligiblePhases";
import { QueueStrip } from "@/components/QueueStrip";
import { SlotCards, WithoutSlot } from "@/components/SlotCards";
import { ErrorBox } from "@/ui/ErrorBox";

export function Overview() {
	const { data, error } = useOrchestraState();
	if (error) return <ErrorBox error={error} />;
	if (!data) return <p className="text-sm text-muted-foreground">Loading…</p>;
	return (
		<div className="space-y-6">
			<SlotCards state={data} />
			<WithoutSlot state={data} />
			<div className="grid gap-4 lg:grid-cols-3">
				<ConductorCard state={data} />
				<QueueStrip ledger={data.ledger} />
				<CiPanel />
			</div>
			<EligiblePhases state={data} />
		</div>
	);
}
