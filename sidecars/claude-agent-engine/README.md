# Claude Agent Engine Sidecar

This directory contains the future Node/Bun Claude Agent SDK sidecar for Connor.

Connor remains the product state owner. The sidecar is a replaceable agent-engine process that receives one Connor-owned request over stdin and emits Connor-normalized sidecar events over stdout as JSONL.

## Current Status

Phase 2 ships both:

- a real SDK entry point: `claude-sidecar.mjs`
- local protocol mocks: `mock-sidecar.mjs` and `mock-sidecar.sh`

The real entry point imports `@anthropic-ai/claude-agent-sdk` and calls `query(prompt, options)`, but Connor does **not** enable it by default. Swift tests include a gated integration path that only runs when explicitly requested by environment variables.

The sidecar now also emits normalized tool and permission boundary events. These events let Connor render/audit SDK tool activity without granting the SDK product-state authority.

## Request Protocol

Swift writes exactly one JSON line to stdin:

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
6. Maps deferred or denied tool-use states into `permissionRequested` / failed tool results.
7. Emits `textComplete` and `runCompleted` after the SDK stream finishes.
8. Emits `runFailed` for SDK errors or non-success result messages.
9. Never persists SDK sessions as Connor sessions.

Before enabling write-capable tools by default, Connor still needs product-level approval flow and audit UI for these normalized events.

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
