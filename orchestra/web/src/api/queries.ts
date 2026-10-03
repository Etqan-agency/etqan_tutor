import { useQuery } from "@tanstack/react-query";
import { get } from "./client";
import type { Ci, Ledger, State } from "./types";

export const keys = {
	state: ["state"] as const,
	ci: ["ci"] as const,
	log: (who: string) => ["log", who] as const,
};

export const useOrchestraState = () =>
	useQuery({ queryKey: keys.state, queryFn: () => get<State>("/api/state") });

export const useCi = () =>
	useQuery({
		queryKey: keys.ci,
		queryFn: () => get<Ci>("/api/ci"),
		refetchInterval: 60_000,
	});

export const useLog = (who: string, enabled: boolean) =>
	useQuery({
		queryKey: keys.log(who),
		queryFn: () =>
			get<{ text: string }>(
				who === "conductor" ? "/api/conductor/log" : `/api/phases/${who}/log`,
			),
		refetchInterval: enabled ? 3000 : false,
	});

export const SLOTS = [1, 2, 3, 4];

export function freeSlots(ledger: Ledger): number[] {
	const held = new Set(
		Object.values(ledger.phases)
			.filter((p) => p.slot !== null && p.status !== "merged")
			.map((p) => p.slot),
	);
	return SLOTS.filter((slot) => !held.has(slot));
}
