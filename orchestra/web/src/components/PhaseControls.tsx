import { useState } from "react";
import { post } from "@/api/client";
import { freeSlots } from "@/api/queries";
import { type Ledger, PHASE_STATUSES } from "@/api/types";
import { ActionDialog } from "@/ui/ActionDialog";
import { Field, inputClass } from "@/ui/Field";

export function PhaseControls({
	code,
	ledger,
	stackUp,
}: {
	code: string;
	ledger: Ledger;
	stackUp: boolean;
}) {
	const phase = ledger.phases[code];
	const slots = freeSlots(ledger);
	const [slot, setSlot] = useState(0);
	const [status, setStatus] = useState(phase.status);
	const launched = phase.worktree !== null;
	// The ledger can lose track of a launch (worktree directory created, then the
	// write to the ledger never happened). Teardown must still be reachable then,
	// unless the phase is already merged, so an unrecorded worktree isn't stuck.
	const canTeardown = launched || phase.status !== "merged";
	const lower = code.toLowerCase();
	return (
		<div className="flex flex-wrap gap-2">
			{phase.status === "paused" ? (
				<ActionDialog
					label="Resume"
					title={`Resume ${code}`}
					command={`ledger.py phase ${code} --status build`}
					run={() => post(`/api/phases/${code}/status`, { status: "build" })}
				/>
			) : (
				<ActionDialog
					label="Pause"
					title={`Pause ${code}`}
					command={`ledger.py phase ${code} --status paused`}
					run={() => post(`/api/phases/${code}/status`, { status: "paused" })}
				/>
			)}
			<ActionDialog
				label="Set status"
				title={`Set ${code}'s status`}
				command={`ledger.py phase ${code} --status ${status}`}
				run={() => post(`/api/phases/${code}/status`, { status })}
			>
				<Field label="Status">
					<select
						className={inputClass}
						value={status}
						onChange={(e) => setStatus(e.target.value as typeof status)}
					>
						{PHASE_STATUSES.map((s) => (
							<option key={s}>{s}</option>
						))}
					</select>
				</Field>
			</ActionDialog>
			<ActionDialog
				label="Move slot"
				title={`Move ${code} to another slot`}
				disabled={!launched}
				command={
					slot === 0
						? `just stop (in ${phase.worktree})\nledger.py phase ${code} --slot 0 --status paused`
						: `just stop (in ${phase.worktree})\nledger.py phase ${code} --slot ${slot}\nstream-env.sh ${lower} ${slot} ${phase.worktree}\njust dev-backend`
				}
				run={() => post(`/api/phases/${code}/slot`, { slot })}
			>
				<Field label="New slot">
					<select
						className={inputClass}
						value={slot}
						onChange={(e) => setSlot(Number(e.target.value))}
					>
						<option value={0}>Release the slot</option>
						{slots.map((s) => (
							<option key={s} value={s}>
								{s}
							</option>
						))}
					</select>
				</Field>
			</ActionDialog>
			<ActionDialog
				label={stackUp ? "Stack down" : "Stack up"}
				title={`${stackUp ? "Stop" : "Start"} ${code}'s stack`}
				disabled={!launched}
				command={`just ${stackUp ? "stop" : "dev-backend"} (in ${phase.worktree})`}
				run={() => post(`/api/phases/${code}/stack`, { up: !stackUp })}
			/>
			<ActionDialog
				label="Tear down"
				title={`Tear down ${code}`}
				variant="destructive"
				disabled={!canTeardown}
				confirmWord={code}
				warning="Stops the session, removes the stack (volumes too), the worktrees and the phase's local branches. If the ledger has no worktree, this removes an unrecorded one left by a failed launch, if any."
				command={`claude stop ${phase.session ?? ""}\nteardown-phase.sh ${code}`}
				run={() => post(`/api/phases/${code}/teardown`, { confirm: code })}
			/>
		</div>
	);
}
