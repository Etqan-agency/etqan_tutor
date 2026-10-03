import path from "node:path";
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react-swc";
import { defineConfig } from "vite";

// `just orchestra-dev`: Vite on 5174, the API proxied to the server. The server
// refuses foreign Origins, so the proxy drops the page's (localhost:5174) Origin.
const api = process.env.ORCHESTRA_API ?? "http://127.0.0.1:7700";

export default defineConfig({
	plugins: [react(), tailwindcss()],
	resolve: { alias: { "@": path.resolve(__dirname, "./src") } },
	server: {
		host: "127.0.0.1",
		port: 5174,
		strictPort: true,
		allowedHosts: ["127.0.0.1", "localhost"],
		cors: false,
		// Dev mode serves the page itself (the production anti-framing headers, app.py
		// `_guard`, only cover the built server), so the dev server sends them too.
		headers: {
			"X-Frame-Options": "DENY",
			"Content-Security-Policy": "frame-ancestors 'none'",
		},
		proxy: {
			"/api": {
				target: api,
				changeOrigin: true,
				configure: (proxy) => {
					proxy.on("proxyReq", (request) => request.removeHeader("origin"));
				},
			},
		},
	},
});
