# L4 Relaxed Entity Graph

Last updated: 2026-06-28 18:33 GMT+8

## Purpose

L4 is a relaxed stable entity / concept graph layer.

It is responsible for:

- stable entity anchors
- names and aliases
- controlled entity type strings
- entity-to-entity relations
- graph expansion over L4 relations

L4 is not a truth adjudication layer.

## Entity type policy

L4 uses a controlled medium-size entity type vocabulary through `MemoryOSEntityType`.

The canonical stored/projected type strings are:

```text
person
organization
group
role
population
place
facility
spatial_object
concept
theory
framework
discipline
standard
language
metric
identifier_scheme
creative_work
document
dataset
software
product
media_object
website
project
event
process
decision
task
rule
agreement
physical_object
device
vehicle
biological_entity
medical_entity
chemical_entity
economic_entity
award
unknown
```

LLM-provided raw labels are normalized at L4 projection and validation boundaries. For example:

- `university`, `school`, `company`, `institution` -> `organization`
- `scientist`, `author`, `researcher` -> `person`
- `parameter`, `variable`, `indicator`, `measure` -> `metric`
- `class`, `type`, `category`, `taxonomy_class`, `ontology_class` -> `concept`
- unsupported raw labels -> `unknown`

This is vocabulary hygiene, not a confidence/evidence gate. Unsupported raw labels should not expand the schema with one-off LLM type strings, but they also should not automatically turn L4 into a strict truth adjudication layer.

## Confidence and evidence policy

L4 records may still carry fields such as:

- `confidence`
- `evidenceSpanIDs`
- `sourceArtifactID`

These fields are kept for schema compatibility, traceability, debugging and future review workflows.

They are not validation gates for L4 relation acceptance.

Specifically:

- Low confidence does not reject an L4 relation.
- Missing evidence span IDs do not reject an L4 relation.
- Unknown evidence span IDs do not reject an L4 relation.
- Missing relation metadata such as `reason` or `causal_basis` does not reject an L4 relation.
- L4 graph expansion scoring does not multiply by LLM-provided confidence.

The reason is practical: current confidence and many evidence annotations are usually proposed by the same LLM that extracts the relation. Treating them as hard gates creates pseudo-strictness without a reliable independent verifier.

## What validation remains

L4 validation still keeps structural checks:

- relation subject must exist in the extracted entity set
- relation object must exist in the extracted entity set
- predicate must be a known `MemoryOSL4RelationPredicate`
- obvious invalid self-loops are rejected for predicates such as `INSTANCE_OF`, `SUBCLASS_OF`, `HAS_PART`, `PART_OF`, `DEPENDS_ON` and `REQUIRES`
- selected taxonomy predicates keep lightweight endpoint type sanity checks using controlled L4 entity type normalization
- `SAME_AS` still requires compatible controlled endpoint types after normalization
- governance-like relations still require at least one governance-like endpoint type

## Current-view selection

For L4 entity statements, current-view selection uses:

1. newer `validAt`
2. newer `committedAt`
3. deterministic `id` tie-breaker

It does not use confidence.

## Retrieval scoring

L4 expansion scoring uses:

- predicate retrieval weight
- graph depth decay

It does not use LLM-provided confidence.

## Future trust mechanisms

If L4 later needs stronger trust handling, it should come from independent mechanisms such as:

- source reliability
- multi-source corroboration
- user confirmation
- contradiction tracking
- review workflows
- provenance quality scoring outside the L4 relation acceptance path

Do not reintroduce LLM self-reported confidence as a hard acceptance gate.
