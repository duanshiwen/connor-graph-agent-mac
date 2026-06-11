# Phase 5: Automation / Labels / Statuses

Last updated: 2026-06-11 17:43 GMT+8

## Status

Phase 5 promotes Automations, Labels, and Statuses into Connor-owned Product OS control-plane state.

This phase does not introduce arbitrary background execution. Automations are audit-first: they match events, persist trigger records, and surface timeline entries. Action execution remains deferred until Connor has an explicit reviewed execution engine.

## Goals

- Keep labels/statuses as first-class Product OS configuration, not hard-coded UI-only state.
- Add a local automation registry under the single Connor Home root.
- Evaluate automation rules for session governance and registry events.
- Persist deterministic trigger records for review and audit.
- Keep all execution subject to Connor permission policy; no `.allowAll` or hidden background mutation.

## Implemented

### Core domain

- `ProductOSAutomationTriggerKind`
- `ProductOSAutomationTrigger`
- `ProductOSAutomationActionKind`
- `ProductOSAutomationAction`
- `ProductOSAutomationRule`
- `ProductOSAutomationConfig`
- `ProductOSAutomationEventContext`
- `ProductOSAutomationTriggerRecord`

### Repository

`AppProductOSAutomationRepository`:

- Loads or creates `automations/automations.json`.
- Mirrors governance statuses to `statuses/statuses.json`.
- Mirrors governance labels to `labels/labels.json`.
- Evaluates enabled rules against event context.
- Persists trigger records to `automations/automation-trigger-log.json`.
- Validates duplicate IDs and missing action fields.
- Rejects unsafe automatic archive actions.

### Built-in automation rules

- `needs-review-flags-graph-review`
  - Trigger: session status changed to `needs_review`.
  - Records review-oriented timeline suggestions.
  - Suggests `graph-review` label.
  - Requires review.
- `important-label-adds-review-note`
  - Trigger: `important` label added.
  - Records an audit-only review note.

### Native UI

The Product OS panel now includes:

- Status definitions.
- Label definitions.
- Automation rules with enable/disable toggles.
- Recent automation trigger log.
- Summary cards for automations and trigger records.

### App integration

Automation evaluation is triggered by:

- Session status changes.
- Session label add/remove.
- Session archive/restore.
- Source registry status changes.
- Skill registry status changes.

Matched rules insert normalized `automationTriggered` timeline entries and persist trigger records.

## Boundaries

Allowed in Phase 5:

- Local automation config and validation.
- Event matching.
- Trigger log persistence.
- UI visibility and rule enable/disable toggles.
- Labels/statuses config mirroring.

Deferred:

- Arbitrary background execution.
- Scheduled automation jobs.
- Webhooks or external side effects.
- Fully editable label/status definitions in UI.
- Automatic mutation actions without explicit review/execution layer.

## Guardrails

- No multi-workspace abstraction is introduced.
- Automations cannot bypass Connor permission policy.
- Automations are audit-first and review-friendly.
- Automatic archival is rejected until explicit execution review exists.
- Graph memory remains governed by the graph admission pipeline.
- Labels/statuses remain Connor-owned configuration; SDK engines do not own them.

## Validation

Phase 5 adds tests covering:

- Default automation rule seeding.
- Labels/statuses mirror files under single Home root.
- Duplicate rule rejection.
- Missing required action field rejection.
- Unsafe automatic archive rejection.
- Status and label trigger matching.
- Trigger log persistence.

## Next Slice

Recommended Phase 6 candidates:

1. Reviewed Automation Execution Engine:
   - execute safe mutations only after explicit policy decision
   - dry-run preview
   - audit records for action started/finished/failed
2. Editable Product OS Settings:
   - create/edit status definitions
   - create/edit label definitions
   - create/edit automation rules
3. Skill manifest loader:
   - parse `SKILL.md`
   - bind skills to automation triggers
   - inject instructions before model request under policy
4. MCP Source Runtime skeleton:
   - connector lifecycle
   - credential references
   - source permission envelope
   - source audit events
