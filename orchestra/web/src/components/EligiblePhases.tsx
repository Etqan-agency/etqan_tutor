import { useState } from "react";
import { post } from "@/api/client";
import { freeSlots } from "@/api/queries";
import type { State } from "@/api/types";
import { ActionDialog } from "@/ui/ActionDialog";
import { Card } from "@/ui/Card";
import { Field, inputClass } from "@/ui/Field";
import { ModeField } from "./SessionControls";

const slug = (text: string) =>
	text
		.toLowerCase()
		.replace(/[^a-z0-9]+/g, "-")
		.replace(/^-|-$/g, "");

function LaunchDialog({
	code,
	title,
	slots,
}: {
	code: string;
	title: string;
	slots: number[];
}) {
	const [suffix, setSuffix] = useState(`${code.toLowerCase()}a-${slug(title)}`);
	const [slot, setSlot] = useState(slots[0]);
	const [mode, setMode] = useState("auto");
	return (
		<ActionDialog
			label={`Launch ${code}`}
			title={`Launch ${code} · ${title}`}
			variant="primary"
			command={`launch-phase.sh ${code} ${suffix} ${slot}\nstart-session.sh ${code} --mode ${mode}`}
			canSubmit={/^[a-z0-9][a-z0-9-]*$/.test(suffix)}
			run={() => post(`/api/phases/${code}/launch`, { suffix, slot, mode })}
		>
			<Field label="Branch suffix">
				<input
					className={inputClass}
					value={suffix}
					onChange={(e) => setSuffix(e.target.value.trim())}
				/>
			</Field>
			<Field label="Slot">
				<select
					className={inputClass}
					value={slot}
					onChange={(e) => setSlot(Number(e.target.value))}
				>
					{slots.map((s) => (
						<option key={s} value={s}>
							{s}
						</option>
					))}
				</select>
			</Field>
			<ModeField value={mode} onChange={setMode} />
		</ActionDialog>
	);
}

export function EligiblePhases({ state }: { state: State }) {
	const slots = freeSlots(state.ledger);
	const codes = state.eligible.phases;
	return (
		<Card
			title="Ready to launch"
			aside={`${slots.length} free slot${slots.length === 1 ? "" : "s"}`}
		>
			{codes.length === 0 ? (
				<p className="text-sm text-muted-foreground">
					No phase is ready, or no slot is free.
				</p>
			) : (
				<ul className="space-y-2">
					{codes.map((code) => (
						<li
							key={code}
							className="flex items-center justify-between gap-3 text-sm"
						>
							<span>{`${code} · ${state.ledger.phases[code].title}`}</span>
							<LaunchDialog
								code={code}
								title={state.ledger.phases[code].title}
								slots={slots}
							/>
						</li>
					))}
				</ul>
			)}
		</Card>
	);
}
