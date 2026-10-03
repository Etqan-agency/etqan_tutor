import { useQueryClient } from "@tanstack/react-query";
import {
	type ReactNode,
	useCallback,
	useEffect,
	useId,
	useRef,
	useState,
} from "react";
import { Button } from "./Button";
import { ErrorBox } from "./ErrorBox";
import { Field, inputClass } from "./Field";

const FOCUSABLE_SELECTOR =
	'button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), a[href], [tabindex]:not([tabindex="-1"])';

type Props = {
	label: string;
	title: string;
	/** Exactly what will run or change, shown before confirming. */
	command: string;
	run: () => Promise<unknown>;
	confirmWord?: string;
	variant?: "primary" | "secondary" | "destructive";
	disabled?: boolean;
	warning?: string;
	canSubmit?: boolean;
	children?: ReactNode;
};

/** Every change goes through one of these: a button, then a dialog naming the command. */
export function ActionDialog({
	label,
	title,
	command,
	run,
	confirmWord,
	variant = "secondary",
	disabled,
	warning,
	canSubmit = true,
	children,
}: Props) {
	const client = useQueryClient();
	const id = useId();
	const [open, setOpen] = useState(false);
	const [typed, setTyped] = useState("");
	const [pending, setPending] = useState(false);
	const [error, setError] = useState<unknown>(null);
	const dialogRef = useRef<HTMLDivElement>(null);
	const triggerRef = useRef<HTMLElement | null>(null);

	const close = useCallback(() => {
		setOpen(false);
		setTyped("");
		setError(null);
	}, []);

	// Move focus into the dialog on open (the first field, else Cancel — never
	// Confirm, so Enter can't fire a destructive action by accident), and
	// return it to the button that opened the dialog when it closes.
	useEffect(() => {
		if (!open) return;
		const dialog = dialogRef.current;
		const firstField = dialog?.querySelector<HTMLElement>(
			"input, select, textarea",
		);
		const cancelButton = dialog?.querySelector<HTMLElement>("[data-cancel]");
		(firstField ?? cancelButton)?.focus();
		return () => {
			triggerRef.current?.focus();
		};
	}, [open]);

	// Escape closes (unless a submit is in flight); Tab traps focus inside the dialog.
	useEffect(() => {
		if (!open) return;
		const onKey = (event: KeyboardEvent) => {
			if (event.key === "Escape") {
				if (!pending) close();
				return;
			}
			if (event.key !== "Tab") return;
			const focusable = Array.from(
				dialogRef.current?.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR) ??
					[],
			);
			if (focusable.length === 0) return;
			const first = focusable[0];
			const last = focusable[focusable.length - 1];
			const active = document.activeElement;
			if (event.shiftKey && active === first) {
				event.preventDefault();
				last.focus();
			} else if (!event.shiftKey && active === last) {
				event.preventDefault();
				first.focus();
			}
		};
		window.addEventListener("keydown", onKey);
		return () => window.removeEventListener("keydown", onKey);
	}, [open, pending, close]);

	async function submit() {
		setPending(true);
		setError(null);
		try {
			await run();
			await client.invalidateQueries();
			close();
		} catch (caught) {
			setError(caught);
		} finally {
			setPending(false);
		}
	}

	const ready =
		canSubmit && (!confirmWord || typed === confirmWord) && !pending;
	return (
		<>
			<Button
				variant={variant === "destructive" ? "destructive" : "secondary"}
				size="sm"
				disabled={disabled}
				onClick={(e) => {
					triggerRef.current = e.currentTarget;
					setOpen(true);
				}}
			>
				{label}
			</Button>
			{open && (
				<div className="fixed inset-0 z-50 flex items-center justify-center bg-overlay p-4">
					<div
						ref={dialogRef}
						role="dialog"
						aria-modal="true"
						aria-labelledby={id}
						className="w-full max-w-lg rounded-lg border border-border bg-card p-5 text-card-foreground shadow-lg"
					>
						<h2 id={id} className="text-lg font-semibold">
							{title}
						</h2>
						{warning && (
							<p className="mt-2 rounded-md bg-warning p-2 text-sm text-warning-foreground">
								{warning}
							</p>
						)}
						<p className="mt-3 text-sm text-muted-foreground">This will run:</p>
						<pre className="mt-1 whitespace-pre-wrap rounded-md bg-muted p-2 font-mono text-xs">
							{command}
						</pre>
						{children && <div className="mt-4 space-y-3">{children}</div>}
						{confirmWord && (
							<div className="mt-4">
								<Field label={`Type ${confirmWord} to confirm`}>
									<input
										className={inputClass}
										value={typed}
										onChange={(e) => setTyped(e.target.value)}
									/>
								</Field>
							</div>
						)}
						{error !== null && <ErrorBox error={error} />}
						<div className="mt-5 flex justify-end gap-2">
							<Button
								variant="ghost"
								onClick={close}
								disabled={pending}
								data-cancel
							>
								Cancel
							</Button>
							<Button
								variant={variant === "destructive" ? "destructive" : "primary"}
								disabled={!ready}
								onClick={submit}
							>
								{pending ? "Working…" : "Confirm"}
							</Button>
						</div>
					</div>
				</div>
			)}
		</>
	);
}
