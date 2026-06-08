# connor-graph-agent-mac

A macOS-native graph knowledge agent client for Agent OS.

This project is a runnable Agent client, not a Markdown knowledge-base manager. Its runtime knowledge source of truth is a local graph store.

## Status

Current MVP status: **Phase 17 LLM provider health check build**.

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
- LLM Settings UI with macOS Keychain-backed API key storage.
- SQLite-backed Agent Chat session and message persistence.
- LLM provider health check / test connection for Stub and OpenAI-compatible modes.

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
- **Agent Chat** — ask the graph-backed agent using the selected LLM provider, with sessions and messages persisted to SQLite.
- **Promotion Queue** — review active memory candidates and promote / dismiss / pin them.
- **Import** — read-only import of a legacy Markdown knowledge repository into SQLite.
- **LLM Settings** — configure Stub vs OpenAI-compatible mode, base URL, model, Keychain API key and provider test connection.

## Test and build

```bash
swift test
swift build
```

Current acceptance baseline:

```text
81 tests passing
Build complete
```

## Real LLM provider

The runtime supports an OpenAI-compatible provider. In the SwiftUI app, API keys are stored in macOS Keychain through the **LLM Settings** page. Environment variables remain available for programmatic tests and smoke runs.

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
- Provider health checks use a minimal `chat/completions` request, which validates base URL, API key, model and response parsing without depending on provider-specific model-list endpoints.

## LLM Settings and Keychain

The SwiftUI **LLM Settings** page supports:

- Provider mode: `Stub` or `OpenAI Compatible`
- Base URL, defaulting to `https://api.openai.com/v1`
- Model, defaulting to `gpt-4o-mini`
- API key save / clear
- Test Connection for Stub and OpenAI-compatible providers

Secret storage:

```text
macOS Keychain generic password
service: ConnorGraphAgent
account: openai-compatible-api-key
```

Non-secret settings are stored outside SQLite:

- provider mode
- base URL
- model

The API key is never stored in SQLite, README, fixtures or committed source. If OpenAI-compatible mode is selected without a stored key, chat and Test Connection return a clear missing API key error.

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

## Chat session persistence

Agent Chat sessions are persisted in SQLite alongside graph runtime data.

SQLite tables:

```text
chat_sessions
chat_messages
```

Persisted session data includes:

- session id
- title
- created / updated timestamps
- user and assistant messages
- assistant citations
- optional context snapshot text

The SwiftUI **Agent Chat** page supports:

- creating a new chat session
- selecting a recent chat session
- reloading persisted sessions
- saving each user/assistant turn after submission

## Current limitations

This is intentionally an MVP, not the final Agent OS client.

Known limitations:

- SwiftUI app seeds demo graph data only when the Application Support SQLite database is empty.
- Chat sessions are persisted to SQLite, but the UI does not yet support editing, deleting, branching or summarizing conversations.
- App UI exposes provider connection testing, but does not yet include model listing, latency metrics or multi-profile management.
- Legacy importer uses frontmatter and path heuristics; it does not yet run LLM-based entity extraction.
- Search is currently in-memory lexical matching, not embedding / hybrid search.
- Promotion Queue Review UI is available, but does not yet include advanced filtering, conflict resolution or diff previews.
- No Graphiti sidecar adapter yet.

## Roadmap after MVP

Recommended next phases:

1. Add chat session compaction / summary.
2. Add hybrid retrieval: lexical + embedding + graph neighborhood.
3. Add Graphiti adapter for temporal fact extraction, deduplication and invalidation.
4. Add human-readable export projections for graph slices.
5. Add model listing / multi-profile provider management.

## Development discipline

Every implementation phase should be validated with:

```bash
swift test
swift build
```
