# Commercial Note Import Operations Guide

## Supported sources

The native import wizard is enabled by default. It scans and previews content before creating a persistent background job.

- Recursive Markdown folders
- Obsidian Vaults: aliases, wikilinks, heading/block anchors, note embeds and file embeds
- Notion offline export **folders after extraction**: Markdown, CSV, HTML and local resources
- Evernote/Yinxiang ENEX: streaming notes, ENML, tags, dates and resources

Direct Notion ZIP selection remains intentionally unavailable until the production `SafeArchiveBackend` and its representative-hardware release evidence are complete. The wizard states this boundary instead of accepting a ZIP it cannot safely process.

Each imported note is stored as `AgentSessionKind.note`. Source provenance remains in the import ledger. Original note messages are never silently overwritten.

## Safety and privacy

- Sources use persisted security-scoped bookmarks. Stale authorization requires explicit reauthorization.
- Symbolic links are not followed by default and candidates must stay under the authorized root.
- Archives are validated before extraction for traversal, links, entry count, depth, size and compression ratio.
- ENEX external entities are disabled. HTML/ENML scripts are removed and remote resources are not loaded.
- Attachments are copied into the Session Capsule and validated by hash/byte count.
- Automatic LLM runs use headless Session managers and do not alter the selected foreground Session.
- Reports exclude note bodies.

## Recovery behavior

The ledger is the source of truth for pause, cancel, heartbeat, lease and retry state.

- `creatingSession` with a bound Session resumes as imported; it does not create another Session.
- `creatingSession` without a Session returns to ready.
- `runningLLM` returns to the persistent LLM queue.
- Active leases prevent duplicate workers; expired leases may be reclaimed.
- Pause stops new dispatch while active work safely completes.
- Cancel stops new dispatch and requests cancellation of active headless runs. Existing Sessions are retained.

## Import Center actions

The current native Import Center loads persisted jobs and item status from the ledger and offers:

- Pause / resume dispatch
- Cancel remaining work while retaining Sessions already created
- Refresh persisted job and item status
- Inspect discovered/imported/duplicate/failed counts and per-item errors

The domain and reporting services also model retry, reauthorization, encoding review, opening imported Sessions, and diagnostic export. These actions must not be advertised as complete until their UI commands are connected and verified.

## Source-specific limits

- Obsidian plugin-specific syntax and Canvas are preserved as source text/diagnostics; they are not silently discarded.
- Notion ZIP extraction requires a production archive backend implementing `SafeArchiveBackend`; parsing operates only on its validated output directory.
- Notion CSV defaults to child pages only. Row-as-note must be explicitly selected.
- ENEX cannot restore notebook stack or tag hierarchy that is absent from the export.
- ENEX resources are staged in a dedicated temporary area and must be removed after Session Attachment Store ingestion.

## Feature flag and release gate

The feature is enabled by default for the native Markdown-folder, Obsidian-vault, extracted-Notion-folder, and ENEX paths. Operations can disable it without rebuilding:

- environment: `CONNOR_NOTE_IMPORT_ENABLED=false`
- persisted kill switch: `connor.feature.noteImport.enabled=false`

Current automated evidence includes:

- 10,000 Markdown files scanned without loss
- 1,000 queued operations with peak concurrency capped at three
- Provider-key isolation and Retry-After policy
- Zip traversal, symlink, compression-ratio and size-limit rejection
- Crash reconciliation without duplicate Session creation
- Attachment copying and message-reference persistence
- Source adapter fixtures for Obsidian, Notion and ENEX

Before default enablement, release engineering must additionally run on representative hardware:

- 1,000 real Note Session creation with Memory OS ingestion
- 1 GB attachment tree
- 500 MB real Notion ZIP through the production archive backend
- 1–2 GB real ENEX with peak RSS measurement
- Foreground Session switching/sending/search while background import runs
- Disk-full, permission-revocation, process termination and real Provider 429 fault injection
- Full `swift test` and signed app UI smoke tests

Do not expand the advertised capability to direct Notion ZIP import, automatic failed-stage retry, or unattended large-archive release claims while the corresponding gate is missing or failing. Use the kill switch if a regression affects the enabled import paths.
