import type { ReactNode } from "react";

export const inputClass =
	"w-full rounded-md border border-input bg-background px-2.5 py-1.5 text-sm focus-visible:outline-2 focus-visible:outline-ring";

/** A label wrapping its control, so getByLabelText finds it. */
export function Field({
	label,
	children,
}: {
	label: string;
	children: ReactNode;
}) {
	return (
		// biome-ignore lint/a11y/noLabelWithoutControl: the control is the child passed in, which the rule cannot see
		<label className="block text-sm">
			<span className="mb-1 block font-medium">{label}</span>
			{children}
		</label>
	);
}
