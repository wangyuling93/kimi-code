import { execFileSync } from "node:child_process";
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

/**
 * Fork-identity version step: rewrite upstream changeset bump targets before
 * running `changeset version`.
 *
 * Upstream changesets reference "@moonshot-ai/kimi-code", a package that does
 * not exist in this fork (renamed to "@vyl/kimi-code"). "Sync fork" merges
 * bring such changesets in without conflict markers. The rewrite must happen
 * HERE (inside the version command), not in a workflow step, because the
 * changesets action resets the working tree with `git reset --hard` after
 * checking out the release branch, which would discard any earlier rewrite.
 */
const changesetDir = join(process.cwd(), ".changeset");
let rewritten = false;
for (const name of readdirSync(changesetDir)) {
  if (!name.endsWith(".md")) continue;
  const file = join(changesetDir, name);
  const content = readFileSync(file, "utf8");
  const next = content.replaceAll('"@moonshot-ai/kimi-code"', '"@vyl/kimi-code"');
  if (next !== content) {
    writeFileSync(file, next);
    rewritten = true;
    console.log(`rewrote ${name}: @moonshot-ai/kimi-code -> @vyl/kimi-code`);
  }
}
if (!rewritten) {
  console.log("no changeset rewrites needed");
}

execFileSync("pnpm", ["changeset", "version"], { stdio: "inherit" });
