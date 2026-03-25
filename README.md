<p align="center">
  <h1 align="center">session-bridge</h1>
  <p align="center">
    <strong>Peer-to-peer communication between Claude Code sessions</strong>
  </p>
  <p align="center">
    <a href="https://github.com/PatilShreyas/claude-code-session-bridge/actions/workflows/test.yml"><img src="https://github.com/PatilShreyas/claude-code-session-bridge/actions/workflows/test.yml/badge.svg" alt="Tests"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  </p>
  <p align="center">
    <a href="#getting-started">Quick Start</a> &middot;
    <a href="#commands">Commands</a> &middot;
    <a href="#how-it-works">How It Works</a> &middot;
    <a href="#when-to-use-it">Use Cases</a> &middot;
    <a href="#known-limitations">Limitations</a>
  </p>
</p>

---

When you're working across multiple repos — a shared library and its consumer app, a backend and frontend, microservices — each Claude Code session is isolated. **session-bridge** lets them talk to each other.

The Library agent answers questions about breaking changes. The Consumer agent asks what API replaced a deprecated function. The agent responds with its **full context** — no approximation, no extra API cost.

Neither session has to stop working. With **cooperative listening**, both sessions stay productive — queries arrive and get answered automatically on the next user turn, no blocking required.

https://github.com/user-attachments/assets/ce893322-5749-42be-9973-e36e60b969a6

## Getting Started

### 1. Install

```bash
# Install jq (required)
brew install jq        # macOS
sudo apt install jq    # Linux

# Install the plugin
claude plugin marketplace add PatilShreyas/claude-code-session-bridge
claude plugin install session-bridge
```

<details>
<summary>Alternative: install via git clone</summary>

```bash
git clone https://github.com/PatilShreyas/claude-code-session-bridge.git ~/claude-code-session-bridge
```

Then start Claude with:
```bash
claude --plugin-dir ~/claude-code-session-bridge/plugins/session-bridge
```

Or add to `~/.claude/settings.json` for permanent loading:
```json
{
  "plugins": ["~/claude-code-session-bridge/plugins/session-bridge"]
}
```

</details>

### 2. Use it

Open two terminals — one for each project.

**Terminal 1** (the library):
```
cd ~/projects/my-library && claude

> /bridge start
Session ID: a1b2c3
```

**Terminal 2** (the consumer app):
```
cd ~/projects/my-app && claude

> /bridge connect a1b2c3
Connected to 'my-library'

> /bridge ask "What breaking changes did you make?"

Response from my-library:
  3 breaking changes in v2.0:
  1. login() → authenticate() — takes a Config object
  2. getUser() → getCurrentUser() — returns UserProfile
  3. Removed refreshToken() — now automatic
```

That's it. Neither session had to stop what it was doing. The Library agent received the query on its next turn, responded with its **full session context**, and went back to work. No extra API calls, no approximation.

## Commands

| Command | Description |
|---------|-------------|
| `/bridge start` | Register this session as a bridge peer |
| `/bridge connect <id>` | Connect to a peer session (auto-starts if needed) |
| `/bridge ask <question>` | Send a question and wait for the response |
| `/bridge peers` | List all active sessions on this machine |
| `/bridge status` | Show session ID, connected peers, pending messages |
| `/bridge listen` | Enter dedicated listening mode (blocks session — see below) |
| `/bridge stop` | Disconnect, notify peers, clean up |

> **Tip:** You don't always need explicit commands. Just tell your agent "ask the library about X" in natural language and it will use the bridge automatically.

## How It Works

### Cooperative listening (default)

After `/bridge start`, sessions answer peer queries **automatically** — no dedicated listener needed. The `UserPromptSubmit` hook checks for pending messages on every user turn. When one is found, the agent responds to the query first, then handles the user's actual prompt.

Both sessions stay productive. The tradeoff: responses arrive when the listener's user next interacts. If a session is idle for minutes, queries wait.

```
1. Session A (library) does /bridge start → ID a1b2c3
2. Session B (consumer) does /bridge connect a1b2c3
3. Session B does /bridge ask "What changed in the auth API?"
4. Session A's user types their next prompt (anything)
5. Hook fires → agent sees the pending query → responds → continues with user's prompt
6. Session B receives the answer
```

### Dedicated listening mode

For instant responses, `/bridge listen` puts the agent into a **continuous listening loop**. The agent does nothing but answer peer queries until the user presses Ctrl+C.

Use this when you need sub-second response times or when the listening session has no other work to do.

### Why it works

- **No background process** — the agent IS the responder
- **No `claude -p` calls** — zero extra API cost for responses
- **Full context** — the agent that made the changes answers questions about them
- **Includes real code** — responses contain actual file contents, not just descriptions

**Design principles:**
- No shared mutable state — each session owns its manifest
- Atomic file writes — temp file + `mv` prevents partial reads
- UUID message IDs — no collision risk
- Connection via ping handshake — peers never mutate each other's manifests

---

## When To Use It

### Great for

> **Multi-repo coordination** — Library + consumer app, SDK + client, shared module + services

You make breaking changes in the library. Instead of context-switching to the consumer app and manually explaining what changed, the consumer agent asks the library agent directly.

> **Backend + Frontend** — API changes that affect both sides

Backend session changes an endpoint's response format. Frontend session asks "what does the new response look like?" and gets the actual schema, not a stale doc.

> **Microservices** — Service A depends on Service B's contract

Service B renames a field in its API. Service A's agent asks Service B's agent what changed and updates the client code automatically.

> **Monorepo modules** — Independent modules that depend on each other

Module X changes an internal interface. Module Y's agent queries Module X about the new type signatures and applies the fix.

> **Migration assistance** — Upgrading dependencies with breaking changes

Your agent can ask the dependency's agent: "I'm on v1.3. What do I need to change for v2.0?" and get a step-by-step migration with actual code.

### Not designed for

- **Real-time chat** between humans (it's agent-to-agent communication)
- **Remote collaboration** across machines (local-only via filesystem)
- **CI/CD pipelines** (sessions are tied to interactive Claude Code)
- **Persistent messaging** (messages don't survive session cleanup)

## Example Scenarios

### Scenario 1: Dependency upgrade with breaking changes

```
Consumer: "Update our app to use auth-sdk v2.0"
  Agent detects version bump → proactively queries library peer
  Agent: "Asking auth-sdk about breaking changes..."
  Library responds with changes + migration steps
  Agent applies all changes automatically
  Agent: "Done. Updated 4 files, ran tests, all passing."
```

### Scenario 2: Back-and-forth clarification

```
Consumer: /bridge ask "How should I handle the new error types?"
  Library: "What error types are you currently catching? Send me your error handler."
  Consumer: (reads its own code, sends the relevant function)
  Library: "Replace AuthError with AuthException. Here's the new hierarchy: ..."
  Consumer: applies the fix
```

### Scenario 3: Natural language (no /bridge command needed)

```
Consumer user: "Ask the backend team what the new API response format looks like
               for the /users endpoint and update our models accordingly"
  Agent queries the backend peer
  Agent gets the response with actual schema
  Agent updates the model classes
  Agent: "Updated UserResponse model to match new schema."
```

### Scenario 4: Multiple peers

```
> /bridge peers
SESSION    PROJECT              STATUS   PATH
-------    -------              ------   ----
a1b2c3     auth-sdk             active   ~/projects/auth-sdk
d4e5f6     payments-service     active   ~/projects/payments
g7h8i9     my-app               active   ~/projects/my-app  (you)

> /bridge ask "What config format does the payments service expect?"
  Routes to payments-service peer automatically based on question context
```

## Dos and Don'ts

### Do

- **Just use `/bridge start`** — cooperative listening is the default. Both sessions keep working and answer queries on their next turn.
- **Use natural language** — "ask the backend what changed" works just as well as `/bridge ask`.
- **Let agents share real code** — responses include actual file contents, type definitions, and function signatures. Ask for them specifically if the agent gives you prose instead.
- **Use for version upgrades** — "update to v2.0" will proactively query the peer about breaking changes before even trying to build.
- **Use back-and-forth** — if the responder needs more info, it'll ask a follow-up question. The other side answers and re-queries automatically.
- **Clean up** — run `/bridge stop` when done, or stale sessions accumulate.

### Don't

- **Don't use it as a chat app** — it's designed for agent-to-agent coordination, not human conversation. The agents talk; you give them tasks.
- **Don't send secrets** — messages are plain JSON on the local filesystem. No encryption. Don't ask a peer to "send me the API keys."
- **Don't expect remote access** — both sessions must be on the same machine. It uses the local filesystem (`~/.claude/session-bridge/`), not a network protocol.
- **Don't use it for large file transfers** — message content is passed as shell arguments. Share file paths or describe locations instead of pasting entire files into queries.
- **Don't leave sessions running forever** — stale sessions from killed terminals persist until manually cleaned up with `/bridge stop` or `/bridge peers` + cleanup.
- **Don't expect instant responses in cooperative mode** — queries wait until the listener's user next interacts. For faster responses, use `/bridge listen`.

## Known Limitations

### Response latency in cooperative mode

With cooperative listening, queries wait until the responding session's user types their next prompt. If a session is idle for several minutes, the query sits in the inbox. Use `/bridge listen` when you need immediate responses from an otherwise-idle session.

### Session is occupied in dedicated listen mode

When a session is in `/bridge listen` mode, it's dedicated to answering peer queries. The user can't use it for other work until they press Ctrl+C. This only applies to `/bridge listen` — cooperative listening (the default) has no such restriction.

### Platform support

| Platform | Status |
|----------|--------|
| macOS | Tested |
| Linux | Should work (GNU `date` fallback) |
| Windows | Not supported yet |

### Other considerations

- **Polling interval** — `/bridge listen` checks every 3 seconds. Cooperative mode checks on each user turn.
- **No encryption** — Messages are plain JSON, protected by Unix file permissions.
- **Session accumulation** — Crashed sessions may persist. Use `/bridge peers` to check, `/bridge stop` to clean up.
- **Single machine only** — Communication is via local filesystem. No network/remote support.

## Plugin Structure

<details>
<summary>Click to expand</summary>

```
plugins/session-bridge/
├── .claude-plugin/
│   └── plugin.json
├── commands/
│   └── bridge.md                # /bridge command (all subcommands)
├── hooks/
│   └── hooks.json               # SessionEnd cleanup, PreCompact preservation
├── skills/
│   └── bridge-awareness/
│       └── SKILL.md             # Teaches agent the bridge protocol
├── scripts/
│   ├── register.sh              # Create session directory and manifest
│   ├── send-message.sh          # Send message to peer's inbox
│   ├── check-inbox.sh           # Scan inboxes for pending messages
│   ├── list-peers.sh            # List active sessions
│   ├── connect-peer.sh          # Ping to establish connection
│   ├── heartbeat.sh             # Update session heartbeat
│   ├── cleanup.sh               # Remove session, notify peers
│   ├── bridge-listen.sh         # Block until message arrives
│   └── bridge-receive.sh        # Block until specific response arrives
├── test.sh                      # Run all tests
└── tests/
    ├── test-helpers.sh           # Shared assertions
    ├── test-register.sh
    ├── test-send-message.sh
    ├── test-check-inbox.sh
    ├── test-list-peers.sh
    ├── test-connect-peer.sh
    ├── test-cleanup.sh
    ├── test-heartbeat.sh
    ├── test-bridge-listen.sh
    ├── test-bridge-receive.sh
    └── test-integration.sh       # End-to-end two-session test
```

</details>

## Running Tests

```bash
cd plugins/session-bridge
bash test.sh
```

## Contributing

Contributions are welcome! Please open an issue or PR.

## License

[MIT](LICENSE)
