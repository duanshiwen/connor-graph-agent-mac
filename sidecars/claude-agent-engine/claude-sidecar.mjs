#!/usr/bin/env node
import { createInterface } from 'node:readline';
import { stdin, stdout, stderr, exit } from 'node:process';
import { query } from '@anthropic-ai/claude-agent-sdk';

const readFirstJSONLine = async () => {
  const rl = createInterface({ input: stdin, crlfDelay: Infinity });
  for await (const line of rl) {
    if (line.trim().length === 0) continue;
    return line;
  }
  return '';
};

const writeEvent = (event) => stdout.write(`${JSON.stringify(event)}\n`);
const writeDiagnostic = (message) => stderr.write(`${message}\n`);
const SIDECAR_PROTOCOL_VERSION = 2;
const SIDECAR_CAPABILITIES = ['resume', 'fork', 'defer-permissions', 'health', 'heartbeat', 'diagnostics', 'structured-failure', 'cancel'];
const pendingDeferredToolUses = new Map();
let activeQuery = null;
let activeAbortController = null;
let activeRunID = null;
let activeSessionID = null;
let cancellationRequested = false;

const clearActiveRun = (runID = null) => {
  if (runID && activeRunID !== runID) return;
  activeQuery = null;
  activeAbortController = null;
  activeRunID = null;
  activeSessionID = null;
  cancellationRequested = false;
};

const cancelActiveRun = (payload = {}) => {
  cancellationRequested = true;
  const reason = payload.reason ?? 'Connor cancelled Claude SDK sidecar command loop';
  try {
    if (typeof activeQuery?.stopTask === 'function') activeQuery.stopTask();
  } catch (error) {
    writeDiagnostic(`stopTask failed during cancel: ${error?.message ?? String(error)}`);
  }
  try {
    if (typeof activeQuery?.interrupt === 'function') activeQuery.interrupt();
  } catch (error) {
    writeDiagnostic(`interrupt failed during cancel: ${error?.message ?? String(error)}`);
  }
  try {
    activeAbortController?.abort(reason);
  } catch (error) {
    writeDiagnostic(`abortController failed during cancel: ${error?.message ?? String(error)}`);
  }
  try {
    if (typeof activeQuery?.close === 'function') activeQuery.close();
  } catch (error) {
    writeDiagnostic(`query close failed during cancel: ${error?.message ?? String(error)}`);
  }
};

const stableJSONString = (value) => {
  if (value === undefined) return '{}';
  if (typeof value === 'string') return value;
  try {
    return JSON.stringify(value ?? {});
  } catch {
    return '{}';
  }
};

const validateRequest = (request) => {
  if (request.ownsProductState !== false) {
    throw new Error('Refusing request: sidecar must not own Connor product state');
  }
  if ((request.protocolVersion ?? SIDECAR_PROTOCOL_VERSION) !== SIDECAR_PROTOCOL_VERSION) {
    throw new Error(`Refusing request: unsupported Connor sidecar protocol version ${request.protocolVersion}`);
  }
  if (request.sdkPermissionMode !== 'bypassPermissions') {
    throw new Error('Refusing request: Connor expects SDK permissions to be bypassed and governed externally');
  }
  if (request.sdkSessionID && request.forkFromSDKSessionID) {
    throw new Error('Refusing request: resume sdkSessionID and forkFromSDKSessionID are mutually exclusive');
  }
  if (!request.connorRunID || !request.connorSessionID) {
    throw new Error('Invalid request: Connor run/session IDs are required');
  }
  return request;
};

const parseCommand = (line) => {
  if (!line) throw new Error('Missing Connor sidecar command JSONL line');
  const parsed = JSON.parse(line);
  if (parsed.start) return { name: 'start', payload: validateRequest(parsed.start) };
  if (parsed.approvalResolved) return { name: 'approvalResolved', payload: parsed.approvalResolved };
  if (parsed.cancel) return { name: 'cancel', payload: parsed.cancel };
  if (parsed.health) return { name: 'health', payload: parsed.health };

  // Backward compatibility: legacy one-shot transports still send the raw request shape.
  if (parsed.connorRunID && parsed.connorSessionID) {
    return { name: 'start', payload: validateRequest(parsed) };
  }

  throw new Error('Unknown Connor sidecar command envelope');
};

const parseRequest = (line) => parseCommand(line).payload;

const textFromContentBlock = (block) => {
  if (!block) return '';
  if (typeof block === 'string') return block;
  if (block.type === 'text' && typeof block.text === 'string') return block.text;
  if (block.type === 'thinking' && typeof block.thinking === 'string') return '';
  if (block.type === 'tool_use' || block.type === 'tool_result') return '';
  return '';
};

const contentBlocks = (message) => {
  const content = message?.message?.content ?? message?.content ?? [];
  if (typeof content === 'string') return [{ type: 'text', text: content }];
  return Array.isArray(content) ? content : [];
};

const textFromAssistantMessage = (message) => contentBlocks(message).map(textFromContentBlock).join('');

const sessionIDFromMessage = (message) =>
  message?.session_id ??
  message?.sessionId ??
  message?.session?.id ??
  message?.metadata?.session_id ??
  null;

const emitHeartbeat = (request, sdkSessionID = null) => {
  writeEvent({
    heartbeat: {
      protocolVersion: SIDECAR_PROTOCOL_VERSION,
      sdkSessionID: sdkSessionID ?? request.sdkSessionID ?? null,
      sdkCWD: request.cwd,
      timestamp: new Date().toISOString(),
      pendingDeferredToolUseCount: pendingDeferredToolUses.size,
      ownsProductState: false
    }
  });
};

const emitDiagnostic = ({ status, message, request = null, sdkSessionID = null, failureCode = null, recoverability = null }) => {
  writeEvent({
    runtimeDiagnostic: {
      protocolVersion: SIDECAR_PROTOCOL_VERSION,
      status,
      message,
      sdkSessionID: sdkSessionID ?? request?.sdkSessionID ?? null,
      sdkCWD: request?.cwd ?? null,
      failureCode,
      recoverability,
      ownsProductState: false
    }
  });
};

const emitRunFailed = (message, code = 'unknown', recoverability = 'unknown') => {
  writeEvent({ runFailed: { message, code, recoverability } });
};

const isAssistantLike = (message) =>
  message?.type === 'assistant' ||
  message?.type === 'assistant_message' ||
  message?.type === 'partial_assistant' ||
  message?.type === 'partial_assistant_message';

const isUserLike = (message) => message?.type === 'user' || message?.type === 'user_message';
const isResultLike = (message) => message?.type === 'result' || message?.type === 'sdk_result';
const isErrorLike = (message) => message?.type === 'error' || message?.type === 'assistant_message_error';
const isPermissionDeniedLike = (message) => message?.type === 'permission_denied' || message?.type === 'permission_denial';

const capabilityForTool = (toolName) => {
  const normalized = String(toolName ?? '').toLowerCase();
  if (normalized.includes('read') || normalized.includes('grep') || normalized.includes('glob') || normalized.includes('ls')) return 'readSession';
  if (normalized.includes('web') || normalized.includes('fetch') || normalized.includes('search')) return 'externalNetwork';
  if (normalized.includes('write') || normalized.includes('edit')) return 'proposeGraphWrite';
  if (normalized.includes('bash') || normalized.includes('shell')) return 'externalNetwork';
  return 'modelCall';
};

const emitToolUseFromBlock = (block) => {
  if (block?.type !== 'tool_use') return;
  const toolCallID = block.id ?? block.tool_use_id ?? block.toolCallID ?? `${block.name ?? 'tool'}-${Date.now()}`;
  const name = block.name ?? block.tool_name ?? 'unknown';
  const inputJSON = stableJSONString(block.input ?? block.arguments ?? {});
  writeEvent({ toolUseRequested: { toolCallID, name, inputJSON } });
  writeEvent({ toolUseStarted: { toolCallID, name } });
};

const emitToolResultFromBlock = (block) => {
  if (block?.type !== 'tool_result') return;
  const toolCallID = block.tool_use_id ?? block.id ?? block.toolCallID ?? 'unknown-tool-call';
  const name = block.name ?? block.tool_name ?? 'unknown';
  const isError = Boolean(block.is_error ?? block.isError ?? false);
  const contentText = typeof block.content === 'string'
    ? block.content
    : stableJSONString(block.content ?? block.result ?? '');
  writeEvent({
    toolUseCompleted: {
      toolCallID,
      name,
      contentText,
      contentJSON: typeof block.content === 'string' ? null : stableJSONString(block.content ?? block.result ?? null),
      isError
    }
  });
};

const requestIDForDeferredTool = (deferred) => `permission-${deferred?.id ?? deferred?.tool_use_id ?? 'deferred-tool-call'}`;

const emitPermissionRequestedFromDeferredResult = (message, request) => {
  const deferred = message?.deferred_tool_use ?? message?.deferredToolUse;
  if (!deferred) return false;
  const toolCallID = deferred.id ?? deferred.tool_use_id ?? 'deferred-tool-call';
  const name = deferred.name ?? deferred.tool_name ?? 'unknown';
  const payloadJSON = stableJSONString(deferred.input ?? {});
  const requestID = requestIDForDeferredTool(deferred);
  pendingDeferredToolUses.set(requestID, {
    requestID,
    toolCallID,
    toolName: name,
    input: deferred.input ?? {},
    sdkSessionID: message?.session_id ?? message?.sessionId ?? request.sdkSessionID ?? null,
    request
  });
  writeEvent({
    permissionRequested: {
      requestID,
      capability: capabilityForTool(name),
      toolName: name,
      payloadJSON
    }
  });
  return true;
};

const emitPermissionDenied = (message) => {
  const toolCallID = message?.tool_use_id ?? message?.toolUseID ?? 'denied-tool-call';
  const name = message?.tool_name ?? message?.toolName ?? 'unknown';
  const reason = message?.decision_reason ?? message?.message ?? 'Claude SDK permission denied';
  writeEvent({
    toolUseCompleted: {
      toolCallID,
      name,
      contentText: reason,
      contentJSON: stableJSONString(message),
      isError: true
    }
  });
};

const processAssistantSideEffects = (message) => {
  for (const block of contentBlocks(message)) emitToolUseFromBlock(block);
};

const processUserSideEffects = (message) => {
  for (const block of contentBlocks(message)) emitToolResultFromBlock(block);
};

const buildConnorDeferHooks = () => ({
  PreToolUse: [
    async () => ({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        permissionDecision: 'defer'
      }
    })
  ]
});

const buildDeferredResumeHooks = (deferred, resolution) => ({
  PreToolUse: [
    async () => ({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        permissionDecision: 'allow',
        permissionDecisionReason: resolution.reason ?? 'Connor approved deferred tool execution',
        updatedInput: JSON.parse(resolution.payloadJSON || stableJSONString(deferred.input ?? {}))
      }
    })
  ]
});

const runRequest = async (request) => {
  let finalText = '';
  let emittedRunStarted = false;

  const requestOptions = request.options ?? {};
  const abortController = new AbortController();
  activeAbortController = abortController;
  activeRunID = request.connorRunID;
  activeSessionID = request.connorSessionID;
  cancellationRequested = false;
  const options = {
    cwd: request.cwd,
    permissionMode: request.sdkPermissionMode,
    resume: request.sdkSessionID ?? undefined,
    forkSession: request.forkFromSDKSessionID ?? undefined,
    maxTurns: requestOptions.maxTurns ?? undefined,
    model: requestOptions.model ?? undefined,
    effort: requestOptions.effort ?? undefined,
    includePartialMessages: requestOptions.includePartialMessages ?? true,
    includeHookEvents: requestOptions.includeHookEvents ?? true,
    persistSession: requestOptions.persistSession ?? true,
    abortController,
    hooks: buildConnorDeferHooks()
  };

  emitDiagnostic({ status: 'starting', message: `Starting Claude SDK sidecar ${request.forkFromSDKSessionID ? 'fork' : request.sdkSessionID ? 'resume' : 'fresh'} request`, request });
  emitHeartbeat(request);

  const sdkQuery = query(request.prompt, options);
  activeQuery = sdkQuery;

  try {
    for await (const message of sdkQuery) {
      if (!emittedRunStarted) {
        const sdkSessionID = sessionIDFromMessage(message);
        writeEvent({ runStarted: { sdkSessionID } });
        emitHeartbeat(request, sdkSessionID);
        emittedRunStarted = true;
      }

      if (isErrorLike(message)) {
        emitRunFailed(message?.error?.message ?? message?.message ?? 'Claude SDK sidecar error', 'sdk_error', 'retryable');
        return;
      }

      if (isPermissionDeniedLike(message)) {
        emitPermissionDenied(message);
        continue;
      }

      if (isAssistantLike(message)) {
        processAssistantSideEffects(message);
        const text = textFromAssistantMessage(message);
        if (text.length > 0) {
          finalText += text;
          writeEvent({ textDelta: { text } });
        }
        continue;
      }

      if (isUserLike(message)) {
        processUserSideEffects(message);
        continue;
      }

      if (isResultLike(message)) {
        const subtype = message?.subtype ?? message?.terminal_reason ?? 'completed';
        const terminalReason = message?.terminal_reason ?? message?.stop_reason ?? subtype;
        if (terminalReason === 'tool_deferred' && emitPermissionRequestedFromDeferredResult(message, request)) {
          emitRunFailed('Claude SDK deferred tool use pending Connor permission approval', 'permission_deferred', 'requires_user_action');
          return;
        }
        if (emitPermissionRequestedFromDeferredResult(message, request)) {
          emitRunFailed('Claude SDK deferred tool use pending Connor permission approval', 'permission_deferred', 'requires_user_action');
          return;
        }
        if (subtype !== 'success' && subtype !== 'completed') {
          emitRunFailed(`Claude SDK result: ${subtype}`, 'sdk_error', subtype === 'error_max_turns' ? 'resumable' : 'retryable');
          return;
        }
      }
    }
  } catch (error) {
    if (cancellationRequested || abortController.signal.aborted) {
      emitRunFailed('Connor cancelled Claude SDK sidecar request', 'cancelled', 'terminal');
      return;
    }
    throw error;
  } finally {
    clearActiveRun(request.connorRunID);
  }

  if (cancellationRequested || abortController.signal.aborted) {
    emitRunFailed('Connor cancelled Claude SDK sidecar request', 'cancelled', 'terminal');
    return;
  }

  if (!emittedRunStarted) {
    writeEvent({ runStarted: { sdkSessionID: request.sdkSessionID ?? null } });
  }

  emitDiagnostic({ status: 'ready', message: 'Claude SDK sidecar request completed', request });
  writeEvent({
    textComplete: {
      text: finalText,
      citations: [],
      contextSnapshot: null
    }
  });
  writeEvent({ runCompleted: {} });
};

const runDeferredResume = async (deferred, resolution) => {
  const request = deferred.request;
  const options = {
    cwd: request.cwd,
    permissionMode: request.sdkPermissionMode,
    resume: deferred.sdkSessionID,
    includePartialMessages: true,
    includeHookEvents: true,
    hooks: buildDeferredResumeHooks(deferred, resolution)
  };

  let finalText = '';
  for await (const message of query(request.prompt, options)) {
    if (isErrorLike(message)) {
      emitRunFailed(message?.error?.message ?? message?.message ?? 'Claude SDK deferred resume error', 'sdk_error', 'retryable');
      return;
    }
    if (isAssistantLike(message)) {
      processAssistantSideEffects(message);
      const text = textFromAssistantMessage(message);
      if (text.length > 0) {
        finalText += text;
        writeEvent({ textDelta: { text } });
      }
      continue;
    }
    if (isUserLike(message)) {
      processUserSideEffects(message);
      continue;
    }
    if (isResultLike(message)) {
      const subtype = message?.subtype ?? message?.terminal_reason ?? 'completed';
      if (subtype !== 'success' && subtype !== 'completed') {
        emitRunFailed(`Claude SDK deferred resume result: ${subtype}`, 'sdk_error', 'retryable');
        return;
      }
    }
  }

  writeEvent({ textComplete: { text: finalText, citations: [], contextSnapshot: null } });
  writeEvent({ runCompleted: {} });
};

const emitSidecarHealth = () => {
  writeEvent({
    sidecarHealth: {
      status: 'ok',
      pendingDeferredToolUseCount: pendingDeferredToolUses.size,
      timestamp: new Date().toISOString(),
      ownsProductState: false,
      protocolVersion: SIDECAR_PROTOCOL_VERSION,
      capabilities: SIDECAR_CAPABILITIES
    }
  });
};

const handleApprovalResolved = async (resolution) => {
  if (!resolution?.requestID) {
    writeEvent({ resumeRejected: { requestID: '', toolName: resolution?.toolName ?? null, reason: 'Missing approval request ID' } });
    return;
  }
  if (resolution.ownsProductState !== false) {
    writeEvent({ resumeRejected: { requestID: resolution.requestID, toolName: resolution.toolName ?? null, reason: 'Sidecar must not own Connor product state' } });
    return;
  }
  const deferred = pendingDeferredToolUses.get(resolution.requestID);
  if (!deferred) {
    writeEvent({ resumeRejected: { requestID: resolution.requestID, toolName: resolution.toolName ?? null, reason: 'No deferred Claude SDK tool use is pending for this Connor request' } });
    return;
  }
  if (resolution.outcome === 'approved') {
    writeEvent({
      resumeAccepted: {
        requestID: resolution.requestID,
        toolName: resolution.toolName ?? deferred.toolName ?? null,
        message: 'Approval resolution accepted; resuming deferred Claude SDK tool use under Connor governance'
      }
    });
    pendingDeferredToolUses.delete(resolution.requestID);
    await runDeferredResume(deferred, resolution);
    return;
  }
  pendingDeferredToolUses.delete(resolution.requestID);
  writeEvent({
    resumeRejected: {
      requestID: resolution.requestID,
      toolName: resolution.toolName ?? deferred.toolName ?? null,
      reason: resolution.reason ?? 'Approval resolution denied by Connor'
    }
  });
};

const runCommandLoop = async () => {
  const rl = createInterface({ input: stdin, crlfDelay: Infinity });
  let activeCommandTask = null;
  for await (const line of rl) {
    if (line.trim().length === 0) continue;
    const command = parseCommand(line);
    switch (command.name) {
      case 'start':
        if (activeCommandTask) {
          emitRunFailed('Claude SDK sidecar already has an active request', 'invalid_request', 'requires_user_action');
          break;
        }
        activeCommandTask = runRequest(command.payload).finally(() => {
          activeCommandTask = null;
        });
        break;
      case 'approvalResolved':
        if (activeCommandTask) await activeCommandTask;
        activeCommandTask = handleApprovalResolved(command.payload).finally(() => {
          activeCommandTask = null;
        });
        break;
      case 'health':
        emitSidecarHealth();
        break;
      case 'cancel':
        cancelActiveRun(command.payload);
        if (!activeCommandTask) emitRunFailed('Connor cancelled Claude SDK sidecar command loop', 'cancelled', 'terminal');
        await activeCommandTask;
        return;
      default:
        throw new Error(`Unsupported Connor sidecar command: ${command.name}`);
    }
  }
  if (activeCommandTask) await activeCommandTask;
};

try {
  await runCommandLoop();
} catch (error) {
  writeDiagnostic(error?.stack ?? error?.message ?? String(error));
  try {
    emitRunFailed(error?.message ?? String(error), 'invalid_request', 'requires_user_action');
  } catch {
    // If stdout is unavailable, stderr diagnostics above are the fallback.
  }
  exit(1);
}
