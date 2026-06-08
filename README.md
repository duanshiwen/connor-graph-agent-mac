# connor-graph-agent-mac

A macOS-native graph knowledge agent client for Agent OS.

This project is a runnable Agent client, not a Markdown knowledge-base manager. Its runtime knowledge source of truth is a local graph store.

## Status

Current MVP status: **Phase 14 promotion queue review UI build**.

Implemented layers:

- macOS SwiftUI app shell.
- Unified graph domain model.
- Rolling one-month Observe Log short-term memory.
- SQLite graph store.
- Legacy Markdown read-only importer.
- Graph search and context assembly.
- Graph-backed Agent runtime.
- Observe Log promotion queue.
- Stub LLM provider for deterministic local testing.
- OpenAI-compatible LLM provider interface for real model calls.
- Application Support SQLite bootstrap for the SwiftUI app.
- Read-only knowledge import UI for legacy Markdown repositories.
- Promotion Queue Review UI for promote / dismiss / pin memory candidates.

## Product principle

Markdown is **not** the final knowledge carrier.

Markdown may be used only as:

- legacy import source,
- human-readable export projection,
- evidence/source snapshot,
- interoperability format.

Runtime knowledge lives in:

```text
GraphNode + SemanticEdge + ObserveLogEntry + SQLiteGraphStore
```

Existing knowledge-base concepts are represented as graph-native typed nodes and semantic edges:

- Question Ledger → `GraphNode(type: .question)`
- Answer Cache → `GraphNode(type: .answer)`
- Work Object → `GraphNode(type: .workObject)`
- Decision → `GraphNode(type: .decision)`
- SOP / Runbook → `GraphNode(type: .procedure)`
- Person Profile → `GraphNode(type: .person)`
- User Preference → `GraphNode(type: .preference)`

## Architecture

```mermaid
graph LR
    UI[SwiftUI macOS App] --> Agent[GraphAgent Runtime]
    Agent --> Search[Graph Search + ContextAssembler]
    Agent --> LLM[LLMProvider]
    LLM --> Stub[StubLLMProvider]
    LLM --> OpenAI[OpenAI-compatible Provider]
    Search --> Store[SQLiteGraphStore]
    Import[Legacy Markdown Importer] --> Store
    Observe[Rolling Observe Log] --> Search
    Observe --> Promotion[Promotion Queue]
    Promotion --> Store
    Store --> Graph[(GraphNode + SemanticEdge)]
```

## Module map

```text
Sources/
  ConnorGraphCore/      Unified graph model: GraphNode, SemanticEdge, typed relations
  ConnorGraphMemory/    Observe Log, rolling policy, promotion queue
  ConnorGraphStore/     SQLite graph and observe-log persistence
  ConnorGraphImport/    Legacy Markdown → graph import
  ConnorGraphSearch/    In-memory search index and AgentContext assembly
  ConnorGraphAgent/       Agent runtime, chat controller, LLM providers
  ConnorGraphAppSupport/  App storage paths, SQLite bootstrap, repository state loading
  ConnorGraphAgentMac/    SwiftUI macOS app shell
```

## Run locally

From this directory:

```bash
swift run connor-graph-agent-mac
```

The app launches against a local SQLite graph store in macOS Application Support. If the database is empty, it seeds a small demo graph so the UI works without any API key or external dependency.

Current SwiftUI pages:

- **Graph Nodes** — inspect graph nodes and edges loaded from SQLite.
- **Search** — run graph / edge / observe-log search against the loaded SQLite snapshot.
- **Observe Log** — inspect short-term memory entries.
- **Agent Chat** — ask the graph-backed agent using `StubLLMProvider`.
- **Promotion Queue** — review active memory candidates and promote / dismiss / pin them.
- **Import** — read-only import of a legacy Markdown knowledge repository into SQLite.

## Test and build

```bash
swift test
swift build
```

Current acceptance baseline:

```text
61 tests passing
Build complete
```

## Real LLM provider

The runtime supports an OpenAI-compatible provider. Secrets are read only from environment variables and must not be committed.

Environment variables:

```bash
export CONNOR_LLM_API_KEY="..."
export CONNOR_LLM_BASE_URL="https://api.openai.com/v1" # optional
export CONNOR_LLM_MODEL="gpt-4o-mini"                 # optional
```

Provider type:

```swift
OpenAICompatibleProvider(
    config: try OpenAICompatibleConfig.fromEnvironment(ProcessInfo.processInfo.environment)
)
```

Notes:

- If `CONNOR_LLM_API_KEY` is missing, optional smoke tests skip automatically.
- `StubLLMProvider` remains the default for tests and local demo UI.
- The provider sends graph context through `AgentContext.renderedText`.
- `LLMResponse.citations` preserves graph source IDs from the context assembler.

## App database

The SwiftUI app stores its runtime graph database at:

```text
~/Library/Application Support/ConnorGraphAgent/connor-graph.sqlite
```

On launch the app:

1. Resolves the Application Support directory.
2. Creates `ConnorGraphAgent/` when needed.
3. Opens `connor-graph.sqlite`.
4. Runs SQLite migrations.
5. Loads a `GraphStoreSnapshot` into the in-memory search index.
6. Seeds demo data only when the database is empty.

The runtime source of truth remains SQLite; Markdown is used only as a read-only import source.

## Read-only legacy knowledge import

The importer can scan an existing Markdown-based repository without modifying source files.

SwiftUI entry point:

1. Open the **Import** page.
2. Enter a Markdown repository path, such as:

```text
/Users/duanshiwen/notes/intelligence-repository
```

3. Click **Import Read-only**.
4. Review scanned files, imported nodes, imported edges, skipped files and warnings.
5. Use **Graph Nodes** or **Search** to inspect imported graph data.

Programmatic entry point:

```swift
let store = try SQLiteGraphStore(path: "graph.sqlite")
try store.migrate()
let report = try LegacyKnowledgeDirectoryImporter(store: store)
    .importDirectory(URL(fileURLWithPath: "/path/to/intelligence-repository"))
```

Report fields:

```swift
LegacyDirectoryImportReport(
    scannedFiles: Int,
    importedNodes: Int,
    importedEdges: Int,
    skippedFiles: Int,
    warnings: [LegacyImportWarning]
)
```

Real repository smoke test is opt-in:

```bash
CONNOR_REAL_REPO_IMPORT_PATH=/Users/duanshiwen/notes/intelligence-repository \
  swift test --filter realIntelligenceRepositoryReadOnlyImportSmoke
```

## Observe Log and Promotion Queue

Short-term memory is represented by `ObserveLogEntry` and defaults to a 30-day rolling retention policy.

Supported observe-log kinds include:

- `operation`
- `toolEvent`
- `insight`
- `fragment`
- `observation`
- `candidateFact`
- `decisionHint`
- `userPreference`

Promotion queue behavior:

```text
candidateFact  → SemanticEdge draft
decisionHint   → Decision GraphNode draft + BELONGS_TO edge when workObjectID exists
userPreference → Preference GraphNode draft + HAS_PREFERENCE edge
```

Queue operations:

- `promote`
- `dismiss`
- `pin` for another 30 days

The SwiftUI **Promotion Queue** page loads active promotion candidates from SQLite and supports:

- **Promote** — writes the draft node / edge produced by `MemoryPromotionService` into `SQLiteGraphStore`, updates the source observe log to `promoted`, then refreshes graph state.
- **Dismiss** — marks the observe-log entry as `dismissed` and removes it from the active queue.
- **Pin 30 days** — keeps the entry active and extends its expiry by another 30 days.

Candidate kinds are:

- `candidate_fact`
- `decision_hint`
- `user_preference`

## Current limitations

This is intentionally an MVP, not the final Agent OS client.

Known limitations:

- SwiftUI app seeds demo graph data only when the Application Support SQLite database is empty.
- App UI does not yet persist chat sessions to SQLite.
- App UI does not yet expose real LLM configuration.
- Legacy importer uses frontmatter and path heuristics; it does not yet run LLM-based entity extraction.
- Search is currently in-memory lexical matching, not embedding / hybrid search.
- Promotion Queue Review UI is available, but does not yet include advanced filtering, conflict resolution or diff previews.
- No Graphiti sidecar adapter yet.
- No Keychain-backed credential manager yet.

## Roadmap after MVP

Recommended next phases:

1. Add Keychain-backed LLM credential storage.
2. Add real chat session persistence.
3. Add hybrid retrieval: lexical + embedding + graph neighborhood.
4. Add Graphiti adapter for temporal fact extraction, deduplication and invalidation.
5. Add human-readable export projections for graph slices.

## Development discipline

Every implementation phase should be validated with:

```bash
swift test
swift build
```
