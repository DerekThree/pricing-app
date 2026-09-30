---
aliases:
  - Agent Wiki Handoff
  - How to Create Great Wikis
status: current
tags:
  - change-guide
  - documentation
  - agent-wiki
---

# Creating great agent wikis

An agent wiki is successful when a future agent can form the right mental model, find the authoritative evidence, and identify the change surface without reading the entire repository. It is not a replacement for code, contracts, tests, or decisions. It is the connective tissue that explains how those sources fit together.

This handoff describes the method used to build this vault.

## Page 1 — Discover and structure the knowledge

### 1. Define the questions the wiki must answer

Start with agent tasks, not repository directories. A useful project wiki should answer:

- What does the application do today?
- What are the canonical domain concepts and how do they relate?
- What happens during the important end-to-end workflows?
- Where is each behavior implemented and enforced?
- Which documents are authoritative when sources disagree?
- What is implemented, accepted as a decision, merely planned, or still open?
- Which files and tests change together when a feature changes?

The discovery step is complete when every major feature request can be routed to a small set of notes and authoritative sources.

### 2. Establish authority before explaining behavior

Identify the source of truth for each kind of fact. Typical categories are:

| Fact | Likely authority |
|---|---|
| Domain terminology | Domain glossary or `CONTEXT.md` |
| Accepted design decision | ADR |
| HTTP request and response shape | API contract |
| Persisted structure and constraints | Migrations |
| Current runtime behavior | Code and executable tests |
| Cross-layer validation ownership | Validation matrix |
| Future direction | Roadmap or planned architecture document |

Put this authority map near the wiki entrance. [[00 Home/Project Knowledge Home|Project Knowledge Home]] does this before presenting its mental model. It prevents the wiki from becoming a competing source of truth.

Every explanatory claim must have evidence. If code, tests, and planning documents disagree, record the observed disagreement or uncertainty. Do not combine them into a cleaner story that the repository does not support.

### 3. Learn the vocabulary before mapping the system

Read the domain glossary before naming pages, diagrams, workflows, or relationships. Preserve distinctions that the implementation may blur. In this project, **Fee** and **Pricing Plan Fee** are different concepts even though both may appear as “fee” in local code.

Create a vocabulary note such as [[01 Domain/CONTEXT]] that:

- points to the canonical glossary;
- uses every canonical term consistently;
- explains commonly confused distinctions;
- identifies implementation names that differ from the domain language;
- avoids inventing new terminology to make the prose sound smoother.

Then create a relationship note such as [[01 Domain/Concept Relationships]]. Definitions answer “what is this?” Relationships answer “what changes when this changes?” Agents need both.

### 4. Investigate the application in passes

Do not read files randomly. Use a sequence that progressively sharpens the model:

1. Read repository instructions, domain context, ADRs, contracts, and existing architecture documents.
2. Identify runtime entry points, feature packages, routes, persistence adapters, and generated-code boundaries.
3. Trace the most important workflow end to end.
4. Read entities and migrations to verify relationships and invariants.
5. Read tests to discover edge cases, correlation rules, failure isolation, and intended status combinations.
6. Compare implemented source with future architecture documents.

Graph or code-search tools are excellent for finding candidate seams, but their output is navigation evidence, not automatically an explanation. Verify the important path in source before writing it as fact.

The investigation is complete when the main workflow can be narrated from input to output, including error paths and persistence boundaries, with a source behind every non-obvious step.

### 5. Separate current behavior from future architecture

Repositories often contain old designs, accepted decisions awaiting implementation, and current code at the same time. A great wiki labels those states explicitly.

Use a comparison note like [[05 Reference/Current and Planned System]] when the distinction affects multiple pages. State what exists in current source, what an ADR decides, what a planning document proposes, and what remains unresolved. Never describe a planned service, database, notification, or workflow in the present tense unless current source implements it.

### 6. Build the smallest useful information architecture

Organize notes around questions and workflows:

```text
00 Home/          routing and source authority
01 Domain/        vocabulary and concept relationships
02 Architecture/  current system and component seams
03 Workflows/     end-to-end business behavior
04 Change Guides/ implementation impact and handoffs
05 Reference/     validation, status, and current-versus-planned distinctions
```

Split a note when different tasks need different material. Keep concepts together when every reader needs the same context. The goal is progressive disclosure: the home note routes; architecture notes explain boundaries; workflow notes explain sequences; change guides translate the model into implementation impact.

## Page 2 — Write, connect, and validate the wiki

### 7. Write each note around one job

A strong note has a recognizable purpose in its first paragraph. A practical structure is:

1. State the outcome or mental model.
2. Show the important relationship or sequence.
3. Explain invariants and edge cases.
4. Link to authoritative implementation evidence.
5. Link to the next note needed for a related task.

Prefer compact tables for exact mappings and Mermaid diagrams for relationships or multi-step flows. Use diagrams only when they make dependencies, hierarchy, or sequence easier to understand than prose. Every diagram must agree with the surrounding text and source.

Write source paths where an agent will need to act. “The backend validates this” is weaker than naming the validator, migration, error mapper, and owning tests. Do not turn the note into a file dump; identify the seam and explain why those files belong together.

### 8. Explain behavior through workflows

Architecture lists components. Workflows teach the application.

For each important workflow, document:

- the caller and entry point;
- validation before business behavior;
- mapping between transport, domain, and persistence models;
- lookup and precedence rules;
- transaction or snapshot boundaries;
- success output and correlation identifiers;
- isolated failures versus whole-request failures;
- the tests that demonstrate edge cases.

[[03 Workflows/Evaluate a Pricing Batch]] is an example: it follows one request from contract validation through configuration loading, account resolution, Fee Request evaluation, and result correlation. That flow gives agents a model they can use when changing any one layer.

### 9. Translate knowledge into change impact

The wiki becomes operational when it tells agents what changes together. Add a change guide or impact table like [[04 Change Guides/Implement a Feature or Change]]. Map feature types to:

- the primary implementation seam;
- downstream consumers;
- generated artifacts;
- migrations or contracts;
- validation ownership;
- the lowest useful test and the required cross-boundary test.

This is more valuable than a generic instruction to “update tests and docs.” It tells the next agent which tests and documents carry the behavior.

### 10. Link deliberately

Every note should be reachable from a task-oriented route. Links should communicate why the target matters, not merely mention a neighboring page.

Use links for three purposes:

- **navigation:** where to begin for a task;
- **definition:** where a canonical concept is explained;
- **evidence:** where an authoritative fact is implemented or decided.

Avoid orphan notes, circular tours that never reach evidence, and repeated definitions spread across several pages. Put one explanation in its best home and link to it elsewhere.

### 11. Preserve observed facts and uncertainty

Use precise status language:

- **Implemented:** verified in current code or tests.
- **Accepted:** recorded by an ADR; implementation may be partial or absent.
- **Planned:** described by a design or roadmap.
- **Open:** the source explicitly leaves the decision unresolved.
- **Unknown:** available evidence cannot establish the answer.

Do not infer intent, history, or causes from naming or directory structure. If a claim is an inference, label it and explain the supporting observations.

### 12. Validate the vault as a product

Before handoff, verify:

- every canonical vocabulary term is represented correctly;
- every internal wiki link resolves to a note and, when used, a real heading;
- every relative source link resolves to an existing file or directory;
- the home note reaches every major branch of the wiki;
- no current-behavior page silently includes planned behavior;
- contract, code, migration, validation, and test references agree;
- diagrams match the prose;
- no page duplicates an authoritative source without identifying which source wins;
- each workflow includes failures and correlation rules, not only the happy path.

Validation is complete when an agent can start from the home note, follow one task path to the owning implementation, and find no broken link or unsupported explanatory claim.

## Common failure modes

- **Repository tour:** describing folders without explaining behavior or dependencies.
- **Code paraphrase:** restating methods line by line without giving a durable mental model.
- **Roadmap blending:** presenting planned topology as current runtime behavior.
- **Vocabulary drift:** using convenient synonyms that erase domain distinctions.
- **Source competition:** copying contracts or validation matrices into notes without naming the authority.
- **Happy-path bias:** omitting status outcomes, precedence, retries, or failure isolation.
- **Link sprawl:** creating many notes without task-oriented routes through them.
- **False completeness:** documenting every screen but not the workflows agents must change safely.

## Handoff standard

A great agent wiki is finished when it is trustworthy, navigable, and actionable:

- **Trustworthy:** claims are evidenced and status is explicit.
- **Navigable:** agents enter by task and reach progressively deeper context.
- **Actionable:** workflows and change maps identify the code, contract, data, validation, and tests that move together.

The strongest wiki does not try to contain the whole repository. It teaches the model that makes the repository understandable.

