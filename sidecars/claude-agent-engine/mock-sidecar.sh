#!/bin/sh

IFS= read -r request

if [ -z "$request" ]; then
  printf '%s\n' 'Missing Connor sidecar request JSONL line' >&2
  exit 2
fi

case "$request" in
  *'"ownsProductState":false'*|*'"ownsProductState": false'*) ;;
  *)
    printf '%s\n' 'Refusing request: sidecar must not own Connor product state' >&2
    exit 3
    ;;
esac

case "$request" in
  *'"sdkPermissionMode":"bypassPermissions"'*|*'"sdkPermissionMode": "bypassPermissions"'*) ;;
  *)
    printf '%s\n' 'Refusing request: Connor expects SDK permissions to be bypassed and governed externally' >&2
    exit 3
    ;;
esac

printf '%s\n' '{"runStarted":{"sdkSessionID":"mock-shell-claude-sdk-session"}}'
printf '%s\n' '{"textDelta":{"text":"Mock Claude shell sidecar received a Connor request"}}'
printf '%s\n' '{"textComplete":{"text":"Mock Claude shell sidecar received a Connor request","citations":[],"contextSnapshot":null}}'
printf '%s\n' '{"runCompleted":{}}'
