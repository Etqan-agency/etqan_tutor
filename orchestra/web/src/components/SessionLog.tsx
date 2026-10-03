import { Terminal } from "@xterm/xterm";
import { useEffect, useRef, useState } from "react";
import { useLog } from "@/api/queries";
import { Button } from "@/ui/Button";

/** `claude logs` is the session's raw terminal output: a terminal renders it as it looked. */
export function SessionLog({ who }: { who: string }) {
	const host = useRef<HTMLDivElement>(null);
	const terminal = useRef<Terminal | null>(null);
	const [paused, setPaused] = useState(false);
	const { data } = useLog(who, !paused);

	useEffect(() => {
		if (!host.current) return;
		const term = new Terminal({
			cols: 200,
			rows: 50,
			disableStdin: true,
			scrollback: 5000,
			fontSize: 12,
		});
		term.open(host.current);
		terminal.current = term;
		return () => term.dispose();
	}, []);

	useEffect(() => {
		if (!terminal.current || data === undefined) return;
		terminal.current.reset();
		terminal.current.write(data.text);
	}, [data]);

	return (
		<div>
			<div className="mb-2 flex items-center justify-between">
				<h2 className="font-semibold">Session output</h2>
				<Button variant="ghost" size="sm" onClick={() => setPaused((p) => !p)}>
					{paused ? "Resume updates" : "Pause updates"}
				</Button>
			</div>
			<div
				ref={host}
				className="overflow-auto rounded-md border border-border bg-muted p-2"
			/>
		</div>
	);
}
