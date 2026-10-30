export function checkDocs(features, pageIds) {
	return features
		.filter((f) => !pageIds.has(f.doc.split("#")[0]))
		.map((f) => `${f.code} → ${f.doc}`);
}

export function groupFeatures(features) {
	const groups = new Map();
	for (const f of features) {
		if (!groups.has(f.group)) groups.set(f.group, []);
		groups.get(f.group).push(f);
	}
	return groups;
}
