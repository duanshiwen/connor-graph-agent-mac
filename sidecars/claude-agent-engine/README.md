# Claude Agent Engine Sidecar

This directory contains the future Node/Bun Claude Agent SDK sidecar for Connor.

Connor remains the product state owner. The sidecar is a replaceable agent-engine process that can receive either a backward-compatible raw Connor request or persistent command envelopes over stdin, then emit Connor-normalized sidecar events over stdout as JSONL. Swift has a persistent process transport for command-loop sidecars, and `claude-sidecar.mjs` now declares the matching command-loop skeleton.

## Current Status

Phase 2 ships both:

- a real SDK entry point: `claude-sidecar.mjs`
- local protocol mocks: `mock-sidecar.mjs` and `mock-sidecar.sh`

The real entry point imports `@anthropic-ai/claude-agent-sdk` and calls `query(prompt, options)`, but Connor does **not** enable it by default. Swift tests include a gated integration path that only runs when explicitly requested by environment variables.

The sidecar now also emits normalized tool and permission boundary events. These events let Connor render/audit SDK tool activity without granting the SDK product-state authority. The real `claude-sidecar.mjs` entry point supports the persistent `approvalResolved` command for Connor-owned deferred tool approval: SDK `tool_deferred` results are surfaced as `permissionRequested`, the sidecar keeps the session transport open, and Connor approval or denial is sent back through the command loop.

## Request Protocol

Swift currently writes exactly one start request JSON line to stdin:

```json
{
  "connorRunID": "run-id",
  "connorSessionID": "session-id",
  "groupID": "default",
  "prompt": "User prompt",
  "cwd": "/path/to/project",
  "permissionMode": "askToWrite",
  "sdkPermissionMode": "bypassPermissions",
  "sdkSessionID": null,
  "ownsProductState": false
}
```

Rules:

- `connorRunID` and `connorSessionID` are authoritative product IDs.
- `sdkSessionID` is optional metadata only.
- `ownsProductState` must remain `false`.
- `sdkPermissionMode` is intentionally `bypassPermissions`; Connor owns permission and audit.
- The sidecar must not write graph memory directly.

## Event Protocol

The sidecar emits one JSON object per line to stdout:

```jsonl
{"runStarted":{"sdkSessionID":"claude-sdk-session-id"}}
{"textDelta":{"text":"Hello"}}
{"textComplete":{"text":"Hello from Claude","citations":[],"contextSnapshot":null}}
{"runCompleted":{}}
```

Tool / permission boundary events:

```jsonl
{"toolUseRequested":{"toolCallID":"tool-1","name":"Read","inputJSON":"{\"file_path\":\"README.md\"}"}}
{"permissionRequested":{"requestID":"permission-tool-1","capability":"readSession","toolName":"Read","payloadJSON":"{\"file_path\":\"README.md\"}"}}
{"toolUseStarted":{"toolCallID":"tool-1","name":"Read"}}
{"toolUseCompleted":{"toolCallID":"tool-1","name":"Read","contentText":"README contents","contentJSON":null,"isError":false}}
```

Persistent approval resume events:

```jsonl
{"resumeAccepted":{"requestID":"permission-tool-1","toolName":"Write","message":"Resume accepted by fake sidecar"}}
{"resumeRejected":{"requestID":"permission-tool-2","toolName":"Bash","reason":"Denied by reviewer"}}
```

These are protocol-level events used by the persistent sidecar command loop. They acknowledge whether a Connor-owned `approvalResolved` command resumed or rejected a deferred SDK tool request. Connor pending approvals and audit history remain authoritative.

Failure event:

```jsonl
{"runFailed":{"message":"error message"}}
```

stderr is reserved for diagnostics. A non-zero exit code is treated as a transport failure by Swift.

## Real SDK Mapping

`claude-sidecar.mjs`:

1. Reads the request JSONL from stdin.
2. Calls `query(request.prompt, options)` from `@anthropic-ai/claude-agent-sdk`.
3. Sets SDK options from Connor policy envelope:
   - `cwd = request.cwd`
   - `permissionMode = request.sdkPermissionMode`
   - `resume = request.sdkSessionID ?? undefined`
   - `includePartialMessages = true`
4. Maps SDK assistant-like messages to `textDelta`.
5. Maps SDK `tool_use` / `tool_result`-like content into normalized tool events.
6. Maps denied tool-use states into failed tool results.
7. Maps SDK `tool_deferred` states into `permissionRequested` and waits for a Connor `approvalResolved` command instead of failing the run.
8. Emits `textComplete` and `runCompleted` after the SDK stream finishes.
9. Emits `runFailed` for SDK errors or non-success result messages. Deferred permission waiting is not a failure condition.
10. Never persists SDK sessions as Connor sessions.

## Approval Resolution Command and Session Transport Skeleton

Connor now has a Swift-side command envelope for the Connor → sidecar resume path. `ClaudeSDKSidecarProcessTransport` implements the command transport boundary for `.start(...)` while preserving the direct request shape shown above. It explicitly rejects `.approvalResolved(...)` because it is still a one-shot process transport; the persistent session transport is required for approval resume.

Swift also defines `ClaudeSDKSidecarSessionTransport`:

```swift
public protocol ClaudeSDKSidecarSessionTransport: Sendable {
    func start(_ request: ClaudeSDKSidecarRequest) async -> AsyncThrowingStream<ClaudeSDKSidecarEvent, Error>
    func send(_ command: ClaudeSDKSidecarCommand) async throws
    func cancel() async
}
```

That protocol is the persistent streaming boundary for sending `approvalResolved` after the initial start request. Current tests use both a fake session transport and a Swift persistent process transport fixture to prove that an approval command can produce `resumeAccepted` or `resumeRejected`. The real Node sidecar implements the same command envelope for deferred SDK tools.

```jsonl
{"approvalResolved":{"connorRunID":"run-id","connorSessionID":"session-id","requestID":"permission-tool-1","status":"approved","outcome":"approved","capability":"commitGraphWrite","toolName":"Write","payloadJSON":"{}","reason":"Human reviewer approved the write","actor":"human-reviewer","ownsProductState":false}}
```

Swift persistent process transport status:

- `ClaudeSDKSidecarPersistentProcessTransport` writes command envelopes as JSONL to stdin.
- It streams stdout JSONL events as they arrive.
- It supports `cancel()` by closing stdin and terminating the process if needed.
- The real Node sidecar implements the command envelope skeleton for `start`, `approvalResolved`, and `cancel`.

Rules:

- `approvalResolved` is driven by Connor `agent_pending_approvals`, not by the SDK.
- `ownsProductState` remains `false`; the sidecar must not become the approval ledger.
- `approved` maps to SDK/tool continuation intent.
- `denied` and `cancelled` both map to denied execution outcome; `cancelled` remains distinct only in Connor pending-approval state and audit history.
- `resumeAccepted` / `resumeRejected` confirm whether the persistent sidecar accepted or rejected Connor's approval resolution for the deferred SDK tool.
- `approvalResolved` in `claude-sidecar.mjs` looks up Connor-tracked deferred SDK tool uses and resumes the same SDK session only after Connor approval.
- The resume path follows the official hook round trip: `PreToolUse` returns `permissionDecision: "defer"`; SDK returns `tool_deferred` with `deferred_tool_use`; Connor approval resumes with `permissionDecision: "allow"` and `updatedInput`.
- This does not make the SDK the permission ledger; Connor pending approvals, audit, and native timeline remain authoritative.

## Real SDK Local Run

Install dependencies in this directory, then run:

```bash
npm install
node claude-sidecar.mjs <<'EOF'
{"connorRunID":"run-1","connorSessionID":"session-1","groupID":"default","prompt":"Reply with hello","cwd":"/tmp","permissionMode":"readOnly","sdkPermissionMode":"bypassPermissions","sdkSessionID":null,"ownsProductState":false}
EOF
```

Optional Swift integration test:

```bash
CONNOR_RUN_CLAUDE_SIDECAR_INTEGRATION=1 \
CONNOR_CLAUDE_SIDECAR_RUNTIME=/absolute/path/to/node \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --filter realClaudeSDKSidecarIntegrationSkipsUnlessExplicitlyEnabled
```

## Local Mocks

If Node or Bun is available, run the JavaScript mock:

```bash
node mock-sidecar.mjs <<'EOF'
{"connorRunID":"run-1","connorSessionID":"session-1","groupID":"default","prompt":"Hello","cwd":"/tmp","permissionMode":"readOnly","sdkPermissionMode":"bypassPermissions","sdkSessionID":null,"ownsProductState":false}
EOF
```

For machines without Node/Bun, use the POSIX shell mock to smoke-test the JSONL protocol:

```bash
./mock-sidecar.sh <<'EOF'
{"connorRunID":"run-1","connorSessionID":"session-1","groupID":"default","prompt":"Hello","cwd":"/tmp","permissionMode":"readOnly","sdkPermissionMode":"bypassPermissions","sdkSessionID":null,"ownsProductState":false}
EOF
```
