# DocNest Agent Workflow

## Project Focus
- Build a native macOS document management app in Xcode.
- Treat [../docs/requirements.md](../docs/requirements.md) as the current product source of truth.
- Keep implementation decisions aligned with the requirements unless the user explicitly changes scope.

## Core Workflow
- Work in small, functional increments.
- Prefer vertical slices that end in a working, verifiable state over large unfinished refactors.
- Before implementing, identify which requirement or requirement gap the change addresses.
- If a change affects behavior, data model, UI flow, architecture, or scope, update [../docs/requirements.md](../docs/requirements.md) in the same work cycle.
- Do not leave undocumented feature decisions behind in code only.

## Compileability Gate
- The app must remain compilable at all times.
- Never leave the repository in a knowingly broken build state at the end of a task.
- After every code change, validate compileability before considering the change complete.
- Once an Xcode project and scheme exist, use a real build command such as `xcodebuild` for validation.
- If the current workspace does not yet contain a buildable Xcode target, do not claim build validation; instead keep changes limited to documentation or scaffolding that does not create a broken intermediate state.
- If a change introduces compile errors, fix them before proceeding to any new feature work.

## Requirements Maintenance
- [../docs/requirements.md](../docs/requirements.md) must be kept current throughout implementation.
- Update requirements when adding, removing, refining, or reprioritizing functionality.
- Record important technical constraints that affect implementation order or architecture when they become clear.
- Keep the requirements document structured, concise, and implementation-relevant.

## Functional Change Definition
- A functional change is any change that adds, removes, or materially alters application behavior.
- Examples: new import flow, label editing, search behavior, persistence changes, fullscreen behavior, theme handling, PDF preview behavior.
- Pure formatting, typo fixes, comment-only edits, or non-behavioral documentation cleanup are not functional changes.

## Commit Policy
- After each completed functional change, create a git commit.
- Commit only when the relevant code, documentation, and build validation for that functional change are complete.
- Do not batch multiple unrelated functional changes into one commit.
- Do not include unrelated user changes or incidental repository noise in a commit.
- Keep commits focused and reversible.
- Use clear commit messages that describe the user-visible or architectural change.

## Preferred Change Sequence
- Step 1: Confirm the target requirement in [../docs/requirements.md](../docs/requirements.md), or update it first if missing or outdated.
- Step 2: Implement the smallest complete slice of the feature.
- Step 3: Build or otherwise validate compileability.
- Step 4: Update [../docs/requirements.md](../docs/requirements.md) to reflect the final behavior and constraints.
- Step 5: Create a git commit for that functional change.

## Quality Bar
- Favor native macOS patterns and keep the UI coherent in normal window mode, fullscreen mode, Light Mode, and Dark Mode.
- Prefer simple, debuggable implementations over premature abstraction.
- Preserve local data safety and library integrity over convenience shortcuts.
- Do not start the next functional change while the current one is unbuilt, undocumented, or uncommitted.