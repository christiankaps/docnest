# AGENTS.md

## Purpose

Defines how AI agents work on this project.

It must support new and existing projects, different agent runtimes, and different execution environments over time.

Keep this file short. Put project facts in project Sources of Truth, not here.

## Core Rules

1. **Understand before acting.** Inspect only context needed for the task.
2. **Do not invent project truth.** Separate known facts, assumptions, and unknowns.
3. **Be critical.** Challenge contradictions, weak assumptions, unnecessary complexity, obsolete choices, and material risks.
4. **Preserve user agency.** Make small reversible choices autonomously. Escalate consequential, irreversible, scope-changing, or strategic decisions with a recommendation.
5. **Preserve user work.** Never discard, overwrite, revert, or absorb unrelated changes.
6. **Keep scope tight.** Make the smallest coherent change that solves the problem.
7. **Prefer simplicity.** Complexity must justify itself.
8. **Prefer consistency.** Follow established project conventions unless a project-wide change is justified.
9. **Verify before claiming success.**
10. **Keep integrations valid.** Every integration into the default branch must leave the project coherent, functional, and reproducible for its maturity.
11. **Keep durable knowledge in the project.** Do not rely on prior chat context.
12. **Protect sensitive data and external systems.** Never expose secrets/private data or perform destructive, costly, publishing, deployment, or other irreversible external actions without explicit authorization or an established workflow.

When guidance conflicts, prefer:
1. platform, safety, legal, and tool constraints;
2. explicit user decisions changing project policy;
3. authoritative project Sources of Truth;
4. this file;
5. enforced project configuration/automation;
6. established local convention;
7. ecosystem best practice;
8. agent preference.

A task-level request does not silently rewrite project-wide policy.

## Communication and Decisions

Keep communication concise and evidence-based. Ask only questions that materially affect the result.

Resolve minor reversible details independently.

For consequential choices:

> **Recommendation:** A  
> **Why:** key reason/trade-off  
> **Alternative:** B when relevant  
> **Decision:** A / B?

Do not repeat established context unless it changed or is needed to understand the result.

## Context Efficiency

Use context proportionally to risk and uncertainty.

- Start narrow; expand only when needed.
- Search before reading whole files.
- Read relevant sections, not entire artifacts, where possible.
- Do not reread unchanged context without reason.
- Prefer project Sources of Truth over reconstructing knowledge from chat/history.
- Prefer project-owned commands over rediscovering tool-specific workflows.
- Inspect diffs/changed regions after edits.
- Use targeted checks and concise output before broad verification.
- Stop investigating once evidence is sufficient.

Permanent instructions also consume context. Add prose only when its future value exceeds that cost.

## Project State and Knowledge

`PROJECT.md` should record:
- `Workflow: INITIALIZING | ESTABLISHED`
- `Maturity: CONCEPTION | MVP | RELEASE_CANDIDATE | PRODUCTION | MAINTENANCE`
- purpose, scope, constraints, current policies, and acceptance expectations.

Baseline files:
- `AGENTS.md` — agent operating rules.
- `PROJECT.md` — current project truth/policy.
- `INBOX.md` — user-owned pending input.
- `DECISIONS.md` — accepted material decisions awaiting consolidation.
- `LESSONS.md` — recurring/systemic agent failures awaiting durable prevention.

Create `PLAN.md` only when persistent planning is useful.

Create additional Sources of Truth only when justified (`ARCHITECTURE.md`, `REQUIREMENTS.md`, `ENVIRONMENTS.md`, `SOURCES.md`, etc.).

For materially different subprojects, prefer a small nested `AGENTS.md` over expanding the root file.

## Start of Work

Before substantial work, inspect only what is relevant:
- applicable `AGENTS.md`;
- `PROJECT.md` and relevant Sources of Truth;
- current execution capabilities;
- relevant queues/plan;
- Git/worktree state before modifying versioned artifacts.

If `INBOX.md` is non-empty, notify the user before substantial unrelated work. Do not silently execute it.

## Initialization and Adoption

### New Project

If project context is missing, enter **Conception Mode**.

Actively guide the user from an initial idea to a sufficiently defined project. Progressively establish:
- problem or opportunity;
- intended outcome;
- users or audience where relevant;
- goals and success criteria;
- scope and non-goals;
- constraints and assumptions;
- first useful milestone or MVP;
- fundamental solution approach;
- verification and working conventions.

Do not use a fixed questionnaire. Infer what is safe, challenge weak assumptions, recommend sensible defaults, and ask only consequential questions—preferably one decision at a time.

Persist established knowledge in `PROJECT.md` and appropriate Sources of Truth. Use `TBD` for unresolved items instead of inventing certainty.

Set `Workflow: INITIALIZING`, `Maturity: CONCEPTION`, and remain there until enough context exists to work reliably. Then establish project commands and Git/integration policy as needed and set `Workflow: ESTABLISHED`.

### Existing Project

Preserve existing knowledge before replacing or restructuring instructions.

Inspect only relevant prior instructions, docs, Git/workflow, project commands, CI, architecture/requirements, conventions, and maturity.

Establish a cheap baseline, then preserve, relocate, refine, challenge, or remove previous guidance as appropriate.

Retire old instructions only after useful content is preserved or intentionally rejected.

## Execution Environment and Commands

Do not assume previous capabilities are still available. Determine only what matters for the task.

Project rules define required outcomes; the mechanism may vary by environment.

If the preferred mechanism is unavailable:
1. use an equivalent approved mechanism where possible;
2. preserve intended semantics;
3. perform the strongest meaningful subset available;
4. state required verification that remains unperformed.

Do not weaken project requirements because an environment lacks a capability.

Prefer stable project-owned commands.

If a `Makefile` exists, start with `make help`; use `make verify` as the integration gate when defined.

Do not inspect a working command's implementation unless it fails, must change, or its behavior is relevant.

Use another established task runner instead of introducing Make unnecessarily.

Prefer deterministic, non-interactive commands over GUI steps, prompts, aliases, or personal machine state.

Do not edit generated files directly unless the workflow requires it; change the source and regenerate.

## Verification and Integration

Scale verification roughly with:

`risk ≈ impact × uncertainty × irreversibility`

Use the cheapest useful checks first. Prefer targeted checks during iteration and the project integration gate before integration.

If verification fails, distinguish current-change failures from pre-existing failures, environment issues, stale project knowledge, or incorrect assumptions before modifying further.

Do not claim success while required verification remains unperformed.

Scale rigor with maturity:
- **CONCEPTION:** optimize for understanding.
- **MVP:** optimize for learning; rough edges may be acceptable, broken integration is not.
- **RELEASE_CANDIDATE:** establish sustainable release quality.
- **PRODUCTION / MAINTENANCE:** favor safe incremental evolution, compatibility, and proportionate verification.

Do not apply production constraints prematurely during MVP or carry MVP shortcuts silently into Production.

## Git, Dependencies, Environment

Use Git unless there is a concrete reason not to.

Keep commits coherent and atomic; never mix unrelated user changes.

Use Git for history; keep project files focused on current truth.

Before adding a dependency, prefer:
1. existing project/platform capability;
2. a small safe local implementation when genuinely simpler;
3. a mature lightweight dependency;
4. larger dependencies only when benefits justify ongoing cost.

Prefer project-local reproducible tooling.

Do not install global packages or alter shell/system configuration, credentials, or machine-wide services without explicit authorization.

## Queues

- `INBOX.md`: user-owned; do not modify independently.
- `DECISIONS.md`: only accepted material decisions awaiting consolidation.
- `LESSONS.md`: only recurring/systemic agent failures likely to matter again.

Consolidate decisions and lessons into the appropriate Source of Truth, tooling, or enforcement; verify; then delete the queue entry.

Empty queues are the desired steady state.

## Maintenance

Update `AGENTS.md` only when a durable operational rule clearly changes or the user requests workflow refinement.

Before adding a rule ask:

> **Will this predictably change how a future agent works on multiple future tasks?**

If not, it belongs elsewhere.

Prefer replacing, consolidating, automating, or deleting instructions over appending prose.

Do not encode temporary environment limitations as permanent policy.

## Fresh-Agent Test

A fresh capable agent without prior chat access should be able to determine:
- what the project is and its current state;
- which artifacts are authoritative;
- how to work consistently;
- which project-owned commands to use;
- how to verify changes;
- how Git/integration work;
- which pending input, decisions, lessons, plans, or open questions matter;
- which constraints and invariants must not be violated.

If not, improve project artifacts rather than relying on conversational memory.
