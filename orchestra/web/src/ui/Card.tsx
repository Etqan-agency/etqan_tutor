import type { ReactNode } from "react";

export function Card({
	title,
	aside,
	children,
}: {
	title?: ReactNode;
	aside?: ReactNode;
	children: ReactNode;
}) {
	return (
		<section className="rounded-lg border border-border bg-card p-4 text-card-foreground">
			{(title || aside) && (
				<header className="mb-3 flex items-baseline justify-between gap-3">
					{title && <h2 className="font-semibold">{title}</h2>}
					{aside && (
						<span className="text-xs text-muted-foreground">{aside}</span>
					)}
				</header>
			)}
			{children}
		</section>
	);
}
