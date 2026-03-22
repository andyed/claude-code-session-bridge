#!/usr/bin/env bash
# scripts/register.sh — Register this session as a bridge peer.
# Env: BRIDGE_DIR (default: ~/.claude/session-bridge), PROJECT_DIR (default: pwd)
#      BRIDGE_TRANSCRIPT_PATH (optional: Claude Code transcript path for deep links)
# Outputs: session ID to stdout
# If a bridge session already exists for this project, reuses it.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "Error: jq is required. Install with: brew install jq (macOS) or apt install jq (Linux)" >&2; exit 1; }

BRIDGE_DIR="${BRIDGE_DIR:-$HOME/.claude/session-bridge}"
PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
PROJECT_NAME=$(basename "$PROJECT_DIR")
BRIDGE_SESSION_FILE="$PROJECT_DIR/.claude/bridge-session"

# Reuse existing session if the bridge-session file exists and points to a valid session
if [ -f "$BRIDGE_SESSION_FILE" ]; then
  EXISTING_ID=$(cat "$BRIDGE_SESSION_FILE")
  EXISTING_DIR="$BRIDGE_DIR/sessions/$EXISTING_ID"

  if [ -d "$EXISTING_DIR" ] && [ -f "$EXISTING_DIR/manifest.json" ]; then
    # Update heartbeat and reuse
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    TMP=$(mktemp "$EXISTING_DIR/manifest.XXXXXX")
    jq --arg hb "$NOW" '.lastHeartbeat = $hb' "$EXISTING_DIR/manifest.json" > "$TMP"
    mv "$TMP" "$EXISTING_DIR/manifest.json"
    echo -n "$EXISTING_ID"
    exit 0
  fi
fi

# Create new session
SESSION_ID=$(set +o pipefail; LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 6)

SESSION_DIR="$BRIDGE_DIR/sessions/$SESSION_ID"
mkdir -p "$SESSION_DIR/inbox" "$SESSION_DIR/outbox"

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Optional deep link fields from env
TRANSCRIPT="${BRIDGE_TRANSCRIPT_PATH:-}"
DEEPLINK=""
if [ -n "$TRANSCRIPT" ]; then
  ENCODED=$(echo "$TRANSCRIPT" | python3 -c "import sys,urllib.parse;print(urllib.parse.quote(sys.stdin.read().strip(),safe=''))" 2>/dev/null || echo "")
  [ -n "$ENCODED" ] && DEEPLINK="claude-history://session/${ENCODED}"
fi

MANIFEST_TMP=$(mktemp "$SESSION_DIR/manifest.XXXXXX")
jq -n \
  --arg sid "$SESSION_ID" \
  --arg pname "$PROJECT_NAME" \
  --arg ppath "$PROJECT_DIR" \
  --arg now "$NOW" \
  --arg tp "$TRANSCRIPT" \
  --arg dl "$DEEPLINK" \
  '{
    sessionId: $sid,
    projectName: $pname,
    projectPath: $ppath,
    transcriptPath: $tp,
    deeplink: $dl,
    startedAt: $now,
    lastHeartbeat: $now,
    status: "active",
    capabilities: ["query", "context-dump", "conversation"]
  }' > "$MANIFEST_TMP"
mv "$MANIFEST_TMP" "$SESSION_DIR/manifest.json"

mkdir -p "$PROJECT_DIR/.claude"
echo -n "$SESSION_ID" > "$BRIDGE_SESSION_FILE"

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "BRIDGE_SESSION_ID=$SESSION_ID" >> "$CLAUDE_ENV_FILE"
fi

echo -n "$SESSION_ID"
