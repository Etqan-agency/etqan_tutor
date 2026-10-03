import type { ButtonHTMLAttributes } from "react";

type Variant = "primary" | "secondary" | "destructive" | "ghost";
const VARIANTS: Record<Variant, string> = {
	primary: "bg-primary text-primary-foreground hover:opacity-90",
	secondary: "bg-secondary text-secondary-foreground hover:opacity-90",
	destructive: "bg-destructive text-destructive-foreground hover:opacity-90",
	ghost: "bg-transparent text-foreground hover:bg-muted",
};

export type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
	variant?: Variant;
	size?: "sm" | "md";
};

export function Button({
	variant = "primary",
	size = "md",
	className = "",
	...props
}: ButtonProps) {
	const sizing = size === "sm" ? "px-2.5 py-1 text-xs" : "px-3.5 py-2 text-sm";
	return (
		<button
			type="button"
			className={`inline-flex items-center gap-1.5 rounded-md font-medium focus-visible:outline-2 focus-visible:outline-ring disabled:cursor-not-allowed disabled:opacity-50 ${sizing} ${VARIANTS[variant]} ${className}`}
			{...props}
		/>
	);
}
