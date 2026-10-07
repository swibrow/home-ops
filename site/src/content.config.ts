import { defineCollection } from "astro:content";
import { glob } from "astro/loaders";
import { docIdFromPath } from "./lib/slug.ts";

const docs = defineCollection({
  loader: glob({
    pattern: "**/*.md",
    base: "../docs",
    generateId: ({ entry }) => docIdFromPath(entry),
  }),
});

export const collections = { docs };
