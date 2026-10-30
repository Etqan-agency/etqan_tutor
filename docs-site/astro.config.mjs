import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";
import remarkDocsLinks from "./src/remark-docs-links.mjs";

const page = (slug) => ({ slug });

export default defineConfig({
	redirects: { "/": "/features/" },
	markdown: { remarkPlugins: [remarkDocsLinks] },
	integrations: [
		starlight({
			title: "Etqan Tutor Docs",
			sidebar: [
				{ label: "Switches", link: "/switches/" },
				{
					label: "Features",
					items: [
						{ label: "Overview", ...page("features") },
						{
							label: "Platform",
							items: ["tenancy", "feature-toggles", "academy-settings", "integrations", "etqan-billing", "private-files"].map((s) => page(`features/${s}`)),
						},
						{
							label: "People and access",
							items: ["people", "sign-in", "roles-permissions", "registration", "employment"].map((s) => page(`features/${s}`)),
						},
						{
							label: "Teaching operations",
							items: ["catalogue", "subscriptions", "sessions", "scheduling-tools", "meetings"].map((s) => page(`features/${s}`)),
						},
						{
							label: "Money",
							items: ["billing", "online-payments", "finance", "wallet", "vouchers", "payroll"].map((s) => page(`features/${s}`)),
						},
						{
							label: "Communication",
							items: ["notifications", "email-whatsapp", "chat", "web-push"].map((s) => page(`features/${s}`)),
						},
						{
							label: "Learning",
							items: ["curriculum", "homework-content", "reviews-honour", "certificates", "student-reports", "library"].map((s) => page(`features/${s}`)),
						},
						{
							label: "Website",
							items: ["website", "website-content"].map((s) => page(`features/${s}`)),
						},
						{
							label: "AI and apps",
							items: ["ai", "apps"].map((s) => page(`features/${s}`)),
						},
						{
							label: "Sales add-ons",
							items: ["recorded-courses", "consultations"].map((s) => page(`features/${s}`)),
						},
					],
				},
				{
					label: "Guide",
					items: [
						{ label: "Overview", ...page("guide") },
						...["onboarding", "architecture", "adding-a-feature", "testing"].map((s) => page(`guide/${s}`)),
					],
				},
				{
					label: "Runbooks",
					items: ["deploy", "operations"].map((s) => page(`guide/runbooks/${s}`)),
				},
			],
		}),
	],
});
