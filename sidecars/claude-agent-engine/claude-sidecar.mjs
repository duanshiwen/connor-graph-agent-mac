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
  if (block.type === 'tool_use') return '';
  return '';
};

const textFromAssistantMessage = (message) => {
  const content = message?.message?.content ?? message?.content ?? [];
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content.map(textFromContentBlock).join('');
};

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

const isResultLike = (message) => message?.type === 'result' || message?.type === 'sdk_result';
const isErrorLike = (message) => message?.type === 'error' || message?.type === 'assistant_message_error';

const run = async () => {
  const request = parseRequest(await readFirstJSONLine());
  let finalText = '';
  let emittedRunStarted = false;

  const options = {
    cwd: request.cwd,
    permissionMode: request.sdkPermissionMode,
    resume: request.sdkSessionID ?? undefined,
    includePartialMessages: true
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

    if (isAssistantLike(message)) {
      const text = textFromAssistantMessage(message);
      if (text.length > 0) {
        finalText += text;
        writeEvent({ textDelta: { text } });
      }
      continue;
    }

    if (isResultLike(message)) {
      const subtype = message?.subtype ?? message?.terminal_reason ?? 'completed';
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
