# connor-graph-agent-mac

A macOS-native graph knowledge agent client for Agent OS.

## Product principle

This project is a runnable Agent client, not a Markdown knowledge-base manager.

- The runtime source of truth is a local graph store.
- Markdown is not the final knowledge carrier.
- Markdown may be used only as:
  - legacy import source,
  - human-readable export projection,
  - evidence/source snapshot,
  - interoperability format.

## MVP layers

1. SwiftUI macOS client.
2. Unified graph domain model.
3. Rolling one-month Observe Log short-term memory.
4. Local graph store.
5. Graph-backed search and Agent ask flow.

## Development

```bash
swift test
swift build
```
