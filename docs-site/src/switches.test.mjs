import { describe, expect, it } from "vitest";
import { checkDocs, groupFeatures } from "./switches.mjs";

const f = (code, group, doc) => ({ code, group, doc });

describe("checkDocs", () => {
	const ids = new Set(["features/sessions", "features/billing"]);
	it("returns [] for valid docs", () => {
		expect(checkDocs([f("a", "g", "features/sessions"), f("b", "g", "features/billing")], ids)).toEqual([]);
	});
	it("lists a missing page", () => {
		expect(checkDocs([f("x", "g", "features/nope")], ids)).toEqual(["x → features/nope"]);
	});
	it("ignores the anchor", () => {
		expect(checkDocs([f("a", "g", "features/sessions#top")], ids)).toEqual([]);
		expect(checkDocs([f("x", "g", "features/nope#top")], ids)).toEqual(["x → features/nope#top"]);
	});
});

describe("groupFeatures", () => {
	it("keeps groups in first-seen order and features in registry order", () => {
		const list = [f("a", "people"), f("b", "teaching"), f("c", "people"), f("d", "money")];
		const m = groupFeatures(list);
		expect([...m.keys()]).toEqual(["people", "teaching", "money"]);
		expect(m.get("people").map((x) => x.code)).toEqual(["a", "c"]);
	});
});
