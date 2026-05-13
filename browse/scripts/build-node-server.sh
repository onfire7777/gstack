#!/usr/bin/env bash
# Build a Node.js-compatible server bundle for Windows.
#
# On Windows, Bun can't launch or connect to Playwright's Chromium
# (oven-sh/bun#4253, #9911). This script produces a server bundle
# that runs under Node.js with Bun API polyfills.

set -e

GSTACK_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SRC_DIR="$GSTACK_DIR/browse/src"
DIST_DIR="$GSTACK_DIR/browse/dist"

BUN_BIN="${BUN_BIN:-}"
if [ -z "$BUN_BIN" ]; then
  if command -v bun >/dev/null 2>&1; then
    BUN_BIN="$(command -v bun)"
  elif command -v bun.exe >/dev/null 2>&1; then
    BUN_BIN="$(command -v bun.exe)"
  elif [ -n "${HOME:-}" ] && [ -x "$HOME/.bun/bin/bun.exe" ]; then
    BUN_BIN="$HOME/.bun/bin/bun.exe"
  elif [ -n "${USERPROFILE:-}" ] && command -v cygpath >/dev/null 2>&1; then
    USERPROFILE_UNIX="$(cygpath -u "$USERPROFILE" 2>/dev/null || true)"
    if [ -n "$USERPROFILE_UNIX" ] && [ -x "$USERPROFILE_UNIX/.bun/bin/bun.exe" ]; then
      BUN_BIN="$USERPROFILE_UNIX/.bun/bin/bun.exe"
    fi
  fi
fi

if [ -z "$BUN_BIN" ]; then
  echo "bun not found; install Bun or set BUN_BIN to the Bun executable" >&2
  exit 127
fi

to_windows_path() {
  local path="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$path"
    return
  fi
  case "$path" in
    /mnt/[a-zA-Z]/*)
      local drive
      local rest
      drive="$(printf '%s' "${path:5:1}" | tr '[:lower:]' '[:upper:]')"
      rest="${path:7}"
      rest="${rest//\//\\}"
      printf '%s:\\%s\n' "$drive" "$rest"
      ;;
    /[a-zA-Z]/*)
      local drive
      local rest
      drive="$(printf '%s' "${path:1:1}" | tr '[:lower:]' '[:upper:]')"
      rest="${path:3}"
      rest="${rest//\//\\}"
      printf '%s:\\%s\n' "$drive" "$rest"
      ;;
    *)
      printf '%s\n' "$path"
      ;;
  esac
}

echo "Building Node-compatible server bundle..."

BUN_SERVER_TS="$SRC_DIR/server.ts"
BUN_OUTFILE="$DIST_DIR/server-node.mjs"
case "$BUN_BIN" in
  *.exe | *.cmd | *bun.exe | *bun.cmd)
    BUN_SERVER_TS="$(to_windows_path "$BUN_SERVER_TS")"
    BUN_OUTFILE="$(to_windows_path "$BUN_OUTFILE")"
    ;;
esac

# Step 1: Transpile server.ts to a single .mjs bundle (externalize runtime deps)
#
# Externalize packages with native addons, dynamic imports, or runtime resolution.
# If you add a new dependency that uses `await import()` or has a .node addon,
# add it here. Otherwise `bun build --outfile` will fail with
# "cannot write multiple output files without an output directory".
"$BUN_BIN" build "$BUN_SERVER_TS" \
  --target=node \
  --outfile "$BUN_OUTFILE" \
  --external playwright \
  --external playwright-core \
  --external diff \
  --external "bun:sqlite" \
  --external "@ngrok/ngrok"

# Step 2: Post-process
# Replace import.meta.dir with a resolvable reference
perl -pi -e 's/import\.meta\.dir/__browseNodeSrcDir/g' "$DIST_DIR/server-node.mjs"
# Stub out bun:sqlite (macOS-only cookie import, not needed on Windows)
perl -pi -e 's|import { Database } from "bun:sqlite";|const Database = null; // bun:sqlite stubbed on Node|g' "$DIST_DIR/server-node.mjs"

# Step 3: Create the final file with polyfill header injected after the first line
{
  head -1 "$DIST_DIR/server-node.mjs"
  echo '// ── Windows Node.js compatibility (auto-generated) ──'
  echo 'import { fileURLToPath as _ftp } from "node:url";'
  echo 'import { dirname as _dn } from "node:path";'
  echo 'const __browseNodeSrcDir = _dn(_dn(_ftp(import.meta.url))) + "/src";'
  echo '{ const _r = createRequire(import.meta.url); _r("./bun-polyfill.cjs"); }'
  echo '// ── end compatibility ──'
  tail -n +2 "$DIST_DIR/server-node.mjs"
} > "$DIST_DIR/server-node.tmp.mjs"

mv "$DIST_DIR/server-node.tmp.mjs" "$DIST_DIR/server-node.mjs"

# Step 4: Copy polyfill to dist/
cp "$SRC_DIR/bun-polyfill.cjs" "$DIST_DIR/bun-polyfill.cjs"

echo "Node server bundle ready: $DIST_DIR/server-node.mjs"
