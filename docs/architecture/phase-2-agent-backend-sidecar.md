# Phase 2: AgentBackend Abstraction and Claude SDK Sidecar

Last updated: 2026-06-11 14:18 GMT+8

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
- `sidecars/claude-agent-engine/` contains protocol docs, mock Node/shell sidecars, and the real `claude-sidecar.mjs` SDK entry point.

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

The sidecar reports tool and permission boundary events back as normalized Connor `AgentEvent` values. Factory-created Claude sidecar `NativeSessionManager` instances persist those events into the SQLite `agent_events` timeline through `AgentEventRecorder`, create Connor-owned `agent_pending_approvals` records for normalized `permissionRequested` events, and render tool/permission events with tool names, call IDs, request IDs, and compact payload summaries for the native timeline UI. Pending approvals can now be resolved through Connor product APIs: approval resolution updates the pending record, writes an `AgentAuditEvent.permissionDecision`, and appends a `permissionResolved` timeline event. Write-capable sidecar tools still must not become default until Connor has native approval UI and execution-resume semantics over these normalized events.

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
  toolUseStarted(toolCallID, name)
  toolUseCompleted(toolCallID, name, contentText, contentJSON?, isError)
  runCompleted
  runFailed(message)
```

These are deliberately smaller than the full Claude Agent SDK message union. The Swift boundary should grow only when Connor has a normalized product concept for the event.

## Process Transport

`ClaudeSDKSidecarProcessTransport` is the first real IPC bridge. It:

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

1. Add product-level approval flow for normalized sidecar `permissionRequested` events.
2. Add product-level UI for listing and resolving pending sidecar approvals.
3. Add sidecar execution-resume semantics after a Connor approval decision, without letting the SDK own Connor session or permission state.
4. Keep SDK permission mode bypassed until Connor can inspect, audit, approve, and resume sidecar tool actions end-to-end.
5. Add cancellation support to `ClaudeSDKSidecarProcessTransport` before long-running sidecar tasks become default.
6. Only after those controls exist, consider enabling a constrained read-only Claude sidecar path in app settings.
