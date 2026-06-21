---
name: prd-jalon-project-manager
description: "Project-management workflow for implementing a PRD by sequential jalons/milestones with context-efficient delegation. Use when Codex must run this repository project from docs/PRD.md and docs/jalons/*.md as a lead project manager: spawn one fresh lead-developer subagent per jalon, require that lead to read the project documents, implement the jalon, run tests, request code reviews through subagents when authorized, document decisions/errors, and create small verified commits."
---

# PRD Jalon Project Manager

## Role

Act as the project manager for a PRD implementation split into sequential jalons. Keep the main thread focused on orchestration, integration, verification, documentation and commits. Delegate each implementation jalon to a fresh lead-developer subagent so context remains scoped to one jalon at a time.

Use this skill only when the user has explicitly asked to run the project with this delegation model or invokes this skill for the PRD implementation.

## Required Project Documents

Before starting or delegating work, read the relevant local project documents. For the purpose of each document and the required read order, read [references/project-documents.md](references/project-documents.md).

At minimum, the project manager reads:

- `docs/PRD.md`
- `docs/JALONS.md`
- `docs/TECHNICAL_CONTRACTS.md`
- `docs/TRACEABILITY.md`
- `docs/PROJECT_MEMORY.md`
- `docs/REVIEW_LOG.md`
- the current `docs/jalons/<NN-...>.md`

## Project Manager Workflow

1. Inspect the current worktree and latest commits.
2. Determine the next incomplete jalon from `docs/JALONS.md`, `docs/PROJECT_MEMORY.md`, `docs/REVIEW_LOG.md`, tests and git history.
3. Read the target jalon document and all cross-cutting docs listed above.
4. Spawn exactly one fresh lead-developer subagent for that jalon when subagents are available and the user has authorized this workflow.
5. Give the lead developer ownership of the jalon scope and clear boundaries. Use [references/prompts.md](references/prompts.md) for the delegation prompt.
6. While the lead works, do only non-overlapping PM work: update traceability, prepare acceptance checks, inspect tests, or review docs.
7. When the lead returns, inspect its changed files and summary. Do not blindly accept work.
8. Run the relevant tests locally from the main thread when feasible.
9. Fix integration issues directly only when they are small and clearly within the jalon scope; otherwise send the lead one focused follow-up.
10. Update `docs/PROJECT_MEMORY.md` with important decisions, errors, fixes and reasons.
11. Update `docs/REVIEW_LOG.md` when reviews were run.
12. Maintain explicit jalon progress. If no dedicated status file exists, keep an `Avancement jalons` section in `docs/PROJECT_MEMORY.md` with each jalon status: `pending`, `in_progress`, `blocked`, or `done`.
13. Commit each coherent, tested step with a small descriptive message.
14. Proceed to the next jalon only after the current jalon acceptance criteria are met or a real blocker is documented.

## Lead Developer Expectations

Each lead developer subagent must:

- rebuild context from the repository, not from conversation memory;
- read the required documents before coding;
- implement only the assigned jalon;
- keep changes scoped and aligned with existing project contracts;
- create or update tests before relying on behavior;
- run relevant tests and report exact commands/results;
- run at least one reviewer subagent before claiming the jalon is complete when the jalon changes code, runtime behavior, tests or project contracts;
- document decisions, errors and fixes in `docs/PROJECT_MEMORY.md`;
- keep commits small, or return changes ready for PM integration if it cannot commit;
- never revert unrelated user or other-agent work.

## Review Policy

Use review subagents at two levels:

- During every implementation jalon: require at least one focused code-review subagent before the jalon can be marked `done`.
- During a jalon with multi-domain changes: require one reviewer per affected high-risk domain, such as infra, state, torrent/libtorrent, HTTP Range, ffmpeg/HLS, security, tests or UI.
- Before final delivery: run the four mandatory PRD reviews: torrenting/libtorrent, ffmpeg/HLS, infra/integration, user/UI.

The only allowed exception is a documentation-only or planning-only jalon with no code, runtime, test or contract behavior changes. Record that exception in `docs/REVIEW_LOG.md`.

Blocking review findings must be fixed before marking a jalon or project complete. Non-blocking findings must be recorded with rationale.

## Commit Policy

Commit after every verified coherent step, not only at the end of a jalon. A commit requires:

- code or docs scoped to one logical step;
- relevant tests passing or a documented reason they could not run;
- `docs/PROJECT_MEMORY.md` updated when a decision/error/fix matters;
- no unrelated staged files.

Prefer messages shaped like:

```text
docs: update jalon contracts
infra: scaffold compose services
state: add atomic media store
range: implement http range parser
transcoder: add interactive ffmpeg builder
```

## Jalon Status Policy

Avoid relying only on inference from git history. Track jalon progress explicitly:

- mark a jalon `in_progress` before spawning its lead developer;
- mark it `blocked` with a concrete blocker when work cannot continue;
- mark it `done` only after acceptance criteria, tests and required subagent reviews are verified;
- record the commit hash or evidence that proves completion when possible.

## Completion Gate

Do not mark the project complete until the current repository evidence proves:

- every PRD acceptance criterion is implemented or explicitly out of scope in the PRD;
- every jalon acceptance criterion is satisfied;
- required tests pass or unavoidable external limitations are documented;
- mandatory reviews are complete and blocking findings are fixed;
- project memory, traceability and review logs are current;
- the worktree is clean after final commits.
