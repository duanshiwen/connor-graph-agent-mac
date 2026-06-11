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

const stableJSONString = (value) => {
  if (value === undefined) return '{}';
  if (typeof value === 'string') return value;
  try {
    return JSON.stringify(value ?? {});
  } catch {
    return '{}';
  }
};

const parseRequest = (line) => {
  if (!line) throw new Error('Missing Connor sidecar request JSONL line');
  const request = JSON.parse(line);
  if (request.ownsProductState !== false) {
    throw new Error('Refusing request: sidecar must not own Connor product state');
  }
  if (request.sdkPermissionMode !== 'bypassPermissions') {
    throw new Error('Refusing request: Connor expects SDK permissions to be bypassed and governed externally');
  }
  if (!request.connorRunID || !request.connorSessionID) {
    throw new Error('Invalid request: Connor run/session IDs are required');
  }
  return request;
};

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

const emitPermissionRequestedFromDeferredResult = (message) => {
  const deferred = message?.deferred_tool_use ?? message?.deferredToolUse;
  if (!deferred) return false;
  const toolCallID = deferred.id ?? deferred.tool_use_id ?? 'deferred-tool-call';
  const name = deferred.name ?? deferred.tool_name ?? 'unknown';
  const payloadJSON = stableJSONString(deferred.input ?? {});
  writeEvent({
    permissionRequested: {
      requestID: `permission-${toolCallID}`,
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

const run = async () => {
  const request = parseRequest(await readFirstJSONLine());
  let finalText = '';
  let emittedRunStarted = false;

  const options = {
    cwd: request.cwd,
    permissionMode: request.sdkPermissionMode,
    resume: request.sdkSessionID ?? undefined,
    includePartialMessages: true,
    includeHookEvents: true
  };

  for await (const message of query(request.prompt, options)) {
    if (!emittedRunStarted) {
      writeEvent({ runStarted: { sdkSessionID: sessionIDFromMessage(message) } });
      emittedRunStarted = true;
    }

    if (isErrorLike(message)) {
      writeEvent({ runFailed: { message: message?.error?.message ?? message?.message ?? 'Claude SDK sidecar error' } });
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
      if (emitPermissionRequestedFromDeferredResult(message)) {
        writeEvent({ runFailed: { message: 'Claude SDK deferred tool use pending Connor permission approval' } });
        return;
      }
      if (subtype !== 'success' && subtype !== 'completed') {
        writeEvent({ runFailed: { message: `Claude SDK result: ${subtype}` } });
        return;
      }
    }
  }

  if (!emittedRunStarted) {
    writeEvent({ runStarted: { sdkSessionID: request.sdkSessionID ?? null } });
  }

  writeEvent({
    textComplete: {
      text: finalText,
      citations: [],
      contextSnapshot: null
    }
  });
  writeEvent({ runCompleted: {} });
};

try {
  await run();
} catch (error) {
  writeDiagnostic(error?.stack ?? error?.message ?? String(error));
  try {
    writeEvent({ runFailed: { message: error?.message ?? String(error) } });
  } catch {
    // If stdout is unavailable, stderr diagnostics above are the fallback.
  }
  exit(1);
}
