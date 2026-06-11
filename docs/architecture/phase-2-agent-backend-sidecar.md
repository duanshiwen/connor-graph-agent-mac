# Phase 2: AgentBackend Abstraction and Claude SDK Sidecar

Last updated: 2026-06-11 11:24 GMT+8

## Status

Phase 2 introduces the Swift-side backend boundary for replacing agent engines without moving product state out of Connor.

This phase does **not** embed the Claude Agent SDK directly into the macOS app. The SDK remains an external sidecar engine. Connor owns sessions, graph memory, permissions, audit, and UI state.

Current implementation status:

- `AgentBackend` is the product-level backend interface.
- `NativeSessionManager` depends on `AnyAgentBackend`, not a concrete SDK or model provider.
- `AgentLoopBackend` adapts the existing native loop.
- `ClaudeSDKSidecarBackend` maps sidecar events into Connor `AgentEvent`.
- `ClaudeSDKSidecarProcessTransport` runs an external process and bridges one request plus JSONL sidecar events over stdin/stdout.
- `sidecars/claude-agent-engine/` contains protocol docs plus mock Node/shell sidecars.

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

The sidecar must report tool or permission events back as normalized Connor `AgentEvent` values. Future work should add explicit sidecar permission request events before any write-capable sidecar tools are enabled.

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

## Next Slice

Recommended next implementation slice:

1. Replace `sidecars/claude-agent-engine/mock-sidecar.mjs` internals with a real Node/Bun sidecar that imports `@anthropic-ai/claude-agent-sdk`.
2. Call `query(request.prompt, options)` with:
   - `cwd = request.cwd`
   - `permissionMode = "bypassPermissions"`
   - `resume = request.sdkSessionID` only as optional SDK metadata, never as Connor session identity.
3. Map SDK messages into the existing JSONL protocol:
   - system/session initialization → `runStarted`
   - partial assistant streaming → `textDelta`
   - final assistant/result → `textComplete` + `runCompleted`
   - SDK errors/result failures → `runFailed`
4. Add a gated integration test that only runs when a JS runtime and Claude SDK executable are explicitly configured.
5. Add explicit tool/permission event normalization before enabling write-capable sidecar tools.
