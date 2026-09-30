# Project AGENTS.md

## Sources of truth

- Domain and decisions: `docs/agents/domain.md` and `docs/ADR/`. 
- For cross-repository history or reusable knowledge, read `docs/agents/wiki/00 Home/Project Knowledge Home.md`.
- Issues and specs: `docs/agents/issue-tracker.md`.
- Contracts, code, migrations, tests, domain context, ADRs, `docs/Validations.md`, and source tickets remain authoritative for their own facts.

## Maven

- Run Maven with `sandbox_permissions: "require_escalated"` on the first attempt because dependency resolution and Maven cache access are blocked in the sandbox. The elevation authorizes only Maven network/cache access; it does not authorize source-file edits.

## Repository ownership

- Treat an ownership or unsafe-repository warning as diagnostic information. Stop and ask the user
  before taking any ownership-related action.
- Preserve repository and `.git` ownership.
- Never initialize or delete a `.git` directory unless the user explicitly requests that exact
  operation.

## Graphify

This project has knowledge graphs at `pricing-backend/graphify-out/` and `pricing-dashboard/graphify-out/` with god nodes, community hubs, and cross-file relationships. Run graphify commands from `pricing-backend/` or `pricing-dashboard/`.

- For `/graphify`, use the installed graphify skill or instructions before doing anything else.
- For codebase questions, first run `graphify query "<question>"` when `graphify-out/graph.json` exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts.
- Dirty `graphify-out/` files are expected after hooks or incremental updates. Skip graphify only for stale or incorrect graph output, or when the user explicitly says not to use it.
- If `graphify-out/wiki/index.md` exists, use it for broad navigation instead of raw source browsing.
- Read `graphify-out/GRAPH_REPORT.md` only for broad architecture review or when query/path/explain do not provide enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
