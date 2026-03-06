# Prepare Paperclip for production.
# Installs production deps if lockfile changed. Build is done locally and synced via make sync-app.
# Note: set -euo pipefail is provided by writeShellApplication wrapper.

PAPERCLIP_DIR="${1:?Usage: paperclip-prepare <paperclip-dir>}"
cd "$PAPERCLIP_DIR"

STAMP_DIR="${PAPERCLIP_DIR}/.paperclip-build"
STAMP="${STAMP_DIR}/.install-stamp"
LOCKFILE="pnpm-lock.yaml"

if [ ! -f "$LOCKFILE" ]; then
  echo "ERROR: ${LOCKFILE} not found in ${PAPERCLIP_DIR}"
  echo "Has the app code been deployed? Try: make sync-app"
  exit 1
fi

if [ ! -f "server/dist/index.js" ]; then
  echo "ERROR: server/dist/index.js not found in ${PAPERCLIP_DIR}"
  echo "Build locally first (pnpm build), then: make sync-app"
  exit 1
fi

CURRENT_HASH=$(sha256sum "$LOCKFILE" | cut -d' ' -f1)

PREV_HASH=""
if [ -f "$STAMP" ]; then
  PREV_HASH=$(cat "$STAMP")
fi

if [ "$CURRENT_HASH" = "$PREV_HASH" ] && [ -d "node_modules" ]; then
  echo "Dependencies up to date, skipping install"
else
  echo "Lock file changed (prev: ${PREV_HASH:-none}, current: ${CURRENT_HASH})"
  echo "Running pnpm install (prod only)..."

  # Production-only install, skip postinstall scripts (esbuild/embedded-postgres try to
  # download binaries which fails in the NixOS sandbox — they are not needed at runtime).
  pnpm install --frozen-lockfile --prod --ignore-scripts

  mkdir -p "$STAMP_DIR"
  echo "$CURRENT_HASH" > "$STAMP"
  echo "Install complete"
fi

# Always apply publishConfig so workspace packages resolve to compiled dist/ output
# rather than TypeScript source files. Workspace package.json files use src/ exports
# for local development but production needs dist/ exports. This is idempotent.
if [ -f "scripts/apply-publish-config.mjs" ]; then
  echo "Applying publishConfig exports..."
  node scripts/apply-publish-config.mjs
else
  echo "WARNING: scripts/apply-publish-config.mjs not found — workspace packages may fail to resolve"
fi
