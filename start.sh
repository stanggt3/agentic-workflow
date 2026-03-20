#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BRIDGE_DIR="$SCRIPT_DIR/mcp-bridge"
UI_DIR="$SCRIPT_DIR/ui"

# Ensure bridge is built
if [ ! -f "$BRIDGE_DIR/dist/index.js" ]; then
  echo "Building MCP bridge..."
  (cd "$BRIDGE_DIR" && npm run build)
fi

cleanup() {
  echo ""
  echo "Shutting down..."
  kill 0 2>/dev/null
  wait 2>/dev/null
}
trap cleanup EXIT INT TERM

echo "Starting MCP bridge on :3100..."
(cd "$BRIDGE_DIR" && npm start) &

echo "Starting UI dashboard on :3000..."
(cd "$UI_DIR" && npm run dev) &

wait
