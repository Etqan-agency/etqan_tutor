import type { Ledger, Phase, State } from "@/api/types";

const TITLES: Record<string, [string, string[]]> = {
	B2: ["Scheduling depth", []],
	B3: ["Money depth", []],
	B4: ["Payroll depth", ["B2", "B3"]],
	B5: ["Communication", ["B2"]],
	B6: ["Learning", ["B2"]],
	B7: ["Add-on sales", ["B3"]],
	B8: ["Marketing extras", []],
	B9: ["Platform extras", []],
	B10: ["AI", ["B6"]],
	B11: ["Apps", ["B2", "B3", "B4", "B5"]],
};

export function makeLedger(): Ledger {
	const phases: Record<string, Phase> = {};
	for (const [code, [title, requires]] of Object.entries(TITLES)) {
		phases[code] = {
			title,
			requires,
			status: "waiting-deps",
			slot: null,
			worktree: null,
			branch: null,
			spec: null,
			current_slice: null,
			current_task: null,
			session: null,
		};
	}
	return {
		phases,
		slices: {},
		next_plan_number: 15,
		ownership: { scheduling: "B2" },
		claims: [],
		shared_decisions: [],
		requests: [],
		queue: [],
		in_flight: null,
		in_flight_extra: null,
		main_heads: {},
		escalations: [],
		conductor_session: null,
	};
}

/** A state; `edit` changes its ledger in place. */
export function makeState(
	edit?: (ledger: Ledger) => void,
	extra: Partial<State> = {},
): State {
	const ledger = makeLedger();
	edit?.(ledger);
	return {
		ledger,
		eligible: { free: 4, phases: ["B2", "B3", "B8", "B9"] },
		sessions: { conductor: { id: null, state: "none" } },
		stacks: {},
		...extra,
	};
}
