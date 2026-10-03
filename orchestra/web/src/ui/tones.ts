import type { PhaseStatus, SessionState } from "@/api/types";

export type Tone = "neutral" | "success" | "warning" | "destructive" | "info";

export const phaseTone: Record<PhaseStatus, Tone> = {
	"waiting-deps": "neutral",
	spec: "info",
	plan: "info",
	build: "info",
	review: "warning",
	queued: "warning",
	merged: "success",
	paused: "neutral",
};

export const sessionTone: Record<SessionState, Tone> = {
	busy: "success",
	idle: "info",
	exited: "warning",
	gone: "destructive",
	none: "neutral",
};
