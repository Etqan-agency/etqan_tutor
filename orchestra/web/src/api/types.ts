export type PhaseStatus =
	| "waiting-deps"
	| "spec"
	| "plan"
	| "build"
	| "review"
	| "queued"
	| "merged"
	| "paused";
export const PHASE_STATUSES: PhaseStatus[] = [
	"waiting-deps",
	"spec",
	"plan",
	"build",
	"review",
	"queued",
	"merged",
	"paused",
];

export type Phase = {
	title: string;
	status: PhaseStatus;
	requires: string[];
	slot: number | null;
	worktree: string | null;
	branch: string | null;
	spec: string | null;
	current_slice: string | null;
	current_task: string | null;
	session: string | null;
};

export type Slice = {
	phase: string;
	status:
		| "spec"
		| "plan"
		| "build"
		| "review"
		| "queued"
		| "in-flight"
		| "merged";
	requires: string[];
	plan_number: number | null;
	spec: string | null;
	plan: string | null;
	prs: string | null;
	bounces: number;
	last_bounce?: string;
};

export type Escalation = {
	id: string;
	phase: string;
	kind: string;
	question: string;
	status: "open" | "resolved";
	answer: string | null;
};
export type Decision = {
	id: string;
	phase: string;
	decision: string;
	affects: string[];
	source: string;
};
export type Claim = {
	target: string;
	phase: string;
	reason: string;
	since: string;
};
export type LedgerRequest = {
	id: string;
	from: string;
	app: string;
	to_owner: string;
	what: string;
	status: "open" | "done";
};

export type Ledger = {
	phases: Record<string, Phase>;
	slices: Record<string, Slice>;
	next_plan_number: number;
	ownership: Record<string, string>;
	claims: Claim[];
	shared_decisions: Decision[];
	requests: LedgerRequest[];
	queue: string[];
	in_flight: string | null;
	main_heads: Record<string, string>;
	escalations: Escalation[];
	conductor_session: string | null;
};

export type SessionState = "busy" | "idle" | "exited" | "gone" | "none";
export type Session = {
	id: string | null;
	state: SessionState;
	session_id?: string | null;
	cwd?: string | null;
};

export type State = {
	ledger: Ledger;
	eligible: { free: number; phases: string[] };
	sessions: Record<string, Session>;
	stacks: Record<string, boolean>;
};

export type Check = {
	name: string;
	state: string;
	bucket: string;
	link: string;
};
export type Failure = { error: string };
export type Ci = {
	master:
		| {
				status: string;
				conclusion: string;
				headSha: string;
				url: string;
				createdAt: string;
		  }
		| Failure
		| null;
	prs: {
		slice: string;
		repo: string;
		number: number;
		url: string;
		checks: Check[] | Failure;
	}[];
};
