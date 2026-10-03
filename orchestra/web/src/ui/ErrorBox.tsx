import { ApiError } from "@/api/client";

export function ErrorBox({ error }: { error: unknown }) {
	const message = error instanceof Error ? error.message : String(error);
	const tail = error instanceof ApiError ? error.outputTail : undefined;
	return (
		<div
			role="alert"
			className="mt-3 rounded-md border border-destructive p-3 text-sm"
		>
			<p className="font-medium text-destructive">{message}</p>
			{tail && (
				<pre className="mt-2 max-h-64 overflow-auto whitespace-pre-wrap font-mono text-xs">
					{tail}
				</pre>
			)}
		</div>
	);
}
