import path from "node:path";
import react from "@vitejs/plugin-react-swc";
import { defineConfig } from "vitest/config";

export default defineConfig({
	plugins: [react()],
	resolve: { alias: { "@": path.resolve(__dirname, "./src") } },
	test: {
		environment: "jsdom",
		globals: true,
		setupFiles: ["./src/test/setup.ts"],
		coverage: {
			provider: "v8",
			all: true,
			include: ["src/**/*.{ts,tsx}"],
			exclude: [
				"src/main.tsx",
				"src/test/**",
				"**/*.test.{ts,tsx}",
				"**/*.d.ts",
			],
			reporter: ["text-summary", "text"],
			thresholds: { lines: 80, statements: 80, branches: 70, functions: 70 },
		},
	},
});
