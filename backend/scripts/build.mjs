// Bundles each Lambda handler in src/handlers into dist/<name>/index.mjs.
import { build } from "esbuild";
import { readdirSync } from "node:fs";
import { basename, resolve } from "node:path";
import { pathToFileURL } from "node:url";

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
      // The AWS SDK is CommonJS; bundled into an ESM file its `require` calls
      // fail at load time ("Dynamic require of node:https is not supported")
      // unless a `require` is provided.
      banner: {
        js: 'import { createRequire } from "node:module"; const require = createRequire(import.meta.url);',
      },
    }),
  ),
);

// Load each bundle the way the Lambda runtime does, so a bundle that throws
// at import time fails the build here instead of in production.
for (const file of handlers) {
  const name = basename(file, ".ts");
  const bundle = await import(pathToFileURL(resolve(`dist/${name}/index.mjs`)).href);
  if (typeof bundle.handler !== "function") throw new Error(`dist/${name}/index.mjs does not export a handler function`);
}

console.log(`built ${handlers.length} handler(s)`);
