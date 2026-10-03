import { useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { keys } from "./queries";

/** The server's event stream: a ledger commit or a session change refetches the state. */
export function useLiveUpdates(): boolean {
	const client = useQueryClient();
	const [connected, setConnected] = useState(false);
	useEffect(() => {
		const source = new EventSource("/api/events");
		source.onopen = () => setConnected(true);
		source.onerror = () => setConnected(false);
		const refresh = () => client.invalidateQueries({ queryKey: keys.state });
		source.addEventListener("ledger", refresh);
		source.addEventListener("sessions", refresh);
		return () => source.close();
	}, [client]);
	return connected;
}
