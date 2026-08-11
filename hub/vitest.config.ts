import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "edge-runtime",
    include: ["convex/*.test.ts"],
    exclude: ["convex/lib/**"],
    coverage: {
      provider: "v8",
      reporter: ["text", "json-summary"],
      thresholds: {
        lines: 70,
        functions: 80,
        statements: 70,
        branches: 45,
      },
    },
  },
});
