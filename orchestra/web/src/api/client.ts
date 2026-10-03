export class ApiError extends Error {
	readonly status: number;
	readonly outputTail?: string;
	readonly exitCode?: number;

	constructor(
		status: number,
		message: string,
		outputTail?: string,
		exitCode?: number,
	) {
		super(message);
		this.name = "ApiError";
		this.status = status;
		this.outputTail = outputTail;
		this.exitCode = exitCode;
	}
}

let tokenPromise: Promise<string> | null = null;

/** The server puts its token in index.html; under `just orchestra-dev` Vite serves
 * the page, so the dev server's /api/token supplies it instead. */
function token(): Promise<string> {
	if (!tokenPromise) {
		const meta = document.querySelector<HTMLMetaElement>(
			'meta[name="orchestra-token"]',
		);
		tokenPromise = meta
			? Promise.resolve(meta.content)
			: get<{ token: string }>("/api/token").then((body) => body.token);
	}
	return tokenPromise;
}

export function resetToken() {
	tokenPromise = null;
}

async function parse<T>(response: Response): Promise<T> {
	const body = await response.json().catch(() => ({}));
	if (!response.ok) {
		const message =
			body.error ??
			(body.exit_code !== undefined
				? `command failed (exit ${body.exit_code})`
				: `HTTP ${response.status}`);
		throw new ApiError(
			response.status,
			message,
			body.output_tail,
			body.exit_code,
		);
	}
	return body as T;
}

export async function get<T>(path: string): Promise<T> {
	return parse<T>(
		await fetch(path, { headers: { Accept: "application/json" } }),
	);
}

export async function post<T = { ok: boolean }>(
	path: string,
	body: unknown = {},
): Promise<T> {
	const response = await fetch(path, {
		method: "POST",
		headers: {
			"Content-Type": "application/json",
			"X-Orchestra-Token": await token(),
		},
		body: JSON.stringify(body),
	});
	return parse<T>(response);
}
