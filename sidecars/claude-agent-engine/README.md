# Claude Agent Engine Sidecar

This directory contains the future Node/Bun Claude Agent SDK sidecar for Connor.

Connor remains the product state owner. The sidecar is a replaceable agent-engine process that receives one Connor-owned request over stdin and emits Connor-normalized sidecar events over stdout as JSONL.

## Current Status

Phase 2 currently ships the protocol skeleton and a mock sidecar CLI only. It does **not** install or call the real `@anthropic-ai/claude-agent-sdk` package yet.

The next implementation slice should replace the mock internals with Claude Agent SDK `query(prompt, options)` while preserving this protocol.

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

Failure event:

```jsonl
{"runFailed":{"message":"error message"}}
```

stderr is reserved for diagnostics. A non-zero exit code is treated as a transport failure by Swift.

## Real SDK Mapping Plan

When the real SDK is introduced:

1. Read the request JSONL from stdin.
2. Call `query(request.prompt, options)` from `@anthropic-ai/claude-agent-sdk`.
3. Set SDK options from Connor policy envelope:
   - `cwd = request.cwd`
   - `permissionMode = "bypassPermissions"`
   - eventually add `canUseTool` or hooks that report permission requests back to Connor.
4. Map SDK streaming assistant messages to `textDelta` / `textComplete`.
5. Map SDK result messages to `runCompleted` or `runFailed`.
6. Never persist SDK sessions as Connor sessions.

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
