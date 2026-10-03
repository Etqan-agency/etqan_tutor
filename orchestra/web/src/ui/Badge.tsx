import type { ReactNode } from "react";
import type { Tone } from "./tones";

const TONES: Record<Tone, string> = {
	neutral: "bg-muted text-muted-foreground",
	success: "bg-success text-success-foreground",
	warning: "bg-warning text-warning-foreground",
	destructive: "bg-destructive text-destructive-foreground",
	info: "bg-info text-info-foreground",
};

export function Badge({
	tone = "neutral",
	children,
}: {
	tone?: Tone;
	children: ReactNode;
}) {
	return (
		<span
			className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ${TONES[tone]}`}
		>
			{children}
		</span>
	);
}
