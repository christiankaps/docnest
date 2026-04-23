# Contributing

## Goal

Contributions should preserve three things at the same time:

- native macOS behavior
- predictable local-data handling
- understandable code and documentation

## AI Agent Workflow

Repository-wide agent instructions live in [AGENTS.md](/Users/kaps/Projects/docnest/AGENTS.md).

For code changes, the required workflow is:

- implement the change
- add tests for new features and bug fixes
- update requirements documentation when features or app behavior change
- run an independent AI review with a different model, starting with a fast reviewer
- if the fast reviewer is clean, run a second review with a stronger slower model
- run the full test suite only after all review passes are clean
- create a commit only after reviews and the full test run pass

## Code Organization Expectations

- keep business behavior in `Domain/UseCases` or narrowly scoped services
- keep filesystem and persistence details in `Infrastructure/`
- keep user-facing workflows in `Features/` and `App/`
- avoid turning `Shared/` into a dumping ground for domain logic

## Swift Style Expectations

- keep Swift code clear and easy to follow
- prefer existing project patterns and Apple frameworks over unnecessary abstractions
- keep dependencies minimal and avoid adding new libraries unless clearly justified
- document important types, methods, properties, invariants, and non-obvious behavior
- use `///` documentation comments for important APIs and use inline comments only where they add real value

## Documentation Expectations

Substantial changes should update documentation as part of the same change.

Update Markdown docs when:

- user-visible behavior changes
- architecture or responsibilities change
- storage, import, migration, or release behavior changes

Add inline code documentation when:

- a public or widely used internal API has non-obvious behavior
- a service depends on filesystem, concurrency, or security-scope assumptions
- a coordinator owns important state or orchestration rules
- a workflow contains invariants that future maintainers must preserve

## Inline Comment Style

Use `///` documentation comments for:

- important types
- important methods
- non-obvious properties that express intent or invariants

Use regular comments sparingly inside functions for:

- tricky algorithms
- sequencing constraints
- performance-sensitive or safety-sensitive logic

Do not add comments that restate obvious code.

## Testing Expectations

Behavior changes should include tests whenever practical, especially for:

- import behavior
- library validation and repair
- search/filter semantics
- storage and naming rules
- watch-folder behavior

## Documentation Checklist for Feature Work

Before considering a substantial change done, verify:

- high-level docs still describe the current behavior accurately
- affected core files have enough inline docs
- tests cover the changed behavior
- README links still point to the right deep documentation
