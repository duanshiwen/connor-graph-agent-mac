#!/usr/bin/env node
import { createInterface } from 'node:readline';
import { stdin, stdout, stderr, exit } from 'node:process';

const rl = createInterface({ input: stdin, crlfDelay: Infinity });
let firstLine = '';

for await (const line of rl) {
  if (line.trim().length === 0) continue;
  firstLine = line;
  break;
}

if (!firstLine) {
  stderr.write('Missing Connor sidecar request JSONL line\n');
  exit(2);
}

let request;
try {
  request = JSON.parse(firstLine);
} catch (error) {
  stderr.write(`Invalid Connor sidecar request JSON: ${error?.message ?? String(error)}\n`);
  exit(2);
}

if (request.ownsProductState !== false) {
  stderr.write('Refusing request: sidecar must not own Connor product state\n');
  exit(3);
}

if (request.sdkPermissionMode !== 'bypassPermissions') {
  stderr.write('Refusing request: Connor expects SDK permissions to be bypassed and governed externally\n');
  exit(3);
}

const writeEvent = (event) => stdout.write(`${JSON.stringify(event)}\n`);

writeEvent({ runStarted: { sdkSessionID: 'mock-claude-sdk-session' } });
writeEvent({ textDelta: { text: 'Mock Claude sidecar received: ' } });
writeEvent({ textDelta: { text: request.prompt } });
writeEvent({
  textComplete: {
    text: `Mock Claude sidecar received: ${request.prompt}`,
    citations: [],
    contextSnapshot: null
  }
});
writeEvent({ runCompleted: {} });
