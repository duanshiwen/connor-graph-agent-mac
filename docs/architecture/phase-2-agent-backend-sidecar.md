# Phase 2: AgentBackend Abstraction and Claude SDK Sidecar

Last updated: 2026-06-11 15:52 GMT+8

## Status

Phase 2 introduces the Swift-side backend boundary for replacing agent engines without moving product state out of Connor.

This phase does **not** embed the Claude Agent SDK directly into the macOS app. The SDK remains an external sidecar engine. Connor owns sessions, graph memory, permissions, audit, and UI state.

Current implementation status:

- `AgentBackend` is the product-level backend interface.
- `NativeSessionManager` depends on `AnyAgentBackend`, not a concrete SDK or model provider.
- `NativeSessionManager` can persist backend-emitted `AgentEvent` streams through `AgentEventRecorder` when the backend itself does not already record events.
- `AgentLoopBackend` adapts the existing native loop.
- `ClaudeSDKSidecarBackend` maps sidecar events into Connor `AgentEvent`, including normalized tool and permission boundary events.
- `ClaudeSDKSidecarProcessTransport` runs an external process and bridges one request plus JSONL sidecar events over stdin/stdout.
- `ClaudeSDKSidecarSessionTransport` is now a Swift protocol for long-lived sidecar sessions that can receive Connor-owned commands after start.
- `ClaudeSDKSidecarPersistentProcessTransport` implements that long-lived Swift-side process boundary with persistent stdin command writes, stdout JSONL event streaming, stderr diagnostics, and cancellation.
- `sidecars/claude-agent-engine/` contains protocol docs, mock Node/shell sidecars, and the real `claude-sidecar.mjs` SDK entry point.
- `claude-sidecar.mjs` now includes a persistent command-loop skeleton for `start`, `approvalResolved`, and `cancel` command envelopes while preserving backward-compatible raw request input.

## Boundary

```text
NativeSessionManager
  owns Connor session persistence and transcript updates
  calls AgentBackend.chat(request)

AgentBackend
  returns normalized Connor AgentEvent stream
  does not own product state

AgentLoopBackend
  adapts the existing native AgentLoopController into AgentBackend

ClaudeSDKSidecarBackend
  adapts Claude SDK sidecar IPC events into Connor AgentEvent
  uses Connor run/session IDs as authoritative IDs
```

## Claude SDK Sidecar Rules

The Claude Agent SDK is used as a backend engine only.

Allowed:

- SDK performs agent loop work inside a sidecar process.
- SDK can provide streaming text, tool-loop events, MCP capabilities, hooks, and subagent behavior.
- Sidecar may return SDK metadata such as SDK session ID.
- Connor records SDK metadata as secondary metadata.

Forbidden:

- SDK session ID becoming Connor session ID.
- SDK permission system becoming Connor permission system.
- SDK writing graph memory directly.
- SDK owning audit logs.
- SDK reading/writing app configuration outside an explicitly provided working directory and policy envelope.
- Swift UI depending on SDK-specific event types.

## Permission Mapping

Phase 2 intentionally sends sidecar requests with:

```text
sdkPermissionMode = bypassPermissions
ownsProductState = false
```

This follows the Craft Agents OSS lesson: use SDK capabilities, but keep the product permission layer in the OS.

Connor `AgentPermissionMode` remains the product-level permission source of truth:

- `readOnly`
- `askToWrite`
- `trustedWrite`
- `allowAll`

The sidecar reports tool and permission boundary events back as normalized Connor `AgentEvent` values. Factory-created Claude sidecar `NativeSessionManager` instances persist those events into the SQLite `agent_events` timeline through `AgentEventRecorder`, create Connor-owned `agent_pending_approvals` records for normalized `permissionRequested` events, and render tool/permission events with tool names, call IDs, request IDs, and compact payload summaries for the native timeline UI. Pending approvals can now be resolved through Connor product APIs: approval resolution updates the pending record, writes an `AgentAuditEvent.permissionDecision`, and appends a `permissionResolved` timeline event that is rendered as approved/denied/needs-approval in the timeline. The macOS app now has a native "权限审批" surface that lists pending approvals and lets the reviewer approve, deny, or cancel them. Connor also has a Swift-side `ClaudeSDKSidecarCommand.approvalResolved` protocol skeleton for future Connor → sidecar resume, with `ownsProductState = false` preserved. `ClaudeSDKSidecarProcessTransport` now implements a command transport boundary for `.start(...)` while preserving the legacy one-line request shape, and explicitly rejects `.approvalResolved(...)` until a persistent streaming session transport exists. `ClaudeSDKSidecarSessionTransport` now defines that future persistent boundary with `start(_:)`, `send(_:)`, and `cancel()`; fake transport tests prove that `.approvalResolved(...)` can yield protocol-level `resumeAccepted` / `resumeRejected` events without touching the current one-shot process path. Write-capable sidecar tools still must not become default until that skeleton is connected to safe execution-resume semantics.

## IPC Contract

Swift-side request model:

```swift
ClaudeSDKSidecarRequest
  connorRunID
  connorSessionID
  groupID
  prompt
  cwd
  permissionMode
  sdkPermissionMode
  sdkSessionID?
  ownsProductState = false
```

Swift-side sidecar event model:

```swift
ClaudeSDKSidecarEvent
  runStarted(sdkSessionID?)
  textDelta(text)
  textComplete(text, citations, contextSnapshot?)
  toolUseRequested(toolCallID, name, inputJSON)
  permissionRequested(requestID, capability, toolName?, payloadJSON)
  resumeAccepted(requestID, toolName?, message)
  resumeRejected(requestID, toolName?, reason)
  toolUseStarted(toolCallID, name)
  toolUseCompleted(toolCallID, name, contentText, contentJSON?, isError)
  runCompleted
  runFailed(message)
```

These are deliberately smaller than the full Claude Agent SDK message union. `resumeAccepted` and `resumeRejected` are protocol-level events for the future Connor → sidecar command loop. They are intentionally not mapped into new Connor `AgentEventKind` cases yet, so Phase 2 avoids expanding SQLite event schema or timeline presentation before real deferred execution semantics exist. The Swift boundary should grow only when Connor has a normalized product concept for the event.

## Session Transport Skeleton

`ClaudeSDKSidecarSessionTransport` is the future long-lived IPC boundary:

```swift
public protocol ClaudeSDKSidecarSessionTransport: Sendable {
    func start(_ request: ClaudeSDKSidecarRequest) async -> AsyncThrowingStream<ClaudeSDKSidecarEvent, Error>
    func send(_ command: ClaudeSDKSidecarCommand) async throws
    func cancel() async
}
```

Connor can now start a persistent sidecar session, keep stdout event streaming, and send commands such as `.approvalResolved(...)` over the same live process session through `ClaudeSDKSidecarPersistentProcessTransport`. This does not make the legacy `ClaudeSDKSidecarProcessTransport` conform to the protocol because that process transport remains one-shot and intentionally preserves the legacy one-line request shape. It also does not connect real Claude SDK deferred tool resume.

## Persistent Process Transport

`ClaudeSDKSidecarPersistentProcessTransport` is the first long-lived IPC bridge. It:

1. Starts a configured executable once per session.
2. Writes `ClaudeSDKSidecarCommand` envelopes as JSONL to stdin.
3. Streams stdout JSONL `ClaudeSDKSidecarEvent` values as they arrive.
4. Keeps stderr reserved for diagnostics.
5. Supports `cancel()` by closing stdin and terminating the process when needed.

The test fixture proves the same process can receive `.start(...)`, emit `permissionRequested`, then receive `.approvalResolved(...)` and emit `resumeAccepted`. The real Node SDK sidecar now exposes the command-loop envelope shape, but its `approvalResolved` handler is still a skeleton that emits `resumeAccepted` / `resumeRejected` without invoking real Claude SDK deferred resume.

## One-shot Process Transport

`ClaudeSDKSidecarProcessTransport` is the first conservative one-shot IPC bridge. It:

1. Starts a configured executable.
2. Writes exactly one `ClaudeSDKSidecarRequest` JSON line to stdin.
3. Reads stdout as JSONL `ClaudeSDKSidecarEvent` values.
4. Treats stderr as diagnostics.
5. Treats non-zero process exit as transport failure.

This transport is intentionally conservative: it validates the process boundary without yet depending on Node/Bun or the real Claude Agent SDK package.

## Real SDK Entry Point

`sidecars/claude-agent-engine/claude-sidecar.mjs` imports `@anthropic-ai/claude-agent-sdk` and calls `query(request.prompt, options)`.

The current mapping is deliberately conservative:

- `cwd = request.cwd`
- `permissionMode = request.sdkPermissionMode`
- `resume = request.sdkSessionID ?? undefined`
- `includePartialMessages = true`
- `includeHookEvents = true`
- assistant-like SDK messages → `textDelta`
- SDK `tool_use`-like content → `toolUseRequested` + `toolUseStarted`
- SDK `tool_result`-like content → `toolUseCompleted`
- deferred tool-use / permission denial state → `permissionRequested` or failed tool result
- stream completion → `textComplete` + `runCompleted`
- SDK errors/result failures → `runFailed`

A Swift integration test exists but is gated by environment variables, so normal CI/local test runs do not require Node/Bun, npm install, Claude login, or network access.

## Next Slice

Recommended next implementation slice:

1. Add sidecar execution-resume semantics after a Connor approval decision, without letting the SDK own Connor session or permission state.
4. Keep SDK permission mode bypassed until Connor can inspect, audit, approve, and resume sidecar tool actions end-to-end.
5. Add cancellation support before long-running sidecar tasks become default.
6. Only after those controls exist, consider enabling a constrained read-only Claude sidecar path in app settings.
