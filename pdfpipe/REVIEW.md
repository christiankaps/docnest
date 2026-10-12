# PdfPipe architecture review

- Reviewed: 2026-10-12
- Baseline: `ea80f78`
- Scope: file structure, filenames, type names, dependencies, and dead code.

These findings are recommendations, not accepted implementation decisions. No architecture refactor was made as part of this review.

## Overall assessment

The architecture is appropriate for the current MVP. The app, share extension, shared implementation, and test roots have clear ownership. Shared sources let both entry points use the same processing and document workbench. The project uses Apple frameworks without third-party runtime dependencies; the target dependency graph has no cycle.

The main improvement is tighter session-state ownership. A broad restructuring or additional framework target is not justified by the current project size.

## Findings

### 1. Session state depends on several independently writable properties

**Priority: Medium — maintainability risk, not a demonstrated functional defect.**

[DocumentSessionModel.swift](Shared/DocumentSessionModel.swift) exposes mutable properties including `busy`, `processed`, `awaitingNaming`, `savedName`, and `document`. [WorkbenchView.swift](Shared/WorkbenchView.swift) combines these properties to select content, navigation titles, and actions. Every transition must keep their combinations consistent.

**Recommendation:** Consider a single workflow-state enum with explicit transitions. Restrict externally writable state where bindings do not require mutation, while retaining separate user-editable naming inputs. Make this a focused follow-up with transition and cancellation coverage.

### 2. The session model depends directly on configuration persistence

**Priority: Low.**

`DocumentSessionModel` receives `PipelineStore` during import to read configuration and its loading error. This couples document-session orchestration to the persistence-backed observable store even though the session does not edit saved configuration.

**Recommendation:** Pass the configuration snapshot and loading outcome needed for import/default selection. Preserve validation and error behavior. A protocol hierarchy or dependency-injection framework is unnecessary for this change.

### 3. `ProcessedDocument` describes more than processed output

**Priority: Low.**

[DocumentEngine.swift](Shared/DocumentEngine.swift) returns `ProcessedDocument` from initial import preparation, naming preview, and final processing. The name suggests processing has finished even when the workbench is still reviewing an imported document.

**Recommendation:** Rename the type to `SessionDocument` or another name covering all of these stages. Keep `PreparedRun` distinct because it represents an intermediate processing run awaiting final naming.

### 4. Most filenames are clear; `SystemViews.swift` is overly generic

**Priority: Low.**

[SystemViews.swift](Shared/SystemViews.swift) contains the PDF preview and native export/share adapters. Its filename conveys less ownership than the other source filenames.

**Recommendation:** Consider `DocumentSystemViews.swift`. Keeping these small related adapters together is reasonable; one file per type is not required. Other multi-type files, such as `Pipeline.swift` and `DocumentAnalysis.swift`, group related concepts coherently.

### 5. The existing file structure should remain proportionate to project size

**Assessment: Keep the current roots.**

`PdfPipe/`, `ShareExtension/`, `Shared/`, `PdfPipeTests/`, and `PdfPipeUITests/` reflect target ownership. `Shared/` mixes models, processing, storage, and UI, but its current size remains manageable.

**Recommendation:** Keep the current layout. If navigation becomes difficult as the project grows, group shared sources by Domain, Processing, Storage, and UI. Preserve target membership through `project.yml` and regeneration rather than editing the generated Xcode project.

### 6. Confirmed unused items and test-only APIs

**Priority: Low.**

- [BrandIcon.imageset](PdfPipe/Assets.xcassets/BrandIcon.imageset/Contents.json) has no references in the current implementation. It is distinct from the active AppIcon asset family.
- `DocumentDate.candidates` in [DocumentAnalysis.swift](Shared/DocumentAnalysis.swift) has no callers. The workbench directly pattern-matches the associated candidates in `.ambiguous`.
- `DocumentEngine.process` is called by unit tests. It is a convenience wrapper around `prepareRun` and `finishRun`, not dead code. The production session uses those stages separately to support naming review.

**Recommendation:** Remove the unused branding asset and candidates accessor in a small cleanup. Retain the test-used processing wrapper unless deliberately moving that convenience into test helpers.

## Evidence and limits

The review inspected source ownership, target declarations in `project.yml`, imports, workflow state, and repository references. Reference searches distinguish confirmed unused items from test-used APIs and framework entry points; they are not a formal whole-program dead-code analysis.

At the reviewed baseline, `make verify` passed on a fresh iOS 27 simulator: 43 unit tests, five UI tests, static analysis, and an optimized unsigned device Release build. These checks establish the existing baseline; they do not validate the proposed refactors or physical-device provider behavior.
