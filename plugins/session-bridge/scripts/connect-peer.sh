#!/usr/bin/env bash
# scripts/connect-peer.sh — Connect to a peer by sending a ping.
# Usage: connect-peer.sh [target-id]
#   If target-id is omitted, lists available sessions (excluding self).
#   If exactly one other session exists, auto-connects to it.
#   If multiple exist, prints the list so the agent can pick one.
set -euo pipefail

BRIDGE_DIR="${BRIDGE_DIR:-$HOME/.claude/session-bridge}"
SENDER_ID="${BRIDGE_SESSION_ID:?BRIDGE_SESSION_ID must be set}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSIONS_DIR="$BRIDGE_DIR/sessions"

# If no target given, discover peers
if [ -z "${1:-}" ]; then
  PEERS=()
  PEER_NAMES=()
  PEER_PATHS=()

  for MANIFEST in "$SESSIONS_DIR"/*/manifest.json; do
    [ -f "$MANIFEST" ] || continue
    SID=$(jq -r '.sessionId' "$MANIFEST")
    [ "$SID" != "$SENDER_ID" ] || continue  # Skip self
    PNAME=$(jq -r '.projectName' "$MANIFEST")
    PPATH=$(jq -r '.projectPath' "$MANIFEST")
    PEERS+=("$SID")
    PEER_NAMES+=("$PNAME")
    PEER_PATHS+=("$PPATH")
  done

  if [ ${#PEERS[@]} -eq 0 ]; then
    echo "No other bridge sessions found. Start a bridge in another terminal first." >&2
    exit 1
  elif [ ${#PEERS[@]} -eq 1 ]; then
    # Auto-connect to the only available peer
    TARGET_ID="${PEERS[0]}"
    echo "Auto-connecting to '${PEER_NAMES[0]}' (${TARGET_ID})..." >&2
  else
    # Multiple peers — list them for the agent to pick
    echo "Available sessions:" >&2
    for i in "${!PEERS[@]}"; do
      echo "  ${PEERS[$i]}  ${PEER_NAMES[$i]}  ${PEER_PATHS[$i]}" >&2
    done
    echo "" >&2
    echo "PEERS:${PEERS[*]}" # Machine-readable on stdout
    exit 0
  fi
else
  TARGET_ID="$1"
fi

TARGET_MANIFEST="$SESSIONS_DIR/$TARGET_ID/manifest.json"

if [ ! -f "$TARGET_MANIFEST" ]; then
  echo "Error: Session $TARGET_ID not found." >&2
  exit 1
fi

PEER_NAME=$(jq -r '.projectName' "$TARGET_MANIFEST")
PEER_PATH=$(jq -r '.projectPath' "$TARGET_MANIFEST")

# Check for staleness (>5 min since last heartbeat)
PEER_HB=$(jq -r '.lastHeartbeat' "$TARGET_MANIFEST")
NOW_EPOCH=$(date -u +%s)
HB_EPOCH=$(date -u -jf "%Y-%m-%dT%H:%M:%SZ" "$PEER_HB" +%s 2>/dev/null || date -u -d "$PEER_HB" +%s 2>/dev/null || echo "0")
AGE=$((NOW_EPOCH - HB_EPOCH))
if [ "$AGE" -gt 300 ]; then
  echo "Warning: Session $TARGET_ID appears stale (last active ${AGE}s ago). Connecting anyway." >&2
fi

# Send ping via send-message.sh
BRIDGE_DIR="$BRIDGE_DIR" BRIDGE_SESSION_ID="$SENDER_ID" \
  bash "$SCRIPT_DIR/send-message.sh" "$TARGET_ID" ping "connected" > /dev/null

echo "Connected to '$PEER_NAME' ($TARGET_ID) at $PEER_PATH"
