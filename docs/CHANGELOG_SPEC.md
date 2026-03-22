# Unified Changelog & Event ID Specification

## Overview

A persistent, append-only JSONL changelog that aggregates all Claude Code session events with unique IDs. Enables programmatic navigation (deep links), cross-event queries, and dashboard integration.

## Event ID Format

All events use the format `evt-{12 alphanumeric}`, matching CCSB's `msg-{12 alphanumeric}` convention.

```
evt-abc123def456
msg-xyz789ghijk  (bridge messages, existing format)
```

IDs are generated per-event in bash:
```bash
EVENT_ID="evt-$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 12)"
```

## Files

| File | Purpose | Written by |
|------|---------|------------|
| `~/Documents/dev/changelog.jsonl` | Unified index of all events | All hooks |
| `~/Documents/dev/session-milestones.jsonl` | Session lifecycle events | `log-session-milestones.sh` |
| `~/Documents/dev/coordination-log.jsonl` | Bridge query/response pairs | `log-bridge-coordination.sh` |
| `~/Documents/dev/research-log.jsonl` | WebFetch/WebSearch URLs | `log-research.sh` |
| `~/.claude/session-signals/{SESSION_ID}.bridge.json` | Ephemeral dashboard signal | `log-bridge-coordination.sh` |

The individual logs continue to exist with their domain-specific schemas. The changelog is the unified index with a common envelope.

## Changelog Envelope Schema

Every entry in `changelog.jsonl`:

```json
{
  "event_id": "evt-abc123def456",
  "timestamp": "2026-03-22T12:00:00Z",
  "type": "milestone_compaction_auto | research_fetch | research_search | bridge_query_received | bridge_response_received",
  "session_id": "uuid",
  "project": "scrutinizer",
  "deeplink": "claude-history://session/%2FUsers%2F...",
  "summary": "Human-readable one-liner",
  "related_ids": ["msg-xyz789", "evt-previous"]
}
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `event_id` | string | Unique `evt-*` identifier |
| `timestamp` | ISO 8601 | UTC timestamp |
| `type` | string | Event type (prefixed by source) |
| `session_id` | string | Claude Code session UUID |
| `project` | string | Project directory basename |
| `deeplink` | string | `claude-history://` URL to session transcript |
| `summary` | string | Short description for display |
| `related_ids` | string[] | IDs of related events/messages for graph traversal |

### Event Types

| Type | Source | Trigger |
|------|--------|---------|
| `milestone_compaction_auto` | milestones hook | PreCompact (auto) |
| `milestone_compaction_manual` | milestones hook | PreCompact (manual) |
| `milestone_agent_Explore` | milestones hook | SubagentStop (Explore) |
| `milestone_agent_Plan` | milestones hook | SubagentStop (Plan) |
| `milestone_session_end_*` | milestones hook | SessionEnd |
| `research_fetch` | research hook | WebFetch |
| `research_search` | research hook | WebSearch |
| `bridge_query_received` | coordination hook | Bridge query arrives |
| `bridge_response_received` | coordination hook | Bridge response arrives |
| `bridge_ping_received` | coordination hook | Bridge ping arrives |

## Related IDs & Graph Traversal

Events link to each other via `related_ids`:

- **Search results** → parent search event: `["evt-parent-search"]`
- **Bridge responses** → original query message: `["msg-original-query"]`
- **Milestones** → empty by default: `[]`

This enables queries like "find all events related to this bridge message":
```bash
jq 'select(.related_ids[]? == "msg-abc123")' changelog.jsonl
```

## Signal Files

Bridge events emit ephemeral signal files for dashboard visibility (c9watch, claude-code-ui):

**Path**: `~/.claude/session-signals/{SESSION_ID}.bridge.json`

```json
{
  "session_id": "uuid",
  "event_id": "evt-abc123",
  "bridge_event": "bridge_query_received",
  "from_project": "scrutinizer",
  "content_preview": "What shader for foveation?",
  "timestamp": "2026-03-22T12:00:00Z"
}
```

Signal files are write-once per event. Dashboards read and optionally clear them. The event is also persisted to `changelog.jsonl` so nothing is lost.

## Query Examples

```bash
# All events for a project
jq 'select(.project == "scrutinizer")' ~/Documents/dev/changelog.jsonl

# Bridge coordination across all projects
jq 'select(.type | startswith("bridge"))' ~/Documents/dev/changelog.jsonl

# Get deep link for a specific event
jq 'select(.event_id == "evt-abc123") | .deeplink' ~/Documents/dev/changelog.jsonl

# Trace a bridge exchange: find response to a query
jq 'select(.related_ids[]? == "msg-original-query-id")' ~/Documents/dev/changelog.jsonl

# Recent activity (last 20 events)
tail -20 ~/Documents/dev/changelog.jsonl | jq -r '"\(.timestamp) \(.type) \(.summary)"'

# Count events by type
jq -r '.type' ~/Documents/dev/changelog.jsonl | sort | uniq -c | sort -rn
```

## Integration Points

### claude-code-history-viewer
- `deeplink` field contains `claude-history://` URLs matching the deep-link-protocol spec
- `event_id` can serve as anchor for scroll-to-message navigation
- Bridge events in milestones carry `bridge.from_deeplink` for cross-session links

### interests2025 / Qdrant
- `changelog.jsonl` can be ingested via a new `ingest_changelog.js` script
- Embed `summary` field for semantic search over session activity
- `event_id` as Qdrant point ID for deduplication

### c9watch / claude-code-ui
- Signal files at `~/.claude/session-signals/` follow existing conventions
- `bridge_event` type distinguishes bridge signals from native working/stop/permission signals

### FrakBot / OpenClaw
- `coordination-log.jsonl` entries with `event_id` are publishable narrative
- Deep links on both sides provide verifiable provenance
- The unified changelog is the source for "Adventures in AI Coding" content
