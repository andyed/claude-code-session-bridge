# Cooperative Listening & Deep Link Metadata

This document describes two enhancements to session-bridge that make it work better for multi-session workflows where sessions are actively working (not dedicated listeners).

## Problem

The original `/bridge listen` command blocks the listening session entirely. The agent enters an infinite poll loop and can do nothing else. For workflows with 3-5 concurrent sessions on related projects, dedicating one session as a listener is wasteful.

## Cooperative Listening

session-bridge already has the infrastructure for non-blocking message delivery: the `UserPromptSubmit` hook runs `check-inbox.sh` on every user turn. When pending messages are found, they're injected as a `systemMessage` directive. The agent sees the message, responds, and continues with the user's actual request.

**No code changes were needed.** The fix is documentation and framing:

- `SKILL.md` now documents Cooperative Listening as the default mode
- `/bridge listen` is reframed as "dedicated listening mode" for specialized use cases
- The help text prioritizes `start` → `ask` over `start` → `listen`

### How it works in practice

1. Session A (scrutinizer) does `/bridge start`, gets ID `abc123`
2. Session B (psychodeli) does `/bridge start`, `/bridge connect abc123`
3. Session B does `/bridge ask "What visual clutter metric are you using?"`
4. Session A's user types their next prompt (anything)
5. The `UserPromptSubmit` hook fires, `check-inbox.sh` finds the pending query
6. Session A's agent sees: "CLAUDE BRIDGE: 1 pending message — query from psychodeli..."
7. Agent responds to the query via `send-message.sh`, then handles the user's actual prompt
8. Session B's `bridge-receive.sh` picks up the response

**Tradeoff:** Responses arrive when the listener's user next interacts. If idle for minutes, queries wait. For instant responses, use `/bridge listen`.

## Deep Link Metadata

Messages and manifests now carry optional transcript and deep link fields, enabling external tools to navigate directly to the conversation context where a bridge exchange happened.

### Message metadata (send-message.sh)

New optional fields in the `metadata` object:

```json
{
  "metadata": {
    "urgency": "normal",
    "fromProject": "scrutinizer",
    "transcriptPath": "/Users/user/.claude/projects/.../session.jsonl",
    "deeplink": "claude-history://session/%2FUsers%2Fuser%2F...",
    "messageUuid": ""
  }
}
```

These are populated automatically from the session manifest's `transcriptPath` field. Callers can also set `BRIDGE_TRANSCRIPT_PATH` and `BRIDGE_MESSAGE_UUID` environment variables to override.

When not set, the fields are empty strings — fully backward compatible.

### Manifest enrichment (check-inbox.sh)

The `UserPromptSubmit` hook receives `transcript_path` in its stdin JSON. `check-inbox.sh` now reads this and writes it into the session manifest if not already present. This means the manifest gets enriched on the first user interaction after `/bridge start`, without the user needing to pass any extra flags.

### Manifest fields (register.sh)

New optional fields in the manifest:

```json
{
  "sessionId": "abc123",
  "projectName": "scrutinizer",
  "projectPath": "/Users/user/dev/scrutinizer",
  "transcriptPath": "/Users/user/.claude/projects/.../session.jsonl",
  "deeplink": "claude-history://session/%2FUsers%2Fuser%2F...",
  "startedAt": "...",
  "lastHeartbeat": "...",
  "status": "active",
  "capabilities": ["query", "context-dump", "conversation"]
}
```

Set via `BRIDGE_TRANSCRIPT_PATH` env var at registration time, or enriched automatically by `check-inbox.sh` on first hook invocation.

## Use Cases

### External tool integration

A coordination log reader can parse bridge messages and render clickable links to both sides of the conversation — the asker's session and the responder's session.

### Session history visualization

Tools like [claude-code-history-viewer](https://github.com/soooyoung-k/claude-code-history-viewer) can render coordination edges between session timelines, showing when and where cross-session queries happened.

### Audit trail

The deep link in each message creates a verifiable provenance chain: you can trace a decision back through the bridge exchange to the original conversation context where it was made.
