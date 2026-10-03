import { useState } from "react";
import { post } from "@/api/client";
import { useOrchestraState } from "@/api/queries";
import { ActionDialog } from "@/ui/ActionDialog";
import { Card } from "@/ui/Card";
import { ErrorBox } from "@/ui/ErrorBox";
import { Field, inputClass } from "@/ui/Field";

function AddDecision({ codes }: { codes: string[] }) {
	const [phase, setPhase] = useState(codes[0]);
	const [text, setText] = useState("");
	const [affects, setAffects] = useState<string[]>([]);
	const [source, setSource] = useState("");
	const toggle = (code: string) =>
		setAffects(
			affects.includes(code)
				? affects.filter((c) => c !== code)
				: [...affects, code],
		);
	return (
		<ActionDialog
			label="Add decision"
			title="Record a shared decision"
			variant="primary"
			command={`ledger.py decide ${phase} ${JSON.stringify(text)} --affects ${affects.join(",")} --source ${JSON.stringify(source)}`}
			canSubmit={text.trim() !== "" && source.trim() !== ""}
			run={() => post("/api/decisions", { phase, text, affects, source })}
		>
			<Field label="Phase">
				<select
					className={inputClass}
					value={phase}
					onChange={(e) => setPhase(e.target.value)}
				>
					{codes.map((c) => (
						<option key={c}>{c}</option>
					))}
				</select>
			</Field>
			<Field label="Decision">
				<textarea
					className={inputClass}
					rows={3}
					value={text}
					onChange={(e) => setText(e.target.value)}
				/>
			</Field>
			<fieldset className="text-sm">
				<legend className="mb-1 font-medium">Affects</legend>
				<div className="flex flex-wrap gap-3">
					{codes.map((c) => (
						<label key={c} className="flex items-center gap-1">
							<input
								type="checkbox"
								checked={affects.includes(c)}
								onChange={() => toggle(c)}
							/>
							{c}
						</label>
					))}
				</div>
			</fieldset>
			<Field label="Source">
				<input
					className={inputClass}
					value={source}
					onChange={(e) => setSource(e.target.value)}
				/>
			</Field>
		</ActionDialog>
	);
}

export function CoordinationPage() {
	const { data, error } = useOrchestraState();
	if (error) return <ErrorBox error={error} />;
	if (!data) return <p className="text-sm text-muted-foreground">Loading…</p>;
	const { ledger } = data;
	const codes = Object.keys(ledger.phases);
	return (
		<div className="grid gap-4 lg:grid-cols-2">
			<Card title="Shared decisions" aside={<AddDecision codes={codes} />}>
				<ul className="space-y-2 text-sm">
					{ledger.shared_decisions.map((d) => (
						<li key={d.id}>
							<span className="font-medium">{`${d.id} · ${d.phase}`}</span>{" "}
							<span>{d.decision}</span>
							<span className="block text-muted-foreground">{`affects ${d.affects.join(", ") || "—"} · ${d.source}`}</span>
						</li>
					))}
				</ul>
			</Card>
			<Card title="Claims">
				<ul className="space-y-2 text-sm">
					{ledger.claims.map((c) => (
						<li
							key={c.target}
							className="flex items-center justify-between gap-3"
						>
							<span>
								<span className="font-mono">{c.target}</span>
								{` · ${c.phase} · ${c.reason} · since ${c.since}`}
							</span>
							<ActionDialog
								label="Force release"
								title={`Release ${c.target}`}
								variant="destructive"
								confirmWord={c.target}
								command={`ledger.py release-claim ${c.target}`}
								run={() => post("/api/claims/release", { target: c.target })}
							/>
						</li>
					))}
				</ul>
			</Card>
			<Card title="Requests">
				<ul className="space-y-2 text-sm">
					{ledger.requests.map((r) => (
						<li key={r.id} className="flex items-center justify-between gap-3">
							<span>{`${r.id} · ${r.from} → ${r.to_owner} · ${r.app}: ${r.what} (${r.status})`}</span>
							{r.status === "open" && (
								<ActionDialog
									label="Mark done"
									title={`Mark ${r.id} done`}
									command={`ledger.py request-done ${r.id}`}
									run={() => post(`/api/requests/${r.id}/done`)}
								/>
							)}
						</li>
					))}
				</ul>
			</Card>
			<Card title="Ownership">
				<ul className="space-y-1 text-sm">
					{Object.entries(ledger.ownership).map(([app, owner]) => (
						<li key={app}>{`${app} → ${owner}`}</li>
					))}
				</ul>
			</Card>
		</div>
	);
}
