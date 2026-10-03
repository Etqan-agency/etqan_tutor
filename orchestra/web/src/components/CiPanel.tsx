import { useCi } from "@/api/queries";
import type { Check, Failure } from "@/api/types";
import { Badge } from "@/ui/Badge";
import { Card } from "@/ui/Card";

const isFailure = (value: unknown): value is Failure =>
	typeof value === "object" && value !== null && "error" in value;

function summary(checks: Check[]) {
	const count = (bucket: string) =>
		checks.filter((c) => c.bucket === bucket).length;
	return `${count("pass")} passed · ${count("fail")} failed · ${count("pending")} pending`;
}

export function CiPanel() {
	const { data } = useCi();
	const master = data?.master;
	return (
		<Card title="CI">
			{!data ? (
				<p className="text-sm text-muted-foreground">Loading…</p>
			) : (
				<div className="space-y-2 text-sm">
					<p className="flex items-center gap-2">
						<span>master</span>
						{isFailure(master) ? (
							<span className="text-destructive">{master.error}</span>
						) : master ? (
							<a href={master.url} target="_blank" rel="noreferrer">
								<Badge
									tone={
										master.conclusion === "success"
											? "success"
											: master.status === "completed"
												? "destructive"
												: "info"
									}
								>
									{master.conclusion || master.status}
								</Badge>
							</a>
						) : (
							<span className="text-muted-foreground">no runs</span>
						)}
					</p>
					{data.prs.map((pr) => (
						<p key={pr.url}>
							<a
								className="hover:underline"
								href={pr.url}
								target="_blank"
								rel="noreferrer"
							>{`${pr.slice} · #${pr.number}`}</a>{" "}
							<span className="text-muted-foreground">
								{isFailure(pr.checks) ? pr.checks.error : summary(pr.checks)}
							</span>
						</p>
					))}
				</div>
			)}
		</Card>
	);
}
