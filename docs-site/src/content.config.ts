import { defineCollection } from "astro:content";
import { glob } from "astro/loaders";
import { docsSchema } from "@astrojs/starlight/schema";

export const collections = {
	docs: defineCollection({
		loader: glob({ pattern: ["features/**/*.md", "guide/**/*.md"], base: "../docs", generateId: ({ entry }) => entry.replace(/\.md$/, "").toLowerCase().replace(/\/readme$/, "") }),
		schema: docsSchema(),
	}),
};
