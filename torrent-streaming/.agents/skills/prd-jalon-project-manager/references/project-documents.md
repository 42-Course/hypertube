# Project Documents

Read these documents from the repository root. Use absolute paths in final reports when referencing files.

## Required Read Order

1. `docs/PRD.md`
   - Source of product goals, architecture, non-goals, services, tests, reviews and acceptance criteria.
   - Treat it as the highest project-specific requirement document.

2. `docs/JALONS.md`
   - Index of jalons and delivery order.
   - Use it to identify the next jalon and avoid skipping sequence.

3. `docs/TECHNICAL_CONTRACTS.md`
   - Cross-cutting implementation contracts extracted from initial reviews.
   - Covers state ownership, range-server APIs, libtorrent loop, HTTP Range, HLS, Sidekiq, process lifecycle, recovery, healthchecks and fixtures.
   - It resolves ambiguity in the PRD or jalon docs.

4. `docs/TRACEABILITY.md`
   - Matrix linking PRD requirements to jalons and tests.
   - Use it to check that implementation and tests cover the intended behavior.

5. `docs/PROJECT_MEMORY.md`
   - Durable memory of decisions, errors, risks and fixes.
   - Update it after non-trivial decisions, mistakes, bug fixes, blockers or test limitations.

6. `docs/REVIEW_LOG.md`
   - Records documentary, targeted and final reviews.
   - Update it after every reviewer subagent pass and after resolving findings.

7. `docs/jalons/<NN-...>.md`
   - The detailed implementation plan for the current jalon.
   - It defines the lead developer scope, test expectations and acceptance gate.

## Project Manager Use

- Read all cross-cutting documents once at the start of a PM turn.
- Re-read the current jalon before spawning the lead developer.
- Re-read `PROJECT_MEMORY.md` and `REVIEW_LOG.md` before deciding whether a jalon is complete.

## Lead Developer Use

In the lead-developer prompt, require the agent to read:

- PRD;
- JALONS index;
- technical contracts;
- traceability matrix;
- project memory;
- review log;
- current jalon document;
- local source files relevant to the jalon.

The lead developer should not rely on PM summaries as a substitute for reading the files.

