import type { Ledger } from "@/api/types";

/** The slices in flight, oldest first (`in_flight`, then `in_flight_extra`). */
export function flying(ledger: Ledger): string[] {
	return [ledger.in_flight, ledger.in_flight_extra].filter(
		(sid): sid is string => Boolean(sid),
	);
}

/** "B4d + B5c", or "—" when nothing is in flight. */
export function inFlightLabel(ledger: Ledger): string {
	return flying(ledger).join(" + ") || "—";
}
