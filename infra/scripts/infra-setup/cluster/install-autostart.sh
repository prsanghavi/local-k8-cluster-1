#!/bin/bash
# Installs (or reinstalls) the launchd agent that auto-starts the k3d cluster on login.
set -euo pipefail

PLIST_NAME="com.samay.k3d-local-cluster-1"
PLIST_SRC="$(cd "$(dirname "$0")/launchd" && pwd)/${PLIST_NAME}.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"

if [ ! -f "$PLIST_SRC" ]; then
  echo "ERROR: plist not found at $PLIST_SRC" >&2
  exit 1
fi

# Unload first if already installed (ignore errors if not loaded)
launchctl unload "$PLIST_DEST" 2>/dev/null || true

cp "$PLIST_SRC" "$PLIST_DEST"
launchctl load "$PLIST_DEST"

echo "✓ LaunchAgent installed: $PLIST_DEST"
echo "  It will auto-start the k3d 'local-cluster-1' cluster on next login."
echo "  Logs: /tmp/k3d-local-cluster-1.log  /tmp/k3d-local-cluster-1.error.log"
