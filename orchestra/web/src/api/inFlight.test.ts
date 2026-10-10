import { flying, inFlightLabel } from "@/api/inFlight";
import { makeLedger } from "@/test/fixtures";

describe("inFlight", () => {
	it("lists the primary then the extra", () => {
		const ledger = makeLedger();
		expect(inFlightLabel(ledger)).toBe("—");
		ledger.in_flight = "B4d";
		ledger.in_flight_extra = "B5c";
		expect(flying(ledger)).toEqual(["B4d", "B5c"]);
		expect(inFlightLabel(ledger)).toBe("B4d + B5c");
	});

	it("reads a ledger written before the second slot", () => {
		const ledger = makeLedger();
		delete ledger.in_flight_extra;
		ledger.in_flight = "B3a";
		expect(inFlightLabel(ledger)).toBe("B3a");
	});
});
