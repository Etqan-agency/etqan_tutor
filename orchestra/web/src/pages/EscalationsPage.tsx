import { type ReactNode, useState } from "react";
import { post } from "@/api/client";
import { useOrchestraState } from "@/api/queries";
import type { Escalation } from "@/api/types";
import { ActionDialog } from "@/ui/ActionDialog";
import { Badge } from "@/ui/Badge";
import { ErrorBox } from "@/ui/ErrorBox";
import { Field, inputClass } from "@/ui/Field";

function Answer({ escalation }: { escalation: Escalation }) {
	const [answer, setAnswer] = useState("");
	return (
		<ActionDialog
			label="Answer"
			title={`Answer ${escalation.id}`}
			variant="primary"
			canSubmit={answer.trim() !== ""}
			command={`ledger.py resolve ${escalation.id} ${JSON.stringify(answer)}`}
			run={() => post(`/api/escalations/${escalation.id}/resolve`, { answer })}
		>
			<p className="text-sm">{escalation.question}</p>
			<Field label="Your answer">
				<textarea
					className={inputClass}
					rows={4}
					value={answer}
					onChange={(e) => setAnswer(e.target.value)}
				/>
			</Field>
		</ActionDialog>
	);
}

function Row({
	escalation,
	children,
}: {
	escalation: Escalation;
	children?: ReactNode;
}) {
	return (
		<li className="rounded-md border border-border p-3 text-sm">
			<div className="flex items-center gap-2">
				<span className="font-medium">{escalation.id}</span>
				<Badge>{escalation.phase}</Badge>
				<Badge tone="warning">{escalation.kind}</Badge>
				<span className="ml-auto">{children}</span>
			</div>
			<p className="mt-2">{escalation.question}</p>
			{escalation.answer && (
				<p className="mt-1 text-muted-foreground">{escalation.answer}</p>
			)}
		</li>
	);
}

export function EscalationsPage() {
	const { data, error } = useOrchestraState();
	if (error) return <ErrorBox error={error} />;
	if (!data) return <p className="text-sm text-muted-foreground">Loading…</p>;
	const open = data.ledger.escalations.filter((e) => e.status === "open");
	const resolved = data.ledger.escalations.filter(
		(e) => e.status === "resolved",
	);
	return (
		<div className="space-y-6">
			<h1 className="text-xl font-semibold">Escalations</h1>
			<section aria-label="Open">
				<h2 className="mb-3 font-semibold">Open</h2>
				{open.length === 0 ? (
					<p className="text-sm text-muted-foreground">
						Nothing is waiting for you.
					</p>
				) : (
					<ul className="space-y-2">
						{open.map((e) => (
							<Row key={e.id} escalation={e}>
								<Answer escalation={e} />
							</Row>
						))}
					</ul>
				)}
			</section>
			<section aria-label="Resolved">
				<h2 className="mb-3 font-semibold">Resolved</h2>
				<ul className="space-y-2">
					{resolved.map((e) => (
						<Row key={e.id} escalation={e} />
					))}
				</ul>
			</section>
		</div>
	);
}
