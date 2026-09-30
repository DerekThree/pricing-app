# Domain Docs

Engineering skills should consume this repo’s domain documentation when exploring the codebase.

## Before exploring, read these

- `docs/agents/wiki/01 Domain/CONTEXT.md`, or `CONTEXT-MAP.md` if it exists.
- `docs/ADR/` for ADRs that touch the area being changed. In a multi-context repo,
  also check context-specific ADR directories.

If these files do not exist, proceed silently. Do not suggest creating them upfront;
the domain-modeling skill creates them when terms or decisions are resolved.

## File structure

This is a single-context project:

```text
/
├── docs/agents/wiki/01 Domain/CONTEXT.md
├── docs/ADR/
├── pricing-backend/
└── pricing-dashboard/
```

## Use the glossary’s vocabulary

When output names a domain concept, use the term defined in
`docs/agents/wiki/01 Domain/CONTEXT.md`. Avoid synonyms that conflict with the
project's established vocabulary. If the concept is not defined, note the gap for
domain modeling.

## Flag ADR conflicts

If output contradicts an existing ADR, surface the conflict explicitly rather than
silently overriding it, and identify the ADR so it can be deliberately revisited.
