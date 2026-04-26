# DocNest Requirements

## 1. Product Goal

DocNest is a native macOS app for managing personal and professional documents, with a PDF-first focus. The app combines three core ideas:

1. A local document library managed as one coherent library, similar to Apple Photos.
2. An intuitive labeling system for fast organization, filtering, and retrieval.
3. Direct filesystem fallback access so documents can still be viewed or backed up outside the app.

The app should feel local, fast, and trustworthy. Cloud features are optional future extensions and are not part of the first release.

## 2. Product Principles

### 2.1 Local Data Ownership
- All original documents are stored locally in a user-controlled library.
- The app does not hide files in proprietary, inaccessible databases.
- Metadata may be managed internally, but raw files must remain discoverable in the filesystem.

### 2.2 PDF-First, Document-Centric
- PDFs have priority in import, preview, search, and metadata editing.
- Other formats may follow later but must not complicate v1.

### 2.3 Organizing Without Folder Lock-In
- Labels are the primary organization system.
- Physical folder structure exists for robustness and internal management, not business-level organization.

### 2.4 Native macOS Experience
- The app feels like a real Mac app: fast, filesystem-aware, drag-and-drop capable, with strong keyboard support and native dialogs.
- The app supports native macOS fullscreen mode.
- The app adapts consistently to Light and Dark appearance.

## 3. Target Users

### 3.1 Primary User Groups
- Individuals with many PDFs: invoices, contracts, tax records, manuals, scans.
- Freelancers or small teams with local document collections.
- Users who want structured document management without rigid folder hierarchies.

### 3.2 Typical Use Cases
- Import an invoice, assign labels, and find it later via search.
- Tag a contract by customer, year, and status.
- Collect scanned paperwork centrally and make it searchable.
- Open or export documents outside the app via Finder.

## 4. Scope and Boundaries

### 4.1 In Scope for v1
- Create, open, and close local libraries.
- Import PDFs.
- View and manage documents.
- Create, assign, remove, and rename labels.
- Search and filter documents by metadata and labels.
- Finder access to original files.
- Fullscreen support and Light/Dark appearance support.
- Solid metadata persistence and consistency checks.

### 4.2 Explicitly Out of Scope for v1
- iCloud sync or multi-device sync.
- Collaboration and multi-user support.
- Automatic ML/AI classification.
- Full document editing.
- Mobile apps.

## 5. Core Terms

### 5.1 Library
A user-selected package or directory containing original documents, preview data, and metadata.

### 5.2 Document
An imported item with original file, stable internal ID, technical metadata, and user-defined information.

### 5.3 Label
A freely defined category that can be assigned to one or more documents.

### 5.4 Smart Folder
A saved label combination that appears as a virtual folder in the sidebar, for example "Invoices" or "Tax Documents". Smart folders store only label collections, not search queries.

### 5.5 Label Group
An optional organizational container for labels in the sidebar. Label groups let users cluster related labels (e.g. a "Finance" group containing "Invoices", "Tax", "Receipts"). Groups are purely a sidebar display concept — they do not affect label filtering, smart folder matching, or document queries.

### 5.6 Watch Folder
A user-configured directory on the local filesystem that the app monitors for new PDF files. When new PDFs appear in a watch folder, they are automatically imported into the library. Each watch folder can optionally auto-assign a set of labels to imported documents. Watch folders are a library-level setting managed from the app menu bar, not displayed in the sidebar.

## 6. Functional Requirements

### 6.1 Library Management

#### Must
- User can create a new library.
- User can open an existing library.
- App remembers the last successfully opened library and tries to reopen it automatically on next launch.
- App must not automatically reopen a remembered library when that library has been moved to Trash. In that case the remembered library reference is cleared or ignored and the app starts in its normal no-library state.
- If no last-opened library is known, or the stored library can no longer be validated, the app must not show a modal popup. Instead, it shows a welcome state directly in normal window content with actions to open or create a library.
- The save dialog for library creation shows only the library name without the internal extension (.docnestlibrary); the app appends the extension automatically.
- App validates structure and metadata consistency when opening a library.
- App presents understandable error states if a library is damaged or incomplete.
- The active metadata store is library-local and, for v1, stored at Metadata/library.sqlite.

#### Must (App Lifecycle)
- Only one instance of the app may run at a time. If a second instance is launched, it activates the existing instance and terminates itself.

#### Should
- Library is treated as a macOS package (UTExportedTypeDeclarations with com.apple.package conformance), appearing as a single file in Finder and app file dialogs.
- The .docnestlibrary package uses a dedicated file icon in Finder and in macOS open/save panels.
- App provides a "Show in Finder" action for libraries and individual documents.
- The library manifest includes a format version number. When opening a library created by an older app version, the app detects the version mismatch and runs any necessary migration steps before loading the library. After migration, the manifest is updated to the current version.
- The SwiftData schema uses `VersionedSchema` and `SchemaMigrationPlan` to manage database evolution across app versions. Each schema version is captured as a full model snapshot. The `ModelContainer` is opened with the migration plan so that older databases are migrated forward automatically. Lightweight migrations (new columns with defaults) use `MigrationStage.lightweight`; breaking changes use `MigrationStage.custom`.
- Release builds bake the marketing version and build number into the app bundle, and the app surfaces that information in About/App Info UI.

### 6.2 Document Import

#### Must
- PDFs can be imported via file dialog, drag-and-drop, and paste (Command+V).
- Folders can be dropped or pasted onto the document list; all PDFs inside (including nested subfolders) are imported recursively.
- Pasting a web URL (http/https) to a PDF downloads the file directly into the library without leaving a copy in the Downloads folder. The filename is derived from the URL path or Content-Disposition header.
- Import captures file hash, filename, creation date, import timestamp, and page count.
- Documents receive a stable internal ID.
- Duplicate detection is required, at least hash-based.
- User sees summary counts for imported, skipped, and failed files.
- User receives clear feedback when files fail in batch import.
- Labels currently active as filters are automatically assigned to newly imported documents so they appear immediately in the filtered view.
- Import runs in the background with a progress indicator (spinner and file counter) shown next to the search bar.
- User can cancel an in-progress import; already-imported files are kept.
- PDFs and folders can be imported by dropping them onto the app's dock icon. URLs received before a library is loaded are queued and processed once the library becomes available.
- The app registers as a macOS Services provider ("Import into DocNest") for PDFs and folders, allowing import from Finder's Services and Share menus.
- The import pipeline must reject self-import attempts. If the open library package itself, one of its internal folders, or a watched folder that resolves into the active library package is selected as import source, the app must skip that source and explain why.

#### Must (Storage Naming)
- Stored files inside the library package use the document title as filename (sanitized for filesystem safety), not a random UUID.
- On naming collision within the same storage directory, a short content-hash suffix is appended (e.g. `Invoice March 2026 (a1b2c3d4).pdf`).
- When a document is renamed in the app (inspector or inline rename), the stored file is renamed to match the new title. The stored-file path in the database is updated accordingly.

#### Should
- Batch import of multiple files.
- Optional copy-into-library instead of external reference; for v1, copy into library is recommended.

#### Decision for Current Implementation
- Hash-based duplicates are skipped in v1 and counted in import status.
- Import and export summary messages show only counts (no individual filenames) and appear as an auto-dismissing toast overlay at the bottom of the window. Toasts disappear after 5 seconds or on click.

#### Drag-and-Drop Requirements for v1
- Drag-and-drop uses the same import pipeline as the file dialog; validation, duplicate handling, file copy, and feedback are identical.
- While a library is open, PDFs and folders can be dropped onto the main window from Finder or other apps via file URLs.
- Main content shows a clear visual drop zone during valid drag operations; invalid content is not shown as acceptable.
- Multiple PDFs and folders can be imported in one drop. Folders are scanned recursively for PDFs.
- Non-PDF files in a drop are not imported in v1 and are reported as skipped or failed.
- A drop without an open library must not trigger a silent import attempt; the app must explain library state instead.
- Drop behavior applies to the document list and the empty-library state; users must not need to hit a tiny target.

#### Explicit Boundary for v1
- Finder file URLs and normal file drops are in scope for v1.
- Advanced drag sources such as file promises, mail attachments without local file URLs, or external providers requiring async materialization are out of scope.

### 6.3 Document Presentation

#### Must
- List view with sortable columns.
- When left sidebar and right inspector are visible, both panels must remain fully visible; the app must not partially clip visible panel content.
- When the window narrows, the center document list shrinks first; side panels retain fully usable widths while visible.
- User can resize visible file-list columns directly via drag gesture.
- User can toggle file-list attributes (Imported, Created, Pages, File Size, Labels). The Document column remains always visible.
- The Document column uses a fixed minimum width that is large enough for approximately 30 characters.
- Column headers are always single-line and stay aligned with row content.
- Optional file-list columns auto-hide in tight layouts (in a deterministic order) before violating panel or Document-column constraints.
- Left and right side panels use fixed, non-overlay layout behavior in open-library mode.
- The left sidebar is not toggleable in open-library mode.
- File list uses clear row separation with alternating row colors (even/odd) for readability at scale.
- Metadata detail view.
- PDF preview for selected document.
- Finder integration: open original file, show in Finder, export.
- Export copies original stored PDFs as-is with descriptive filenames.
- Export filename format: `Title - Label1, Label2.pdf`. Labels are sorted by user-defined sort order. When a document has no labels, the filename is just `Title.pdf`.
- Single-document export uses NSSavePanel with suggested filename. User can change name and destination.
- Multi-document export uses NSOpenPanel in folder-selection mode. All documents are exported into the chosen folder with suggested filenames.
- Filenames are sanitized for filesystem safety: forward slash, colon, and backslash are replaced with underscore.
- Bulk export handles name collisions by appending ` (2)`, ` (3)`, etc. Both in-batch duplicates and existing files in the target folder are considered.
- Documents without stored files are silently skipped during bulk export. An export summary reports skipped and failed counts.
- Export is accessible via document context menu (right-click) and via the File menu bar.
- Keyboard shortcut for export: Shift+Command+E.
- Dragging a document from the list to Finder or Desktop exports the file with the suggested filename. The drag provides both the PDF file (for external apps) and the internal payload (for in-app operations like label assignment and bin).

- The document list supports two presentation modes: list and thumbnails. In thumbnail mode, documents appear as thumbnail tiles similar to Finder icon view. Thumbnail size is continuously adjustable via slider.
- Thumbnail tiles display label color dot badges overlaid on the bottom-right corner of the thumbnail image (up to 4 dots with "+N" overflow) and a mini label bar beneath the title showing compact label chips (up to 2 chips with "+N" overflow).
- Switching between list and thumbnail mode uses a segmented control in the top toolbar.
- Toggling optional file-list attributes in list mode is done through right-click context menu in the list, not a separate header button.
- Toolbar includes a Share button that opens native macOS share sheet for the selected document(s). Printing is reachable via share sheet.
- Right-clicking a document opens a context menu with quick actions: assign labels, show in Finder, move to Bin, and other context actions.
- In the list, each label badge shows an "x" on hover; clicking it removes the label immediately without confirmation dialog.
- The right inspector is a collapsible details column. It is toggleable from the toolbar and via the keyboard shortcut `Control-D`.
- Document rename is available inline in both list and thumbnail modes, from the document context menu, and by Finder-like interaction on the currently selected document name.

#### Should
- Quick Look-like preview behavior.
- Split view behavior with list on the left and preview on the right.

### 6.4 Labels

#### Must
- User can create, rename, and delete labels.
- A document can have multiple labels.
- Labels can be assigned quickly via keyboard or direct actions.
- Filtering by one or more labels is supported.
- Left sidebar shows document count for each label, scoped to the currently selected library section and active label filters.
- Dragging a label from sidebar onto a document assigns that label to the document.
- Dragging one or more documents onto a label in the sidebar assigns the label to those documents. Single-file drops are assigned immediately without confirmation. Multi-file drops show a native confirmation dialog with the count of documents that will be newly assigned and the count already having the label; already-assigned documents are always skipped.
- If multiple labels are selected as filters, logic is AND: only documents with all selected labels are shown.
- Deleting a label must never delete documents; it only removes label associations.
- If a label is assigned to one or more documents, app shows a native confirmation dialog before deletion with the affected document count. Labels with no assignments can be deleted without extra confirmation.
- Label management (create, rename, delete, color selection) is integrated directly in left sidebar, not in a separate modal dialog.
- Label order in sidebar is user-reorderable via drag-and-drop and persisted.
- Full label management is available from `DocNest > Settings… > Labels`. The sidebar remains the quick-access surface for filtering, selection, creation shortcuts, and drag-and-drop organization.

#### Should
- Colored labels.
- Optional emoji icon per label. When set, the emoji replaces the colored circle in sidebar rows, drag previews, and label chips. Users choose an emoji via the system Character Palette (emoji keyboard).
- Label suggestions based on recently used labels.

#### Must (Label Groups)
- User can create, rename, and delete label groups.
- Labels can be assigned to a group via the label editor sheet or by dragging onto a group header.
- Grouped labels appear under a collapsible group header in the sidebar, indented beneath the group name.
- Ungrouped labels appear at the top level before any groups.
- Deleting a group does not delete its labels; they become ungrouped.
- Group order is reorderable via drag-and-drop in sidebar and persisted.

#### May Follow Later
- Rules such as "if filename contains X, suggest label Y".

### 6.5 Search and Filter

#### Must
- Search across filename, title, and labels.
- Combination of text search and label filters.
- Library buckets in sidebar show counts for All Documents, Recent Imports, and Needs Labels.
- Sidebar also includes a Bin bucket with count of currently deleted documents.
- Documents in Bin are ignored by normal search and label filters; they appear only in Bin bucket.
- Documents can be dragged from list directly onto Bin symbol in sidebar.
- Delete key moves selected documents to Bin; when selected documents are already in Bin, Delete performs permanent removal.
- When label filters are enabled or disabled, sidebar selection highlight must update immediately, even if document list refresh takes slightly longer.
- Sorting by import date, document date, name, and file size.
- Needs Labels filter shows only documents without labels. When active, active label filters are automatically cleared to avoid logical conflict.
- Keyboard navigation through the document list must follow the currently visible sort and grouping order, not a separate hidden order.

#### Should
- Saved smart folders (label-only collections shown in sidebar).
- Faceted filters by year, label, file type, duplicate status.

#### v1 Assumption
- For PDFs with extractable text, embedded text is indexed.
- For scanned or image-based PDFs, Vision framework OCR extracts text using VNRecognizeTextRequest with accurate recognition level. Pages with embedded text use the fast PDFKit path; pages without embedded text are rendered at 300 DPI and processed through OCR. Pages are processed sequentially to manage memory.
- OCR runs during import (new documents are fully extracted before the import completes) and as a background backfill on app launch for documents not yet processed.
- A toolbar progress indicator shows OCR backfill progress (document count and cancel button) next to the search bar.
- Each document tracks an `ocrCompleted` flag to prevent infinite retry on genuinely blank documents.
- Users can manually trigger re-extraction via "Re-extract Text" in the document context menu or the inspector's Text Extraction section.
- The inspector shows per-document OCR status: extracted character count, "No text found", "Legacy extraction (no OCR)", or "Pending extraction".

### 6.6 Metadata Editing

#### Must
- User can edit title, document date, and labels.
- Technical metadata remains traceable even when title changes.

#### Should
- Custom fields can be prepared as later extension but are not required in v1.

### 6.9 Document Date

The Document Date represents the semantic content date of a document (e.g. the invoice date printed on an invoice, the signing date of a contract, the date printed in a letter). This is distinct from the file system creation date and the import timestamp.

#### Must

**Attribute and Data Model**
- Every document has an optional `documentDate: Date?` field stored in the metadata database.
- The field is separate from `importedAt` (set at import time, immutable) and from the file system creation date.
- The data model field is named `documentDate` and was renamed from `sourceCreatedAt` in schema V4; the SwiftData migration is lightweight using `@Attribute(.originalName("sourceCreatedAt"))`.

**Date Extraction on Import**
- During import, after OCR text extraction completes, the app attempts to extract a document date from the extracted text using `DocumentDateExtractor`.
- `DocumentDateExtractor` recognises common English and German date formats:
  - ISO 8601: `2024-03-15`
  - English long form: `March 15, 2024` and `15 March 2024`
  - English abbreviated: `Mar 15, 2024` and `15 Mar 2024`
  - German long form: `15. März 2024`
  - German abbreviated: `15. Mär. 2024`
  - European numeric: `15.03.2024`
  - US numeric: `03/15/2024`
- The first plausible date found in the document text is used as the `documentDate`. Plausible means between 1 January 1900 and 10 years in the future.
- If no date is found in the text, the file system creation date (captured at import) is used as the fallback.
- If neither source yields a date, `documentDate` is left as `nil`.

**Details View Editing**
- The document inspector shows the Document Date as a graphical (calendar-style) date picker for the selected document.
- The date picker uses macOS `.graphical` style, showing a mini month calendar widget directly in the inspector panel.
- Changes to the date picker are saved immediately to the database without a separate Save button.
- A clear button (×) next to the section header allows removing the document date, setting it back to `nil`.
- When the document date is `nil`, the calendar is shown with today pre-selected; a hint text below the picker explains that no date is set.

**Document List Column**
- The document list includes a "Doc. Date" column (previously labelled "Created") that shows `documentDate`.
- The column is sortable; documents without a date sort before dated documents when sorted ascending, and after when sorted descending.
- The column can be toggled on or off via the list context menu, like other optional columns.

**Grouping in the Document List**
- The document list supports grouping by Document Date, selectable via the list context menu under "Group By":
  - **None** (default): no grouping, flat list as before.
  - **Year**: documents grouped by the year of their Document Date; labelled `2024`, `2023`, etc.
  - **Year & Month**: sub-grouped by year and month; labelled `March 2024`, `February 2024`, etc. (using the current system locale for month names).
  - **Year & Calendar Week**: sub-grouped by year and ISO calendar week; labelled `2024 · Week 12`, etc.
- Within each group, documents follow the active sort order.
- Documents without a Document Date are collected in a "No Date" group, always shown last.
- Group headers are pinned (sticky) at the top of the scroll area while scrolling through a group.
- Each group header shows the group label and the document count for that group.
- The selected grouping mode is persisted across app launches via `@AppStorage`.
- Grouping applies to both list mode and thumbnail mode.

#### Should
- Date extraction confidence could be improved over time by extending `DocumentDateExtractor` with additional locale patterns or contextual heuristics (e.g. prefer dates appearing near keywords like "Invoice Date:", "Datum:", "Date:").
- A "Re-extract date" action in the context menu or inspector could re-run `DocumentDateExtractor` on the stored full text for documents whose date was set from the file creation date fallback.

### 6.7 Data Integrity and Recovery

#### Must
- App must not silently lose or overwrite original files.
- Deleting a document first moves it to Bin instead of immediate permanent deletion.
- Bin provides Restore All and single-document restore.
- Bin provides Remove All for permanent removal of all currently binned documents.
- If a document is already in Bin, deleting it means permanent removal from library.
- App can detect missing files or inconsistent metadata.
- Library open and maintenance flows include integrity reporting and conservative self-healing for repairable package or metadata issues. Repairs must be recorded in diagnostics output instead of happening silently.

#### Should
- Repair or reindex functionality for a library.
- Import and metadata changes should be transactional or crash-robust.

### 6.8 Watch Folders

#### Must
- User can add, edit, pause/resume, and delete watch folders from `DocNest > Settings… > Watch Folders` and via `Command-,`.
- Each watch folder points to a local directory and monitors it for new PDF files using `DispatchSource.makeFileSystemObjectSource` with `O_EVTONLY` file descriptors.
- When new PDFs appear in a watched directory, they are automatically imported through the standard import pipeline (same hash-based deduplication, file storage, and metadata capture).
- Each watch folder can optionally auto-assign a set of labels to imported documents.
- Watch folders can be individually enabled or disabled (paused). Disabled watch folders stop filesystem monitoring.
- The settings sheet shows each watch folder's status: monitoring (green), paused, or path not found (warning).
- Watch folder monitoring performs an initial scan on startup to catch files added while the app was closed.
- Monitoring is shallow (top-level directory only), filtering for `.pdf` file extension.
- Watch folder monitoring starts automatically when a library is opened and tears down when the library is closed or the app exits.
- Watch folder scanning must be incremental. Repeated filesystem events must not cause the app to rescan and reattempt import for every already-seen PDF in the watched folder.
- Watch folders must not re-import the active DocNest library package or its internal contents.

#### Should
- Context menu on each watch folder row offers Edit, Pause/Resume, Reveal in Finder, and Delete.

## 7. Non-Functional Requirements

### 7.1 Platform
- Native macOS app in Xcode.
- Recommended stack for first version: Swift, SwiftUI, PDFKit, Core Data or SwiftData, Spotlight or custom search index depending on feasibility.
- Project must remain reproducible and traceable in versioned Xcode project definition in repository.

### 7.2 Performance
- Library with at least 20,000 documents should remain usable.
- List filtering and label filtering should feel instant for typical user interactions.
- Preview of an average PDF should appear without noticeable delay.
- Selection highlight and keyboard navigation in the document list must update immediately, even when preview rendering, file-availability checks, OCR status updates, or multi-selection summary work are still catching up.
- Heavy inspector work must be deferred or cancellable so passive detail rendering does not block visible row selection feedback.
- Grouped document lists must preserve visible-order navigation and refresh correctly when document metadata changes move an item between groups.

### 7.3 Robustness
- Library consistency has higher priority than aggressive optimization.
- Metadata database and file inventory must be regularly cross-validatable.

### 7.4 Usability
- Core actions must be reachable without deep navigation.
- Drag-and-drop, multi-select, and keyboard control are important.
- App should be understandable for simple cases without onboarding.

### 7.5 Appearance and Window Behavior
- App must remain fully usable in native macOS fullscreen mode.
- All central views must be visually consistent and readable in Light and Dark mode.
- Colors for labels, selections, separators, and preview containers must have sufficient contrast in both appearances.
- Custom colors or backgrounds must not break system appearance behavior.
- The app window toolbar includes an Appearance button to switch between System, Light, and Dark. Choice is persisted in @AppStorage.
- On startup, the default appearance mode is System.

### 7.6 Privacy
- All data is processed locally.
- Network access is optional and only used for explicit update-check functionality against the project's GitHub releases.
- Update checks must request fresh GitHub release metadata and tolerate a short delay between a release becoming latest and its DMG installer asset being attached.
- User must be able to understand where files are stored and what happens during import.

### 7.7 Engineering Workflow and Code Quality
- Every code change must be reviewed by an AI reviewer using a different model than the implementing agent.
- The first review pass should use a fast model.
- If the fast reviewer reports no findings, a second review pass must be run with a stronger but slower model.
- Existing review agents should be reused when practical instead of spawning fresh reviewers for every pass.
- If any review finds issues, those issues must be fixed and the review sequence repeated until all review passes report no further issues.
- New features and bug fixes must include tests unless there is no practical way to cover the behavior.
- After all review passes are clean, the full test suite must pass before the change is considered complete.
- A commit may be created only after the required reviews are clean and the full test run passes.
- If a new feature is implemented or app behavior changes, the requirements documentation must be updated in the same change.
- Swift code should remain clear, easy to follow, and aligned with existing project structure and patterns.
- Important types, methods, properties, invariants, concurrency assumptions, filesystem assumptions, and non-obvious workflows must be documented in code.
- Dependencies must be kept minimal. New libraries should be added only when clearly justified and when the standard library, Apple frameworks, or existing project code are not sufficient.

## 8. Library Structure

For the first version, a filesystem-friendly structure is preferred that is technically robust and readable for users in emergency situations.

### 8.1 Recommended Form
- One library as package, for example My Documents.docnestlibrary.
- Inside the package: clear directories instead of binary monoliths.
- The library manifest (library.json) carries a `formatVersion` integer. New libraries are stamped with the current version. On open, the app compares the manifest version against its own current version and applies sequential migrations when needed.

### 8.2 Example Structure

```text
My Documents.docnestlibrary/
  Metadata/
    library.json
    library.sqlite
    search-index/
  Originals/
    2026/
      03/
      
        <document-id>.pdf
  Previews/
    <document-id>.jpg
  Attachments/
  Diagnostics/
    import-log.json
```

### 8.3 Design Decision
- Business-level organization is handled by metadata and labels, not Finder folders.
- Physical subfolders exist only for scaling, stability, and debuggability.
- Original files should remain accessible without the app.

## 9. High-Level Data Model

### 9.1 Document Entity
- id
- originalFileName
- storedFilePath
- contentHash
- title
- documentDate (optional; semantic content date extracted from OCR text or falling back to file creation date; user-editable; stored as `documentDate`, formerly `sourceCreatedAt`)
- importedAt
- pageCount
- fileSize
- fullText (extracted PDF text including OCR)
- ocrCompleted (whether OCR extraction has been attempted)
- isDeleted or status field if soft delete is used

### 9.2 Label Entity
- id
- name
- color
- icon (optional emoji)
- groupID (optional reference to Label Group)
- sortOrder
- createdAt

### 9.3 Relation
- Many-to-many between documents and labels.

### 9.4 Smart Folder Entity
- id
- name
- icon (optional emoji)
- labelIDs (array of label UUIDs)
- sortOrder

### 9.5 Label Group Entity
- id
- name
- sortOrder

### 9.6 Watch Folder Entity
- id
- name
- icon (optional emoji)
- folderPath (absolute filesystem path, stored as String)
- isEnabled (defaults to true)
- labelIDs (array of label UUIDs for auto-assignment)
- sortOrder

### 9.7 Optional Later Entities
- CustomFieldDefinition
- ImportJob
- AuditEvent

## 10. UX Requirements

### 10.1 Information Architecture
- Sidebar for library, smart folders, and labels. Watch folders are a library-level setting and are not shown in the sidebar; they are managed via `DocNest > Settings… > Watch Folders`.
- Main area for document list.
- Detail/preview area for selected document.
- Layout must scale meaningfully in normal window mode and fullscreen.
- Three-panel layout (sidebar, document list, inspector) must be fully visible immediately after app launch. No panel may start hidden, collapsed, or partially visible.
- Left sidebar is permanently visible in open-library mode and is not toggleable.
- The app uses a modern, readable system typography style (SF Pro or SF Pro Rounded). Typography, spacing, and visual hierarchy should feel modern and clean.

### 10.2 Core Interactions
- Drag files onto window to import.
- Select a document in list and instantly see clear selection feedback; preview and inspector content may update asynchronously but must not delay the visible selection change.
- Assign labels via shortcuts or inspector.
- Command+L opens a quick label picker overlay for fast keyboard-driven label assignment to selected documents.
- Live filter result list while typing.
- Command+F focuses search field in document view when a library is open.

### 10.4 Drag-and-Drop UX
- During valid PDF drop, active drop zone is immediately recognizable.
- Visual feedback must not unnecessarily obscure list or inspector content.
- After successful drop, user remains in current window context; import must not open a new library or window.
- After completed drop, user sees the same import summary as with file dialog.

### 10.5 Startup State Without Library
- On launch without an open library, app shows no modal dialog and no popup.
- Instead, regular three-panel layout is shown with empty content.
- Main content area shows welcoming view with actions to create or open a library, embedded in normal window flow.
- Sidebar and inspector remain visible but empty or with placeholder content.

### 10.6 Settings-Based Label Management
- Full label management lives in `DocNest > Settings… > Labels`, not in an older standalone modal dialog.
- The sidebar "+" button creates new labels directly. Group creation has its own dedicated button.
- Label create and edit use a dedicated editor sheet (not inline editing). The sheet provides a spacious name field with emoji picker, a visual color swatch grid, and a group picker.
- Editing a label (double-click or context menu "Edit") opens the same editor sheet pre-filled with the label's current values.
- Label groups appear as collapsible sections in the sidebar with disclosure chevron, group name, and label count. Groups can be renamed inline, deleted, or have labels added via context menu.
- Labels can be dragged onto a group header to move them into that group.
- Ungrouped labels appear above groups; grouped labels appear indented under their group header.
- Label order is reorderable via drag-and-drop in sidebar (drag label onto another label). Custom order is persisted.
- Label drop targets show a visual hover highlight (accent color tint) during document drags.
- Technical constraint: label rows must not use SwiftUI List `.onMove`, as this activates the List drop engine which intercepts all row-level drop events. Reordering is implemented via the row `.onDrop` handler by detecting label-type payloads.
- Label filters use AND logic for multi-selection.

### 10.7 Automatic Label Assignment During Import
- If label filters are active during import, those labels are automatically assigned to newly imported documents.
- Imported documents then appear immediately in current filtered view.
- Import summary indicates which labels were assigned automatically.

### 10.3 Critical UX Rules
- User must always be able to tell whether they are changing original document, metadata, or only view state.
- Destructive actions require clear wording and undo where feasible.
- Light and Dark mode must not only function technically but also be visually coherent for lists, sidebars, PDF preview, and label rendering.
- Menu bar entries should show only actions actually supported by current product; generic document-template commands like new document, save, import, export, or print are hidden in v1 while matching workflows are not provided.
- Primary click targets in document rows and sidebar rows must favor reliable single-click behavior. Dragging, double-click actions, and contextual editing affordances must not make normal selection feel unreliable.

## 11. Prioritized Implementation Sequence

The sequence should reduce technical risk early and deliver a usable core product quickly.

### Phase 1: Library Foundation
Goal: app can create and open libraries cleanly.

- Set up Xcode project.
- Keep reproducible project and scheme definitions in repository.
- Define app architecture.
- Define library package format.
- Create persistence model for documents and labels.
- Build base for file operations and consistency checks.

Current state:
- Library manifest includes a `formatVersion` field. New libraries are created with the current format version.
- On open, the app validates the library structure and decodes the manifest. If the manifest version is older than the app's current version, sequential migration steps are applied and the manifest is rewritten.
- SwiftData schema versioning is implemented via `DocNestSchemaV1`, `DocNestSchemaV2`, `DocNestSchemaV3`, and `DocNestMigrationPlan` in `DocNestSchemaVersioning.swift`. The `ModelContainer` is opened with the migration plan. V1→V2 is a lightweight migration (adds `ocrCompleted: Bool` to `DocumentRecord`). V2→V3 is a lightweight migration (adds `WatchFolder` entity).

### Phase 2: Import Pipeline
Goal: PDFs are imported robustly into library.

- Single and multi-file import.
- File hashing and duplicate detection.
- Copy into Originals.
- Metadata capture during import.
- Error handling and import status.
- Hook drag-and-drop into existing import pipeline.

Current state:
- Import stores filename, file size, file creation date, page count, import timestamp, and content hash in document model.
- Hash-based duplicates are skipped and explicitly reported in import status.
- File-dialog import and drag-and-drop use same import path and same feedback model.
- Document list acts as generous drop zone; with closed library, app explains missing import context instead of silently failing.
- Active label filters are automatically assigned to newly imported documents.
- Dropped folders are recursively scanned for PDFs; all found PDFs are imported through the standard pipeline.
- Import runs in the background with a progress indicator (spinner + counter) next to the search bar. User can cancel mid-import.
- Drag-and-drop uses a DropDelegate with explicit UTType.fileURL matching to avoid conflicts with label drag-and-drop on document rows.
- Paste (Command+V) reads file URLs from the system pasteboard and routes them through the same import pipeline. Folders pasted from Finder are recursively scanned for PDFs.
- Pasting a web URL (http/https) downloads the PDF to a temporary location, imports it into the library, and deletes the temp file. No copy is left in the Downloads folder. Filename is derived from URL path or Content-Disposition header. Download failures are reported in the import summary.
- Stored files use the document title as filename (sanitized), with a short content-hash suffix on collision. Renaming a document in the app renames the stored file to match.
- PDFs and folders dropped onto the dock icon are routed through `onOpenURL` into the import pipeline. URLs arriving before a library is loaded are queued in `LibrarySessionController.pendingImportURLs` and drained once the library becomes available.
- App registers as a macOS Services provider via `NSServices` in Info.plist. `ServicesProvider` handles the `importFiles` message by reading file URLs from the pasteboard and posting a notification that `AppRootView` observes to queue imports.
- Single-instance enforcement was removed; macOS prevents duplicate app launches natively via the standard app lifecycle.

Implementation plan for drag-and-drop:
1. Add generous drop area in main content, not only on a single child element.
2. Accept drops only for PDFs/file URLs and tie visual activation to valid content.
3. Route drop handler through same import use-case interface as file dialog so there is no second import path.
4. Translate mixed drops (PDFs + invalid files) into one coherent feedback summary.
5. Test empty-library state and document list as drop targets, including multi-drop, duplicates, and failures.
6. Add UI tests for successful and rejected drops once drop mechanics are stable.

### Phase 3: Reading and Viewing
Goal: documents become truly usable in app.

- Document list.
- Sorting.
- PDF preview with PDFKit.
- Metadata detail view.
- Finder actions.

Current state:
- Document list offers sortable columns for title, import date, page count, and file size.
- Document list shows title in one Document column; original filename is visible in inspector and is not duplicated.
- Document list uses denser typography for large libraries and visual label chips instead of plain text.
- Document list supports drag-resizable column widths in header.
- File attributes (except Document) can be shown/hidden via context menu.
- Document list uses alternating row backgrounds for better visual separation.
- Inspector provides Finder actions for original file and library.
- Three-panel layout enforces strict fixed side panels in open-library mode: sidebar width 260, inspector width 420; center list is elastic.
- In open-library mode, the left sidebar is always visible and not toggleable.
- Document column has a fixed minimum width for approximately 30 characters.
- Optional columns auto-hide in tight layouts before panel clipping or Document-column violation can occur.
- Detail view separates PDF preview and metadata with vertical splitter so users can adjust preview height directly.
- Startup view without library is integrated into regular three-panel layout and no longer shown as separate popup dialog.
- Typography is unified into a consistent modern rounded system style.
- Documents can be renamed inline in both list and thumbnail views via context menu "Rename".
- Pressing Space or double-clicking a document opens a native Quick Look preview via QLPreviewPanel, similar to Finder behavior.
- Arrow keys navigate the document list; when Quick Look is open, navigation automatically updates the preview.
- The document list focus ring is suppressed for a cleaner appearance.
- The toolbar Library menu includes "Show in Finder" when a library is open, revealing the library package in Finder.
- The window title shows the open library's name (without file extension) or "DocNest" when no library is open.
- Export supports single-document (NSSavePanel) and multi-document (NSOpenPanel folder picker) workflows.
- Export filenames combine document title and labels sorted by sortOrder, formatted as "Title - Label1, Label2.pdf".
- Export is accessible via document context menu and File menu bar (Shift+Cmd+E).
- Export copies original PDFs as-is with descriptive filenames. Name collisions in bulk export are resolved automatically.
- Dragging a document to Finder or Desktop exports it with the suggested filename via Transferable file representation.
- Thumbnail tiles show label information: colored dot badges (up to 4 with "+N") overlaid on the thumbnail corner inside a dark capsule, and a compact label chip bar (up to 2 with "+N") beneath the document title. Documents with no labels show neither.

### Phase 4: Labels as Primary Organization
Goal: user can organize documents effectively.

- CRUD for labels.
- Assign labels to documents.
- Filter by labels.
- Strong keyboard and multi-select flows.

Current state:
- Labels can be created, renamed, merged, and deleted globally.
- Each label has user-selectable color from fixed palette (10 options). Color is rendered consistently in sidebar, list, and inspector as colored chip.
- Each label supports an optional emoji icon. When set, the emoji replaces the colored circle in sidebar rows, drag previews, and label chips throughout the app.
- Label create and edit use a dedicated editor sheet with spacious name field, emoji picker, visual color swatch grid (LazyVGrid of all 10 color options), and group picker. This replaces the previous inline sidebar form.
- Editing a label (double-click or context menu "Edit") opens the editor sheet pre-filled with the label's current values.
- Document detail view supports direct assignment/removal of existing labels plus create-and-assign of new labels via keyboard or direct action.
- Sidebar supports multi-label filtering. With multiple active labels, list shows only documents containing all selected labels.
- Deleting a label removes only associations. Documents and original files remain unchanged.
- Document list supports multi-selection. Inspector can add/remove labels for entire selection.
- For mixed label states, inspector separates shared labels from partially assigned labels and offers actions such as add to remaining documents.
- Sidebar offers lightweight label actions for filtering, creation, drag-and-drop organization, and contextual editing, while full management lives in Settings.
- Labels are reorderable in sidebar, persisted via sortOrder field.
- Label groups allow organizing labels into collapsible categories in the sidebar (e.g. "Finance" containing "Invoices", "Tax", "Receipts").
- Groups display as collapsible headers with disclosure chevron, group name, and label count. Grouped labels appear indented beneath their group header; ungrouped labels appear at the top level.
- Groups support create, rename (inline), and delete via context menu. Deleting a group makes its labels ungrouped without deleting them.
- Labels can be moved into a group by dragging onto the group header or via the group picker in the label editor sheet.
- Group order is reorderable and persisted via sortOrder field.
- Quick label picker (Cmd+L) provides a floating overlay for fast keyboard-driven label assignment. The picker includes a type-ahead search field that filters labels, arrow key navigation, and Enter to toggle labels on selected documents. Labels show assignment state indicators (checkmark for all, dash for partial). When not filtering, labels display grouped; when typing, the list is flat. The picker only opens when documents are selected and not in Bin.
- The Labels pane in `DocNest > Settings…` provides a two-panel master-detail management view for centralized label and group management. Left panel shows all labels organized by groups with native multi-select (Cmd+Click, Shift+Click). Right panel is context-sensitive: single-label editor, multi-selection bulk actions, create-new-label form, or empty state. Footer has +/- buttons for creating labels/groups and deleting selected items. Edits auto-save on change (color, icon, group) or on Enter (name).

### Phase 5: Search and Retrieval
Goal: users find documents quickly.

- Search across title, filename, labels.
- Optional text index for PDF contents.
- Combinable filters.
- Saved smart folders once Phase 4 is stable.

Current state:
- Main view provides built-in search field for open library.
- Search filters live across title, original filename, label names, and extracted PDF full text.
- Multi-word search is token-based; document remains visible only if all terms are found across searchable metadata and full text.
- Search text and label filters can be combined and operate on the same document list.
- PDF text extraction uses a two-tier approach: PDFKit for pages with embedded text (fast path) and Vision framework OCR for scanned/image pages (fallback). Text is extracted during import and stored in the document model. Existing documents without extracted text are backfilled on app launch with a toolbar progress indicator. Users can manually re-extract text via context menu or inspector.
- Smart folders are implemented as saved label collections persisted via SwiftData.
- Smart folders appear in their own sidebar section between Library and Labels, with create (+), edit, delete, and drag-to-reorder.
- Selecting a smart folder highlights the corresponding labels in the sidebar and shows only documents matching all of the folder's labels.
- Clicking a selected smart folder deselects it, returning to All Documents with all filters cleared.
- Label filter clicks while a smart folder is selected transition to interactive filtering: the filter is seeded with the folder's labels, then the clicked label is toggled. If the resulting combination matches another smart folder, that folder highlights automatically.
- When interactive label filters exactly match a smart folder's labels, that folder is highlighted in the sidebar.
- Creating a smart folder pre-fills from the currently active label filters.
- Dragging documents onto a smart folder row assigns the folder's labels to those documents.
- Importing files while a smart folder is selected auto-assigns the folder's labels to imported documents.
- Watch folders are implemented as a library-level setting accessible via `DocNest > Settings… > Watch Folders`.
- Each watch folder monitors a local directory for new PDFs using `DispatchSource.makeFileSystemObjectSource` with `O_EVTONLY` file descriptors and `.write` event masks.
- New PDFs are imported through the standard `ImportPDFDocumentsUseCase` pipeline with hash-based deduplication.
- Watch folders support optional label auto-assignment to imported documents.
- Watch folders can be individually paused/resumed. The settings sheet shows per-folder status (monitoring, paused, path not found).
- An initial scan on startup catches files added while the app was closed.
- Watch folder configuration is persisted via SwiftData (`WatchFolder` entity, schema V3).
- The editor sheet provides name, emoji icon, folder path (via NSOpenPanel), enable toggle, and label auto-assign checkboxes.

### Phase 6: Data Integrity and Operational Stability
Goal: app is production-usable and fault-tolerant.

- Consistency checks.
- Reindex or repair mechanisms.
- Undo for metadata edits where feasible.
- Load tests with larger libraries.

### Phase 7: Post-v1 Extensions
- Rule-based label suggestions.
- Extended metadata fields.
- Sync.
- Import of additional file types.
- Recursive watch folder scanning (currently shallow, top-level only).

## 12. MVP Definition

v1 MVP is reached when the following capabilities are stable:

- Create new library and open existing library.
- Import PDFs and store them in library.
- Display documents in list.
- Open PDF preview.
- Create labels and assign them to documents.
- Search and filter by basic metadata and labels.
- Show or open original file in Finder.

## 13. Open Product Decisions

These points should be explicitly decided before implementation starts:

1. Package vs normal directory: should library appear as a single file in Finder?
2. Core Data vs SwiftData: which persistence model is better for debuggability, migrations, and performance?
3. Custom search index or DB-only search: is simple search over persisted fields plus PDF text enough for v1?
4. Hard delete or soft delete: how should deleted documents be handled?
5. Flat labels only, or later extension to hierarchy?

## 14. Recommended Project Start Sequence

For a clean Xcode setup, this sequence is recommended:

1. Finalize domain model and library format.
2. Build minimal persistence layer.
3. Complete import pipeline.
4. Connect document list and PDF preview.
5. Introduce label system.
6. Add search and filters.
7. Only then address OCR, automation, or sync.

This sequence prevents UI features from being built on top of unstable file model or persistence.
