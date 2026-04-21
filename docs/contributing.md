# Contributing

## Goal

Contributions should preserve three things at the same time:

- native macOS behavior
- predictable local-data handling
- understandable code and documentation

## Code Organization Expectations

- keep business behavior in `Domain/UseCases` or narrowly scoped services
- keep filesystem and persistence details in `Infrastructure/`
- keep user-facing workflows in `Features/` and `App/`
- avoid turning `Shared/` into a dumping ground for domain logic

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
