# DocNest Lessons Learned

This document captures practical lessons from building and stabilizing DocNest. For the normative product contract, see [requirements.md](/Users/kaps/Projects/docnest/docs/requirements.md).

## Overview

DocNest works best when it behaves like a native macOS document app first and a custom UI experiment second. The strongest results came from simplifying interaction models, separating fast UI feedback from heavy background work, and treating library integrity as a core product feature rather than a maintenance task.

## UX and Interaction Lessons

### Keep row interactions simple
Problem pattern: combining single-click, double-click, drag, drop, and context menu on the same full-row surface made selection unreliable in SwiftUI on macOS.

What we learned: normal selection must win. If users cannot reliably click once to select, the app feels broken even when rendering performance is otherwise acceptable.

Preferred rule: primary row surfaces should do one thing first: select. Dragging should use a smaller dedicated hotspot when needed, and edit actions should live in context menus or isolated controls unless there is a very strong reason not to.

### Selection feedback must not wait on detail rendering
Problem pattern: document selection was visually coupled to inspector work such as PDF preview loading, file-availability checks, and multi-selection label summaries.

What we learned: users judge responsiveness from the first visible reaction, not from the final detail state.

Preferred rule: keep immediate selection state separate from deferred inspector/detail state. Row highlight and keyboard navigation should update instantly, while inspector content can coalesce behind them.

### Visible order must be the navigation order
Problem pattern: grouped document lists could navigate by an internal sorted cache that did not exactly match what the user saw on screen.

What we learned: keyboard navigation that disagrees with the visible list destroys trust very quickly.

Preferred rule: arrow-key navigation, shift-selection, and follow-up selection operations must always use the currently visible list order after grouping and sorting are applied.

## Data Integrity and Library Safety

### Treat integrity as product behavior, not hidden maintenance
Problem pattern: package structure, metadata drift, and missing derived data were easy to think of as internal concerns.

What we learned: users experience data integrity as trust. Diagnostics, validation, migration, and conservative self-healing materially improve the product, not just the codebase.

Preferred rule: every library open should be an opportunity to validate, report, and safely repair what can be repaired. Repairs should be logged so the app remains explainable.

### Persisted library restore needs explicit safety rules
Problem pattern: security-scoped bookmarks can legitimately reopen moved libraries, but they can also reopen libraries that the user has moved to Trash.

What we learned: "technically restorable" is not always "correct to auto-open."

Preferred rule: restoring a moved library is desirable, restoring a trashed library automatically is not. Auto-restore should include guardrails such as Trash rejection and invalid-state fallback to the normal welcome flow.

### Self-import prevention matters early
Problem pattern: library packages and watch folders can accidentally point back into the active library, causing self-import loops or repeated invalid import attempts.

What we learned: a filesystem-first product must explicitly defend itself against its own package structure.

Preferred rule: the import pipeline and watch-folder logic should reject the active library package and its internal directories before import work begins.

## macOS Platform Lessons

### Native material and control hierarchy usually age better than custom chrome
Problem pattern: heavy custom row backgrounds, boxed panels, and overly dense inline controls made the app feel less native and harder to scan.

What we learned: DocNest gets cleaner and more modern when it leans into macOS materials, semantic typography, and toolbar hierarchy instead of fighting them.

Preferred rule: start with native macOS structure and only add custom styling where it creates real clarity or brand value.

### Menu cleanup should be explicit and continuously verified
Problem pattern: default macOS menu items and writing-tools entries can reappear if they are only partially suppressed or if the filtering approach is brittle.

What we learned: menu-bar correctness is part of the product polish, especially in a focused document app.

Preferred rule: keep only supported commands visible, and re-check menu cleanup whenever app lifecycle or window configuration changes.

## Performance and Architecture Lessons

### Defer and cancel passive work aggressively
Problem pattern: file-existence checks, preview loads, and selection-summary recomputation kept running for intermediate UI states that were no longer relevant.

What we learned: passive detail work should be cancelable and should only finish for the final state the user actually lands on.

Preferred rule: background detail work tied to selection should always be cancelable, keyed by stable identity, and discarded if the user has already moved on.

### Watch-folder scanning must be incremental
Problem pattern: rescanning the full watched directory on every filesystem event led to unnecessary work and repeated attempts against already-seen PDFs.

What we learned: file watching is only cheap if change detection is cheap.

Preferred rule: watch folders should track known file snapshots and only surface newly added or changed PDFs into the import pipeline.

### Coalesce broad UI refreshes before optimizing lower-level code
Problem pattern: multiple overlapping `onChange` paths could trigger repeated list recomputation and make the UI feel heavier than the raw data size justified.

What we learned: eliminating duplicate refresh waves often helps more than micro-optimizing the actual sort or render functions.

Preferred rule: when many related inputs can change together, schedule one coalesced refresh instead of recomputing on every individual signal.

## Testing Lessons

### Large stress tests should not destabilize the normal suite
Problem pattern: a 10,000-document import test was valuable for stress coverage but too heavy for the default XCTest run.

What we learned: there is a real difference between a regression test and a stress test, and the test suite should model that difference explicitly.

Preferred rule: keep a stable default test at a realistic lower scale, and gate heavyweight stress scenarios behind an explicit opt-in environment variable.

### App startup behavior can leak into tests
Problem pattern: auto-restoring the last library during XCTest startup created failures unrelated to the test body itself.

What we learned: host-app lifecycle behavior can contaminate tests unless it is deliberately isolated.

Preferred rule: XCTest runs should skip startup behaviors that depend on persisted user state unless the test is explicitly about that behavior.
