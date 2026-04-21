# Testing

## Test Targets

The repository currently includes:

- `DocNestTests` for unit and integration-style tests around domain, infrastructure, layout logic, and import behavior
- `DocNestUITests` for UI-level verification

Most behavior-heavy coverage lives in `DocNestTests`.

## Running Tests

Run the main test suite:

```sh
xcodebuild test -project DocNest.xcodeproj -scheme DocNest -only-testing:DocNestTests
```

Run all tests:

```sh
xcodebuild test -project DocNest.xcodeproj -scheme DocNest
```

Build only:

```sh
xcodebuild -project DocNest.xcodeproj -scheme DocNest build
```

## What `DocNestTests` Covers

The unit and integration test target covers:

- library creation and validation
- import behavior
- duplicate handling
- folder and watch-folder scanning
- label and smart-folder behavior
- layout helper behavior
- release version parsing
- deletion and export workflows

The import-related tests are especially important because they exercise real temporary files, package layout, and recursive folder behavior.

## What Belongs in Unit or Integration Tests

Use `DocNestTests` when the behavior can be tested without full UI automation, especially for:

- use cases
- filesystem services
- storage rules
- search semantics
- import pipeline behavior
- migration and validation helpers

## What Belongs in UI Tests

Use `DocNestUITests` when the important risk is wiring or user interaction, such as:

- window-state transitions
- menu and command behavior
- drag-and-drop affordances
- import and toast behavior at the UI layer
- multi-panel layout behavior that depends on app runtime integration

## Testing Guidance for New Features

When adding or changing behavior:

- add unit or integration tests for core business logic and filesystem behavior
- add UI tests only where user interaction wiring is the real risk
- prefer focused integration tests around use cases and services over broad end-to-end tests when possible

For import changes, verify at least:

- accepted inputs
- skipped/duplicate behavior
- self-import protection
- summary/result behavior
- filesystem side effects
