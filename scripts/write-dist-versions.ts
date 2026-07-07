import { chmodSync, mkdirSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

const files = [
  "browse/dist/.version",
  "design/dist/.version",
  "make-pdf/dist/.version",
];

let revision = "";
try {
  revision = (await Bun.$`git rev-parse HEAD`.quiet().text()).trim();
} catch {
  revision = "";
}

for (const file of files) {
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, revision ? `${revision}\n` : "");
}

if (process.platform !== "win32") {
  for (const file of [
    "browse/dist/browse",
    "browse/dist/find-browse",
    "design/dist/design",
    "make-pdf/dist/pdf",
    "bin/gstack-global-discover",
  ]) {
    try {
      chmodSync(file, 0o755);
    } catch {
      // Optional generated outputs may be absent in partial builds.
    }
  }
}

for (const entry of readdirSync(".")) {
  if (/^\..+\.bun-build$/.test(entry)) {
    rmSync(entry, { recursive: true, force: true });
  }
}
