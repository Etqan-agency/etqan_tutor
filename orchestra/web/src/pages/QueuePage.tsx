import { useState } from "react";
import { post } from "@/api/client";
import { flying, inFlightLabel } from "@/api/inFlight";
import { useOrchestraState } from "@/api/queries";
import { ActionDialog } from "@/ui/ActionDialog";
import { Card } from "@/ui/Card";
import { ErrorBox } from "@/ui/ErrorBox";
import { Field, inputClass } from "@/ui/Field";

const REPOS = ["backend", "dashboard", "marketing", "meta"];
const SHA = /^[0-9a-f]{7,40}$/;

function Bounce({ sid, warning }: { sid: string; warning?: string }) {
	const [reason, setReason] = useState("");
	return (
		<ActionDialog
			label="Bounce"
			title={`Bounce ${sid}`}
			warning={warning}
			command={`ledger.py bounce ${sid} --reason ${JSON.stringify(reason)}`}
			canSubmit={reason.trim() !== ""}
			run={() => post("/api/queue/bounce", { slice: sid, reason })}
		>
			<Field label="Reason">
				<input
					className={inputClass}
					value={reason}
					onChange={(e) => setReason(e.target.value)}
				/>
			</Field>
		</ActionDialog>
	);
}

function MarkMerged({ sid, warning }: { sid: string; warning?: string }) {
	const [heads, setHeads] = useState<Record<string, string>>({});
	const given = Object.fromEntries(
		Object.entries(heads).filter(([, sha]) => sha !== ""),
	);
	const valid =
		Object.keys(given).length > 0 &&
		Object.values(given).every((sha) => SHA.test(sha));
	return (
		<ActionDialog
			label="Mark merged"
			title={`Mark ${sid} merged`}
			variant="primary"
			warning={warning}
			confirmWord={sid}
			command={`ledger.py merged ${sid} ${Object.entries(given)
				.map(([r, s]) => `--head ${r}=${s}`)
				.join(" ")}`}
			canSubmit={valid}
			run={() => post("/api/queue/merged", { slice: sid, heads: given })}
		>
			{REPOS.map((repo) => (
				<Field key={repo} label={`${repo} head`}>
					<input
						className={inputClass}
						value={heads[repo] ?? ""}
						placeholder="merged commit (leave empty if untouched)"
						onChange={(e) =>
							setHeads({ ...heads, [repo]: e.target.value.trim() })
						}
					/>
				</Field>
			))}
		</ActionDialog>
	);
}

export function QueuePage() {
	const { data, error } = useOrchestraState();
	if (error) return <ErrorBox error={error} />;
	if (!data) return <p className="text-sm text-muted-foreground">Loading…</p>;
	const { ledger } = data;
	const conductor = data.sessions.conductor?.state;
	const warning =
		conductor === "busy" || conductor === "idle"
			? "The conductor is running and may act on this too."
			: undefined;
	const inFlight = flying(ledger);
	return (
		<div className="space-y-6">
			<Card title={`In flight: ${inFlightLabel(ledger)}`}>
				{inFlight.length > 0 ? (
					<div className="space-y-4">
						{inFlight.map((sid) => (
							<section key={sid} aria-label={sid} className="space-y-3 text-sm">
								{inFlight.length > 1 && <p className="font-medium">{sid}</p>}
								<p className="text-muted-foreground">
									{ledger.slices[sid]?.prs ?? "No PRs recorded yet."}
								</p>
								<div className="flex gap-2">
									<MarkMerged sid={sid} warning={warning} />
									<Bounce sid={sid} warning={warning} />
								</div>
							</section>
						))}
					</div>
				) : (
					<ActionDialog
						label="Next"
						title="Put the next slice in flight"
						warning={warning}
						command="ledger.py next"
						disabled={ledger.queue.length === 0}
						run={() => post("/api/queue/next")}
					/>
				)}
			</Card>
			<Card title="Queued">
				{ledger.queue.length === 0 ? (
					<p className="text-sm text-muted-foreground">Nothing queued.</p>
				) : (
					<ol className="space-y-2">
						{ledger.queue.map((sid, index) => (
							<li
								key={sid}
								aria-label={sid}
								className="flex items-center justify-between gap-3 text-sm"
							>
								<span>{`${index + 1}. ${sid}`}</span>
								<span className="flex gap-2">
									<ActionDialog
										label="Move up"
										title={`Move ${sid} up`}
										warning={warning}
										disabled={index === 0}
										command={`ledger.py reorder ${sid} up`}
										run={() =>
											post("/api/queue/reorder", {
												slice: sid,
												direction: "up",
											})
										}
									/>
									<ActionDialog
										label="Move down"
										title={`Move ${sid} down`}
										warning={warning}
										disabled={index === ledger.queue.length - 1}
										command={`ledger.py reorder ${sid} down`}
										run={() =>
											post("/api/queue/reorder", {
												slice: sid,
												direction: "down",
											})
										}
									/>
								</span>
							</li>
						))}
					</ol>
				)}
			</Card>
		</div>
	);
}
