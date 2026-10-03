import { useState } from "react";
import { post } from "@/api/client";
import type { Session } from "@/api/types";
import { ActionDialog } from "@/ui/ActionDialog";
import { Button } from "@/ui/Button";
import { Field, inputClass } from "@/ui/Field";

const MODES = ["auto", "acceptEdits", "manual", "plan", "dontAsk"];
const EFFORTS = ["", "low", "medium", "high", "xhigh", "max"];

function base(who: string) {
	return who === "conductor"
		? "/api/conductor/session"
		: `/api/phases/${who}/session`;
}

export function ModeField({
	value,
	onChange,
}: {
	value: string;
	onChange: (mode: string) => void;
}) {
	return (
		<Field label="Permission mode">
			<select
				className={inputClass}
				value={value}
				onChange={(e) => onChange(e.target.value)}
			>
				{MODES.map((m) => (
					<option key={m}>{m}</option>
				))}
			</select>
		</Field>
	);
}

/** Start / Stop / Restart a phase's (or the conductor's) background session. */
export function SessionControls({
	who,
	session,
}: {
	who: string;
	session: Session | undefined;
}) {
	const [mode, setMode] = useState("auto");
	const [model, setModel] = useState("");
	const [effort, setEffort] = useState("");
	const state = session?.state ?? "none";
	const running = state === "busy" || state === "idle";
	const name = who === "conductor" ? "conductor" : who;
	const flags = [
		`--mode ${mode}`,
		model && `--model ${model}`,
		effort && `--effort ${effort}`,
	]
		.filter(Boolean)
		.join(" ");
	return (
		<div className="flex flex-wrap items-center gap-2">
			<ActionDialog
				label={`Start ${name}`}
				title={`Start the ${name} session`}
				variant="primary"
				disabled={running}
				command={`start-session.sh ${who} ${flags}`}
				run={() => post(`${base(who)}/start`, { mode, model, effort })}
			>
				<ModeField value={mode} onChange={setMode} />
				<Field label="Model (optional)">
					<input
						className={inputClass}
						value={model}
						placeholder="session default"
						onChange={(e) => setModel(e.target.value.trim())}
					/>
				</Field>
				<Field label="Effort (optional)">
					<select
						className={inputClass}
						value={effort}
						onChange={(e) => setEffort(e.target.value)}
					>
						{EFFORTS.map((e) => (
							<option key={e} value={e}>
								{e || "session default"}
							</option>
						))}
					</select>
				</Field>
			</ActionDialog>
			<ActionDialog
				label={`Stop ${name}`}
				title={`Stop the ${name} session`}
				variant="destructive"
				disabled={!running}
				command={`claude stop ${session?.id ?? ""}`}
				run={() => post(`${base(who)}/stop`)}
			/>
			<ActionDialog
				label={`Restart ${name}`}
				title={`Restart the ${name} session`}
				disabled={state === "none"}
				command={
					running
						? `claude respawn ${session?.id}`
						: `claude --bg --resume … (or start-session.sh ${who})`
				}
				run={() => post(`${base(who)}/restart`, { mode })}
			>
				<ModeField value={mode} onChange={setMode} />
			</ActionDialog>
			{session?.id && (
				<Button
					variant="ghost"
					size="sm"
					onClick={() =>
						navigator.clipboard?.writeText(`claude attach ${session.id}`)
					}
				>
					Copy attach command
				</Button>
			)}
		</div>
	);
}
