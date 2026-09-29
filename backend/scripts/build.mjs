// Bundles each Lambda handler in src/handlers into dist/<name>/index.mjs.
import { build } from "esbuild";
import { readdirSync } from "node:fs";
import { basename } from "node:path";

const handlers = readdirSync("src/handlers").filter(
  (f) => f.endsWith(".ts") && !f.endsWith(".test.ts"),
);

await Promise.all(
  handlers.map((file) =>
    build({
      entryPoints: [`src/handlers/${file}`],
      outfile: `dist/${basename(file, ".ts")}/index.mjs`,
      bundle: true,
      platform: "node",
      target: "node22",
      format: "esm",
      sourcemap: true,
      minify: true,
      external: ["@aws-sdk/*"],
    }),
  ),
);

console.log(`built ${handlers.length} handler(s)`);
