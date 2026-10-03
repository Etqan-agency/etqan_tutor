import type { Ledger } from "@/api/types";
import { Badge } from "@/ui/Badge";

const PR = /https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/pull\/(\d+)/g;

export function SlicesTable({
	ledger,
	code,
}: {
	ledger: Ledger;
	code: string;
}) {
	const slices = Object.entries(ledger.slices).filter(
		([, s]) => s.phase === code,
	);
	if (slices.length === 0)
		return <p className="text-sm text-muted-foreground">No slices yet.</p>;
	return (
		<table className="w-full text-sm">
			<thead className="text-left text-muted-foreground">
				<tr>
					<th className="py-1">Slice</th>
					<th>Status</th>
					<th>Plan</th>
					<th>Requires</th>
					<th>PRs</th>
					<th>Bounces</th>
				</tr>
			</thead>
			<tbody>
				{slices.map(([sid, slice]) => (
					<tr key={sid} className="border-t border-border">
						<td className="py-1 font-medium">{sid}</td>
						<td>
							<Badge tone={slice.status === "merged" ? "success" : "info"}>
								{slice.status}
							</Badge>
						</td>
						<td>{slice.plan_number ?? "—"}</td>
						<td className="space-x-2">
							{slice.requires.length === 0
								? "—"
								: slice.requires.map((need) => (
										<span
											key={need}
										>{`${need} ${ledger.slices[need]?.status === "merged" ? "✓" : "✗"}`}</span>
									))}
						</td>
						<td className="space-x-2">
							{[...(slice.prs ?? "").matchAll(PR)].map((match) => (
								<a
									key={match[0]}
									className="hover:underline"
									href={match[0]}
									target="_blank"
									rel="noreferrer"
								>{`#${match[1]}`}</a>
							))}
						</td>
						<td>{slice.bounces}</td>
					</tr>
				))}
			</tbody>
		</table>
	);
}
