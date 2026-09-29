// Bundles the game engines into one script for JavaScriptCore on iOS. The
// output is committed; CI rebuilds it and fails if it differs.
import { build } from "esbuild";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const backendDir = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const outfile = resolve(backendDir, "../ios/Wad/Resources/engines.js");

await build({
  absWorkingDir: backendDir,
  entryPoints: ["src/engines/index.ts"],
  outfile,
  bundle: true,
  platform: "neutral",
  target: "es2020",
  format: "iife",
  globalName: "WadEngines",
  charset: "ascii",
  legalComments: "none",
  minify: false,
  sourcemap: false,
  banner: {
    js: "// Generated from backend/src/engines by `npm run build:ios-engines`. Do not edit.",
  },
});

console.log(`built ${outfile}`);
