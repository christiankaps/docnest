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
- OCR pipeline for image files or scanned PDFs.
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

### 5.4 Smart Filter
A saved search or filter definition, for example "Invoices 2026" or "Unread + Tax".

## 6. Functional Requirements

### 6.1 Library Management

#### Must
- User can create a new library.
- User can open an existing library.
- App remembers the last successfully opened library and tries to reopen it automatically on next launch.
- If no last-opened library is known, or the stored library can no longer be validated, the app must not show a modal popup. Instead, it shows a welcome state directly in normal window content with actions to open or create a library.
- The save dialog for library creation shows only the library name without the internal extension (.docnestlibrary); the app appends the extension automatically.
- App validates structure and metadata consistency when opening a library.
- App presents understandable error states if a library is damaged or incomplete.
- The active metadata store is library-local and, for v1, stored at Metadata/library.sqlite.

#### Should
- Library is treated as a macOS package (UTExportedTypeDeclarations with com.apple.package conformance), appearing as a single file in Finder and app file dialogs.
- The .docnestlibrary package uses a dedicated file icon in Finder and in macOS open/save panels.
- App provides a "Show in Finder" action for libraries and individual documents.

### 6.2 Document Import

#### Must
- PDFs can be imported via file dialog and drag-and-drop.
- Import captures file hash, filename, creation date, import timestamp, and page count.
- Documents receive a stable internal ID.
- Duplicate detection is required, at least hash-based.
- User sees which files are new and which are duplicates.
- User receives clear feedback when individual files fail in batch import.
- Labels currently active as filters are automatically assigned to newly imported documents so they appear immediately in the filtered view.

#### Should
- Batch import of multiple files.
- Optional copy-into-library instead of external reference; for v1, copy into library is recommended.

#### Decision for Current Implementation
- Hash-based duplicates are skipped in v1 and shown as skipped in import status.

#### Drag-and-Drop Requirements for v1
- Drag-and-drop uses the same import pipeline as the file dialog; validation, duplicate handling, file copy, and feedback are identical.
- While a library is open, PDFs can be dropped onto the main window from Finder or other apps via file URLs.
- Main content shows a clear visual drop zone during valid drag operations; invalid content is not shown as acceptable.
- Multiple PDFs can be imported in one drop.
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

- The document list supports two presentation modes: list and thumbnails. In thumbnail mode, documents appear as thumbnail tiles similar to Finder icon view. Thumbnail size is continuously adjustable via slider.
- Switching between list and thumbnail mode uses a segmented control in the top toolbar.
- Toggling optional file-list attributes in list mode is done through right-click context menu in the list, not a separate header button.
- Toolbar includes a Share button that opens native macOS share sheet for the selected document(s). Printing is reachable via share sheet.
- Right-clicking a document opens a context menu with quick actions: assign labels, show in Finder, move to Bin, and other context actions.
- In the list, each label badge shows an "x" on hover; clicking it removes the label immediately without confirmation dialog.

#### Should
- Quick Look-like preview behavior.
- Split view behavior with list on the left and preview on the right.

### 6.4 Labels

#### Must
- User can create, rename, and delete labels.
- A document can have multiple labels.
- Labels can be assigned quickly via keyboard or direct actions.
- Filtering by one or more labels is supported.
- Left sidebar shows document count for each label.
- Dragging a label from sidebar onto a document assigns that label to the document.
- Dragging one or more documents onto a label in the sidebar assigns the label to those documents. Single-file drops are assigned immediately without confirmation. Multi-file drops show a native confirmation dialog with the count of documents that will be newly assigned and the count already having the label; already-assigned documents are always skipped.
- If multiple labels are selected as filters, logic is AND: only documents with all selected labels are shown.
- Deleting a label must never delete documents; it only removes label associations.
- If a label is assigned to one or more documents, app shows a native confirmation dialog before deletion with the affected document count. Labels with no assignments can be deleted without extra confirmation.
- Label management (create, rename, delete, color selection) is integrated directly in left sidebar, not in a separate modal dialog.
- Label order in sidebar is user-reorderable via drag-and-drop and persisted.

#### Should
- Colored labels.
- Optional emoji icon per label. When set, the emoji replaces the colored circle in sidebar rows, drag previews, and label chips. Users choose an emoji via the system Character Palette (emoji keyboard).
- Label suggestions based on recently used labels.

#### May Follow Later
- Hierarchical labels.
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

#### Should
- Saved smart filters.
- Faceted filters by year, label, file type, duplicate status.

#### v1 Assumption
- For PDFs with extractable text, embedded text is indexed.
- OCR for image PDFs is not part of v1.

### 6.6 Metadata Editing

#### Must
- User can edit title, document date, and labels.
- Technical metadata remains traceable even when title changes.

#### Should
- Custom fields can be prepared as later extension but are not required in v1.

### 6.7 Data Integrity and Recovery

#### Must
- App must not silently lose or overwrite original files.
- Deleting a document first moves it to Bin instead of immediate permanent deletion.
- Bin provides Restore All and single-document restore.
- Bin provides Remove All for permanent removal of all currently binned documents.
- If a document is already in Bin, deleting it means permanent removal from library.
- App can detect missing files or inconsistent metadata.

#### Should
- Repair or reindex functionality for a library.
- Import and metadata changes should be transactional or crash-robust.

## 7. Non-Functional Requirements

### 7.1 Platform
- Native macOS app in Xcode.
- Recommended stack for first version: Swift, SwiftUI, PDFKit, Core Data or SwiftData, Spotlight or custom search index depending on feasibility.
- Project must remain reproducible and traceable in versioned Xcode project definition in repository.

### 7.2 Performance
- Library with at least 20,000 documents should remain usable.
- List filtering and label filtering should feel instant for typical user interactions.
- Preview of an average PDF should appear without noticeable delay.

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
- Network access is not required in v1.
- User must be able to understand where files are stored and what happens during import.

## 8. Library Structure

For the first version, a filesystem-friendly structure is preferred that is technically robust and readable for users in emergency situations.

### 8.1 Recommended Form
- One library as package, for example My Documents.docnestlibrary.
- Inside the package: clear directories instead of binary monoliths.

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
- documentDate
- importedAt
- pageCount
- fileSize
- isDeleted or status field if soft delete is used

### 9.2 Label Entity
- id
- name
- color
- icon (optional emoji)
- createdAt

### 9.3 Relation
- Many-to-many between documents and labels.

### 9.4 Optional Later Entities
- SmartFilter
- CustomFieldDefinition
- ImportJob
- AuditEvent

## 10. UX Requirements

### 10.1 Information Architecture
- Sidebar for library, labels, and smart filters.
- Main area for document list.
- Detail/preview area for selected document.
- Layout must scale meaningfully in normal window mode and fullscreen.
- Three-panel layout (sidebar, document list, inspector) must be fully visible immediately after app launch. No panel may start hidden, collapsed, or partially visible.
- Left sidebar is permanently visible in open-library mode and is not toggleable.
- The app uses a modern, readable system typography style (SF Pro or SF Pro Rounded). Typography, spacing, and visual hierarchy should feel modern and clean.

### 10.2 Core Interactions
- Drag files onto window to import.
- Select a document in list and instantly see preview.
- Assign labels via shortcuts or inspector.
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

### 10.6 Sidebar-Integrated Label Management
- Labels are managed directly in left sidebar, not in separate modal dialog.
- Inline sidebar actions: create label (via + with emoji icon, name, and color editable during creation), edit label (double-click or context menu opens same inline form with all fields — emoji, name, color — editable at once), delete (context menu).
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
- Label creation form includes emoji picker button (opens system Character Palette), name field, and color menu.
- Editing a label (double-click or context menu "Edit") shows the same inline form as creation with all fields — emoji, name, color — editable at once.
- Document detail view supports direct assignment/removal of existing labels plus create-and-assign of new labels via keyboard or direct action.
- Sidebar supports multi-label filtering. With multiple active labels, list shows only documents containing all selected labels.
- Deleting a label removes only associations. Documents and original files remain unchanged.
- Document list supports multi-selection. Inspector can add/remove labels for entire selection.
- For mixed label states, inspector separates shared labels from partially assigned labels and offers actions such as add to remaining documents.
- Label management is integrated in left sidebar (create, edit, delete).
- Labels are reorderable in sidebar, persisted via sortOrder field.

### Phase 5: Search and Retrieval
Goal: users find documents quickly.

- Search across title, filename, labels.
- Optional text index for PDF contents.
- Combinable filters.
- Saved smart filters once Phase 4 is stable.

Current state:
- Main view provides built-in search field for open library.
- Search filters live across title, original filename, label names, and extracted PDF full text.
- Multi-word search is token-based; document remains visible only if all terms are found across searchable metadata and full text.
- Search text and label filters can be combined and operate on the same document list.
- PDF text is extracted via PDFKit during import and stored in the document model. Existing documents without extracted text are backfilled on app launch.

### Phase 6: Data Integrity and Operational Stability
Goal: app is production-usable and fault-tolerant.

- Consistency checks.
- Reindex or repair mechanisms.
- Undo for metadata edits where feasible.
- Load tests with larger libraries.

### Phase 7: Post-v1 Extensions
- OCR.
- Rule-based label suggestions.
- Extended metadata fields.
- Sync.
- Import of additional file types.

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

### 4.1 Im Scope fuer v1
- Lokale Library anlegen, oeffnen, schliessen.
- PDFs importieren.
- Dokumente anzeigen und verwalten.
- Labels erstellen, zuweisen, entfernen, umbenennen.
- Dokumente ueber Metadaten und Labels suchen und filtern.
- Finder-Zugriff auf Originaldateien.
- Unterstuetzung fuer Vollbildmodus sowie Light und Dark Appearance.
- Solide Metadatenpersistenz und Konsistenzpruefungen.

### 4.2 Bewusst ausserhalb von v1
- OCR-Pipeline fuer Bilddateien oder gescannte PDFs.
- iCloud-Sync oder Mehrgeraete-Synchronisation.
- Kollaboration und Mehrbenutzerbetrieb.
- Automatische Klassifikation per ML/AI.
- Vollwertiger Dokumenteditor.
- Mobile Apps.

## 5. Zentrale Begriffe

### 5.1 Library
Ein vom Nutzer gewaehltes Paket oder Verzeichnis, das Originaldokumente, Vorschaudaten und Metadaten enthaelt.

### 5.2 Dokument
Ein importiertes Objekt mit Originaldatei, stabiler interner ID, technischen Metadaten und nutzerdefinierten Informationen.

### 5.3 Label
Eine frei definierbare Kategorisierung, die einem oder mehreren Dokumenten zugewiesen werden kann.

### 5.4 Smart Filter
Gespeicherte Such- oder Filterdefinition, z. B. "Rechnungen 2026" oder "Ungelesen + Steuer".

## 6. Fachliche Anforderungen

### 6.1 Library Management

#### Muss
- Nutzer kann eine neue Library anlegen.
- Nutzer kann eine bestehende Library oeffnen.
- App merkt sich die zuletzt erfolgreich geoeffnete Library und versucht sie beim naechsten Start automatisch wieder zu oeffnen.
- Wenn keine zuletzt geoeffnete Library bekannt ist oder die gespeicherte Library nicht mehr validiert werden kann, zeigt die App keinen modalen Popup-Dialog. Stattdessen wird der Willkommenszustand direkt als normaler Fensterinhalt angezeigt und bietet die Optionen "Library oeffnen" und "Library erstellen".
- Der Save-Dialog zum Erstellen einer Library zeigt nur den Bibliotheksnamen ohne die interne Dateiendung (.docnestlibrary); die App haengt die Endung automatisch an.
- App prueft beim Oeffnen, ob Struktur und Metadaten konsistent sind.
- App zeigt Fehlerzustand verstaendlich an, falls eine Library beschaedigt oder unvollstaendig ist.
- Der aktive Metadaten-Store ist library-lokal und liegt fuer v1 in `Metadata/library.sqlite`.

#### Sollte
- Library wird als macOS Package behandelt (UTExportedTypeDeclarations mit com.apple.package-Konformitaet); im Finder und in den Dateidialogen der App erscheint sie wie eine einzelne Datei, nicht wie ein Ordner.\n- App bietet eine Funktion \"Im Finder anzeigen\" fuer Library und einzelne Dokumente.

### 6.2 Dokumentimport

#### Muss
- PDFs koennen per Dateidialog und Drag-and-drop importiert werden.
- Beim Import werden Datei-Hash, Dateiname, Erstellungsdatum, Importzeitpunkt und Seitenanzahl erfasst.
- Dokumente erhalten eine stabile interne ID.
- Doppelte Dateien werden erkannt, mindestens hash-basiert.
- Nutzer sieht beim Import, welche Dateien neu sind und welche Duplikate darstellen.
- Nutzer erhaelt eine verstaendliche Rueckmeldung, wenn einzelne Dateien im Stapelimport fehlschlagen.
- Beim Import werden die aktuell als Filter aktiven Labels automatisch den neu importierten Dokumenten zugewiesen. Dadurch landen neue Dateien direkt in der gefilterten Ansicht und muessen nicht manuell gelabelt werden.

#### Sollte
- Stapelimport mehrerer Dateien.
- Optionales Kopieren in die Library statt Referenzieren externer Dateien; fuer v1 wird Kopieren in die Library empfohlen.

#### Entscheidung fuer die aktuelle Implementierung
- Hash-basierte Duplikate werden fuer v1 nicht erneut importiert, sondern im Importstatus als uebersprungen ausgewiesen.

#### Drag-and-drop Anforderungen fuer v1
- Drag-and-drop nutzt dieselbe Import-Pipeline wie der Dateidialog; Validierung, Duplikaterkennung, Dateikopie und Rueckmeldung verhalten sich identisch.
- Solange eine Library geoeffnet ist, koennen PDFs aus Finder oder anderen Apps mit Datei-URLs auf das Hauptfenster gezogen werden.
- Der Hauptinhalt zeigt waehrend eines gueltigen Drag-Vorgangs eine klare visuelle Drop-Zone; ungueltige Inhalte werden nicht als akzeptabler Drop dargestellt.
- Mehrere PDFs koennen in einem einzigen Drop-Vorgang importiert werden.
- Nicht-PDF-Dateien im Drop werden fuer v1 nicht importiert und in der Rueckmeldung als uebersprungen oder fehlgeschlagen ausgewiesen.
- Ein Drop ohne geoeffnete Library darf keinen stillen Importversuch ausloesen; die App muss stattdessen den Library-Zustand erklaeren.
- Der Drop soll auf die Dokumentliste und den leeren Bibliothekszustand wirken; Nutzer muessen kein spezielles kleines Ziel treffen.

#### Explizite Abgrenzung fuer v1
- Finder-Datei-URLs und normale Datei-Drops sind Teil von v1.
- Fortgeschrittene Drag-Quellen wie File Promises, Mail-Anhaenge ohne lokale Datei-URL oder externe Provider mit asynchroner Materialisierung sind nicht Teil dieses ersten Schritts.

### 6.3 Dokumentdarstellung

#### Muss
- Listenansicht mit sortierbaren Spalten.
- Wenn linke Seitenleiste und rechter Inspector eingeblendet sind, muessen beide Panels jeweils vollstaendig sichtbar bleiben; die App darf keinen sichtbaren Panel-Inhalt halb abschneiden.
- Wenn das Fenster schmaler wird, schrumpft zuerst die Dokumentliste in der Mitte. Die seitlichen Panels behalten ihre voll nutzbaren Breiten, solange sie sichtbar sind.
- Nutzer kann die Breite der sichtbaren Spalten in der Dokumentliste direkt per Drag-Geste anpassen.
- Nutzer kann Dateiattribute in der Dokumentliste ein- oder ausblenden (Importdatum, Erstellungsdatum, Seitenzahl, Dateigroesse, Labels). Die Spalte "Document" bleibt immer sichtbar.
- Die Dokumentliste nutzt eine klare Zeilenabgrenzung mit alternierender Zeilenfarbe (Even/Odd), um die Lesbarkeit bei vielen Eintraegen zu verbessern.
- Detailansicht fuer Metadaten.
- PDF-Vorschau fuer das ausgewaehlte Dokument.
- Finder-Integration: Originaldatei oeffnen, im Finder zeigen, exportieren.

- Die Dokumentliste unterstuetzt zwei Darstellungsmodi: Listenansicht und Miniaturansicht. In der Miniaturansicht werden Dokumente als Thumbnail-Kacheln dargestellt, aehnlich der Finder-Symbolansicht. Die Groesse der Thumbnails ist ueber einen Schieberegler stufenlos einstellbar.
- Der Wechsel zwischen Listenansicht und Miniaturansicht erfolgt ueber ein Segment-Control in der oberen Toolbar des App-Fensters.
- Das Ein- und Ausblenden optionaler Dateiattribute in der Listenansicht erfolgt ueber ein Rechtsklick-Kontextmenu in der Dokumentliste, nicht ueber einen separaten Header-Button.
- Die Toolbar enthaelt einen Share-Button, der das native macOS-Teilen-Sheet fuer das aktuell selektierte Dokument oder alle selektierten Dokumente oeffnet. Drucken ist ueber das Share-Sheet erreichbar.
- Ein Rechtsklick auf ein Dokument in der Liste oeffnet ein Kontextmenu mit Schnellaktionen: Labels zuweisen, im Finder anzeigen, in den Bin verschieben und weitere kontextbezogene Optionen.
- In der Dokumentliste zeigt jedes einem Dokument zugewiesene Label-Badge beim Hover ein "x"-Symbol. Ein Klick auf dieses "x" entfernt das Label sofort vom Dokument, ohne Bestatigungsdialog.

#### Sollte
- Quick Look aehnliches Vorschauverhalten.
- Split View: Liste links, Vorschau rechts.

### 6.4 Labels

#### Muss
- Nutzer kann Labels anlegen, umbenennen, loeschen.
- Ein Dokument kann mehrere Labels haben.
- Labels koennen schnell per Tastatur oder Direktaktion zugewiesen werden.
- Filter nach einem oder mehreren Labels sind moeglich.
- Die linke Seitenleiste zeigt fuer jedes Label die Anzahl der Dokumente, die dieses Label aktuell tragen.
- Das Ziehen eines Labels aus der Seitenleiste auf ein Dokument in der Liste weist dieses Label dem Dokument zu.
- Das Ziehen eines oder mehrerer Dokumente auf ein Label in der Seitenleiste weist das Ziel-Label allen gezogenen Dokumenten zu, aber erst nach einem nativen Bestatigungsdialog.
- Wenn mehrere Labels als Filter ausgewaehlt sind, gilt AND-Logik: Nur Dokumente mit allen ausgewaehlten Labels werden angezeigt.
- Das Loeschen eines Labels darf niemals die zugeordneten Dokumente loeschen; es entfernt nur die Label-Zuordnung.
- Wenn ein Label mindestens einem Dokument zugewiesen ist, zeigt die App vor dem Loeschen einen nativen Bestatigungsdialog mit der Anzahl betroffener Dokumente. Labels ohne zugewiesene Dokumente werden ohne zusaetzliche Bestaetigung geloescht.
- Label-Verwaltung (Anlegen, Umbenennen, Loeschen, Farbauswahl) ist direkt in die linke Seitenleiste integriert, nicht in einen separaten modalen Dialog.
- Die Reihenfolge der Labels in der Seitenleiste ist vom Nutzer per Drag-and-drop aenderbar. Die benutzerdefinierte Reihenfolge wird persistiert.

#### Sollte
- Farbige Labels.
- Optionales Emoji-Icon pro Label. Wenn gesetzt, ersetzt das Emoji den farbigen Kreis in Seitenleisten-Zeilen, Drag-Vorschauen und Label-Chips. Nutzer waehlen ein Emoji ueber die System-Zeichenpalette (Emoji-Tastatur).
- Label-Vorschlaege auf Basis zuletzt genutzter Labels.

#### Kann spaeter folgen
- Hierarchische Labels.
- Regeln wie "wenn Dateiname enthaelt X, schlage Label Y vor".

### 6.5 Suche und Filter

#### Muss
- Volltextnahe Suche ueber Dateiname, Titel und Labels.
- Kombination aus Suchtext und Label-Filtern.
- Die Library-Buckets in der linken Seitenleiste zeigen die jeweilige Dokumentanzahl fuer "All Documents", "Recent Imports" und "Needs Labels".
- Die linke Seitenleiste enthaelt zusaetzlich einen "Bin"-Bucket mit der Anzahl aktuell geloeschter Dokumente.
- Dokumente im "Bin" werden von normaler Suche und Label-Filtern ignoriert; sie erscheinen nur im Bin-Bucket.
- Dokumente koennen per Drag-and-drop aus der Dokumentliste direkt auf das Bin-Symbol in der Seitenleiste verschoben werden.
- Die Entf/Delete-Taste verschiebt selektierte Dokumente in den Bin; bei selektierten Dokumenten im Bin fuehrt sie ein permanentes Entfernen aus.
- Beim Aktivieren oder Deaktivieren eines Label-Filters muss die Auswahlmarkierung in der Seitenleiste sofort sichtbar umschalten, auch wenn die Aktualisierung der Dokumentliste geringfuegig laenger dauert.
- Sortierung nach Importdatum, Dokumentdatum, Name, Dateigroesse.
- "Needs Labels"-Filter zeigt nur Dokumente ohne Labels an. Wenn dieser Filter aktiv ist, werden aktive Label-Filter automatisch geloescht, um logische Konflikte zu vermeiden (ein Dokument kann nicht gleichzeitig keine Labels haben und bestimmte Labels enthalten).

#### Sollte
- Gespeicherte Smart Filter.
- Facettierte Filter fuer Jahr, Label, Dateityp, Duplikatstatus.

#### Annahme fuer v1
- Bei PDFs mit extrahierbarem Text wird der eingebettete Text indexiert.
- OCR fuer Bild-PDFs ist nicht Teil von v1.

### 6.6 Metadatenbearbeitung

#### Muss
- Nutzer kann Titel, Dokumentdatum und Labels bearbeiten.
- Technische Metadaten bleiben nachvollziehbar, auch wenn der Titel geaendert wird.

#### Sollte
- Benutzerdefinierte Felder sind als spaetere Erweiterung vorbereitbar, aber nicht zwingend in v1.

### 6.7 Datenintegritaet und Wiederherstellung

#### Muss
- App darf Originaldateien nicht stillschweigend verlieren oder ueberschreiben.
- Loeschen eines Dokuments verschiebt es zuerst in den "Bin"-Bucket statt es sofort permanent zu entfernen.
- Der "Bin"-Bucket bietet "Restore All" sowie das Wiederherstellen einzelner Dokumente.
- Der "Bin"-Bucket bietet eine "Remove All"-Funktion fuer permanentes Entfernen aller aktuell im Bin liegenden Dokumente.
- Wenn ein Dokument bereits im Bin liegt, bedeutet Loeschen ein permanentes Entfernen aus der Library.
- App kann fehlende Dateien oder inkonsistente Metadaten erkennen.

#### Sollte
- Repair- oder Reindex-Funktion fuer eine Library.
- Import und Metadatenaenderungen sollen transaktional oder robust gegen Abstuerze sein.

## 7. Nicht-funktionale Anforderungen

### 7.1 Plattform
- Native macOS App in Xcode.
- Empfohlener Stack fuer erste Version: Swift, SwiftUI, PDFKit, Core Data oder SwiftData, Spotlight- oder eigener Suchindex je nach Machbarkeit.
- Das Projekt soll als versionierte Xcode-Projektdefinition im Repository nachvollziehbar und reproduzierbar bleiben.

### 7.2 Performance
- Library mit mindestens 20.000 Dokumenten soll noch benutzbar bleiben.
- Listenfilterung und Label-Filter sollen fuer typische Nutzerinteraktionen subjektiv sofort reagieren.
- Vorschau einer durchschnittlichen PDF-Datei soll ohne merkliche Verzoegerung erscheinen.

### 7.3 Robustheit
- Konsistenz der Library hat hoehere Prioritaet als aggressive Optimierung.
- Metadatenbank und Dateibestand muessen regelmaessig gegeneinander validierbar sein.

### 7.4 Usability
- Zentrale Aktionen muessen ohne tiefe Navigation erreichbar sein.
- Drag-and-drop, Mehrfachauswahl und Tastaturbedienung sind wichtig.
- Die App soll auch ohne Einarbeitung fuer einfache Faelle verstaendlich sein.

### 7.5 Appearance und Fensterverhalten
- Die App muss im nativen macOS Vollbildmodus voll nutzbar sein.
- Alle zentralen Ansichten muessen in Light Mode und Dark Mode visuell konsistent und gut lesbar sein.
- Farben fuer Labels, Selektionen, Trennlinien und Vorschau-Container muessen in beiden Erscheinungsbildern ausreichend Kontrast haben.
- Eigene Farben oder Hintergruende duerfen die systemweite Appearance nicht brechen.
- Ueber das Settings-Fenster (Cmd+,) kann der Nutzer die Darstellung zwischen System, Light und Dark umschalten. Die Auswahl wird persistent in @AppStorage gespeichert.

### 7.6 Datenschutz
- Alle Daten werden lokal verarbeitet.
- Netzwerkzugriffe sind in v1 nicht erforderlich.
- Nutzer muss verstehen koennen, wo Dateien liegen und was beim Import passiert.

## 8. Library-Struktur

Fuer die erste Version ist eine dateisystemfreundliche Struktur sinnvoll, die technisch robust und fuer Nutzer im Notfall lesbar ist.

### 8.1 Empfohlene Form
- Eine Library als Package, z. B. `Meine Dokumente.docnestlibrary`.
- Innerhalb des Packages klare Verzeichnisse statt binarer Monolithen.

### 8.2 Beispielstruktur

```text
Meine Dokumente.docnestlibrary/
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

### 8.3 Designentscheidung
- Fachliche Ordnung erfolgt ueber Metadaten und Labels, nicht ueber Finder-Ordner.
- Physische Unterordner dienen nur Skalierung, Stabilitaet und Debugbarkeit.
- Originaldateien sollen auch ohne App zugreifbar bleiben.

## 9. Datenmodell auf hoher Ebene

### 9.1 Entity Dokument
- `id`
- `originalFileName`
- `storedFilePath`
- `contentHash`
- `title`
- `documentDate`
- `importedAt`
- `pageCount`
- `fileSize`
- `isDeleted` oder Statusfeld falls Soft Delete genutzt wird

### 9.2 Entity Label
- `id`
- `name`
- `color`
- `icon` (optionales Emoji)
- `createdAt`

### 9.3 Relation
- Viele-zu-viele zwischen Dokumenten und Labels.

### 9.4 Optionale spaetere Entities
- SmartFilter
- CustomFieldDefinition
- ImportJob
- AuditEvent

## 10. UX-Anforderungen

### 10.1 Informationsarchitektur
- Seitenleiste fuer Library, Labels und Smart Filter.
- Hauptbereich fuer Dokumentliste.
- Detail- oder Vorschau-Bereich fuer ausgewaehltes Dokument.
- Das Layout muss im normalen Fenster und im Vollbildmodus sinnvoll skalieren.
- Das Drei-Panel-Layout (Seitenleiste, Dokumentliste, Inspector) muss nach dem Start sofort vollstaendig sichtbar sein. Kein Panel darf versteckt, eingeklappt oder nur teilweise sichtbar starten.
- Fuer die linke Seitenleiste wird genau ein Sidebar-Toggle im Toolbar-Bereich angeboten; doppelte Bedienelemente fuer dieselbe Aktion sind nicht zulaessig.
- Die App verwendet eine moderne, gut lesbare Schriftart (SF Pro oder SF Pro Rounded). Typografie, Abstaende und visuelle Gewichtung sollen ein modernes, aufgeraeumtes Erscheinungsbild vermitteln.

### 10.2 Kerninteraktionen
- Dateien auf Fenster ziehen und importieren.
- Dokument in Liste waehlen und sofort Vorschau sehen.
- Labels per Shortcut oder Inspector zuweisen.
- Trefferliste live beim Tippen filtern.
- Command+F fokussiert das Suchfeld der Dokumentansicht, wenn eine Library geoeffnet ist.

### 10.4 Drag-and-drop UX
- Bei einem gueltigen PDF-Drop ist die aktive Drop-Zone sofort erkennbar.
- Die visuelle Rueckmeldung darf Listen- oder Inspector-Inhalte nicht unnoetig verdecken.
- Nach erfolgreichem Drop bleibt der Nutzer im aktuellen Fensterkontext; der Import soll keine neue Library oder kein neues Fenster oeffnen.
- Nach einem abgeschlossenen Drop sieht der Nutzer dieselbe Importzusammenfassung wie beim Dateidialog.

### 10.5 Startup-Zustand ohne Library
- Beim Start ohne geoeffnete Library zeigt die App keine modale Dialogbox und keinen Popup.
- Stattdessen wird das regulaere Drei-Panel-Layout mit leerem Inhalt angezeigt.
- Der Hauptbereich (Content-Bereich) zeigt eine einladende Willkommensansicht mit Aktionen zum Erstellen oder Oeffnen einer Library, eingebettet in den normalen Fensterfluss.
- Die Seitenleiste und der Inspector-Bereich bleiben sichtbar, aber inhaltlich leer oder mit Platzhalter-Zustand.

### 10.6 Seitenleisten-integrierte Label-Verwaltung
- Labels werden direkt in der linken Seitenleiste verwaltet, nicht ueber einen separaten modalen Dialog.
- Inline-Aktionen in der Seitenleiste: Label anlegen (ueber ein "+"-Element mit Emoji-Icon, Name und Farbe waehrend der Erstellung einstellbar), Label bearbeiten (Doppelklick oder Kontextmenue oeffnet dasselbe Inline-Formular mit allen Feldern — Emoji, Name, Farbe — gleichzeitig editierbar), loeschen (Kontextmenue).
- Die Reihenfolge der Labels ist per Drag-and-drop in der Seitenleiste aenderbar. Die benutzerdefinierte Sortierung wird persistiert.
- Label-Filter wirken per AND-Logik bei Mehrfachauswahl.

### 10.7 Automatische Label-Zuweisung beim Import
- Wenn beim Import Label-Filter aktiv sind, werden diese Labels automatisch den neu importierten Dokumenten zugewiesen.
- Dadurch erscheinen importierte Dokumente sofort in der aktuell gefilterten Ansicht.
- Der Nutzer erkennt in der Importzusammenfassung, welche Labels automatisch zugewiesen wurden.

### 10.3 Kritische UX-Regeln
- Nutzer muss jederzeit erkennen koennen, ob er ein Originaldokument, Metadaten oder nur die Sicht auf die Daten veraendert.
- Zerstoererische Aktionen brauchen klare Sprache und Undo, wenn moeglich.
- Light Mode und Dark Mode duerfen nicht nur technisch funktionieren, sondern muessen fuer Listen, Seitenleisten, PDF-Vorschau und Label-Darstellung gestalterisch konsistent umgesetzt sein.
- Menueleisten-Eintraege duerfen nur Aktionen zeigen, die im aktuellen Produkt tatsaechlich unterstuetzt werden; generische Dokument-Template-Befehle wie neues Dokument, sichern, importieren, exportieren oder drucken werden fuer v1 ausgeblendet, solange DocNest dafuer keine passenden Workflows anbietet.

## 11. Priorisierte Implementierungsreihenfolge

Die Reihenfolge sollte technische Risiken frueh reduzieren und frueh ein benutzbares Kernprodukt liefern.

### Phase 1: Fundament der Library
Ziel: Die App kann Libraries sauber anlegen und oeffnen.

- Xcode-Projekt anlegen.
- Reproduzierbare Projekt- und Scheme-Definition im Repository verankern.
- App-Architektur festlegen.
- Library-Package-Format definieren.
- Persistenzmodell fuer Dokumente und Labels anlegen.
- Basis fuer Dateioperationen und Konsistenzpruefung bauen.

### Phase 2: Import-Pipeline
Ziel: PDFs kommen robust in die Library.

- Einzel- und Mehrfachimport.
- Datei-Hashing und Duplikaterkennung.
- Kopieren in `Originals/`.
- Metadatenerfassung beim Import.
- Fehlerbehandlung und Importstatus.
- Drag-and-drop an die bestehende Import-Pipeline anschliessen.

Aktueller Stand:
- Import speichert Dateiname, Dateigroesse, Dateierstellungsdatum, Seitenanzahl, Importzeitpunkt und Content-Hash im Dokumentmodell.
- Hash-basierte Duplikate werden uebersprungen und im Importstatus explizit ausgewiesen.
- Dateidialog-Import und Drag-and-drop verwenden denselben Importpfad und dieselbe Rueckmeldung.
- Die Dokumentliste dient als grosszuegige Drop-Zone; bei geschlossenener Library erklaert die App den fehlenden Importkontext statt still zu scheitern.
- Beim Import werden aktuell aktive Label-Filter automatisch auf neu importierte Dokumente uebertragen.

Implementierungsplan fuer Drag-and-drop:
1. In der Hauptansicht einen grosszuegigen Drop-Bereich auf dem Content-Bereich einfuehren, nicht nur auf einem einzelnen Unterelement.
2. Drop nur fuer PDFs bzw. Datei-URLs akzeptieren und die visuelle Aktivierung an gueltige Inhalte koppeln.
3. Den Drop-Handler auf dieselbe Import-Use-Case-Schnittstelle wie den Dateidialog routen, damit kein zweiter Importpfad entsteht.
4. Gemischte Drops mit PDFs und ungueltigen Dateien sauber in eine gemeinsame Rueckmeldung uebersetzen.
5. Den leeren Bibliothekszustand und die Dokumentliste als Drop-Ziel testen, einschliesslich Mehrfachdrop, Duplikaten und Fehlerfaellen.
6. UI-Tests fuer erfolgreichen Drop und fuer abgelehnte Inhalte nachziehen, sobald die Drop-Mechanik stabil ist.

### Phase 3: Lesen und Anzeigen
Ziel: Dokumente werden in der App wirklich nutzbar.

- Dokumentliste.
- Sortierung.
- PDF-Vorschau mit PDFKit.
- Detailansicht fuer Metadaten.
- Finder-Aktionen.

Aktueller Stand:
- Die Dokumentliste bietet sortierbare Spalten fuer Titel, Importdatum, Seitenzahl und Dateigroesse.
- Die Dokumentliste zeigt den Dokumenttitel in einer einzigen "Document"-Spalte; der Originaldateiname ist im Inspector einsehbar und wird nicht dupliziert.
- Die Dokumentliste nutzt dichtere Typografie fuer grosse Libraries und zeigt Labels als visuelle Chips statt nur als Fliesstext.
- Die Dokumentliste unterstuetzt anpassbare Spaltenbreiten per Drag-Geste in der Kopfzeile.
- Dateiattribute (ausser "Document") koennen ueber ein Spaltenmenue ein- oder ausgeblendet werden.
- Die Dokumentliste verwendet alternierende Zeilenhintergruende fuer bessere visuelle Trennung benachbarter Eintraege.
- Der Inspector bietet Finder-Aktionen fuer Originaldatei und Library.
- Die Split-View reserviert mehr Breite fuer Seitenleiste und Detailbereich, damit Library-Namen und die PDF-Vorschau im Alltagsbetrieb besser lesbar bleiben.
- Das Drei-Panel-Layout verwendet NavigationSplitView mit drei Spalten (sidebar, content, detail). NavigationSplitView liefert nativ volle Spaltenhoehe, einen integrierten Sidebar-Toggle und konsistentes Resize-Verhalten auf macOS. Die Spaltenbreiten werden ueber navigationSplitViewColumnWidth gesteuert: Sidebar min 200/ideal 260/max 320, Inspector min 360/ideal 420/max 480, Dokumentliste flexibel.
- Die Detailansicht trennt PDF-Vorschau und Metadaten ueber einen vertikal verschiebbaren Splitter, damit Nutzer die Vorschauhoehe direkt anpassen koennen.
- Die App startet mit einer Fensterbreite und Split-View-Konfiguration, in der die linke Seitenleiste standardmaessig sichtbar bleibt; Nutzer sollen die Library-Navigation nicht erst durch manuelles Verbreitern des Fensters wiederherstellen muessen.
- Ein Sidebar-Toggle-Button in der Toolbar bleibt immer sichtbar und erlaubt das Ein- und Ausblenden der Seitenleiste unabhaengig vom aktuellen Layout-Zustand.
- Die Startup-Ansicht ohne Library ist in das regulaere Drei-Panel-Layout integriert und zeigt keinen separaten Popup-Dialog mehr.
- Die Typografie wurde auf ein konsistentes, modernes Schriftkonzept mit gerundeter Systemschrift vereinheitlicht.
- Dokumente koennen in der Listen- und Miniaturansicht ueber das Kontextmenue "Rename" inline umbenannt werden.
- Leertaste oder Doppelklick auf ein Dokument oeffnet eine native Quick-Look-Vorschau ueber QLPreviewPanel, aehnlich dem Finder-Verhalten.
- Pfeiltasten navigieren durch die Dokumentliste; bei geoeffneter Quick-Look-Vorschau wird die Vorschau automatisch aktualisiert.
- Der Focus-Ring der Dokumentliste ist fuer ein saubereres Erscheinungsbild unterdrueckt.
- Das Toolbar-Library-Menue enthaelt bei geoeffneter Library einen Eintrag "Show in Finder", der das Library-Package im Finder anzeigt.
- Der Fenstertitel zeigt den Namen der geoeffneten Library (ohne Dateiendung) oder "DocNest", wenn keine Library geoeffnet ist.

### Phase 4: Labels als primaeres Ordnungssystem
Ziel: Nutzer kann Dokumente sinnvoll organisieren.

- CRUD fuer Labels.
- Zuweisung zu Dokumenten.
- Filter nach Labels.
- Gute Tastatur- und Multi-Select-Flows.

Aktueller Stand:
- Labels koennen global angelegt, umbenannt, zusammengefuehrt und geloescht werden.
- Jedes Label hat eine vom Nutzer waehlbare Farbe aus einem festen Farbkatalog (10 Optionen). Die Farbe wird in Seitenleiste, Dokumentliste und Inspector konsistent als farbiger Chip dargestellt.
- Jedes Label unterstuetzt ein optionales Emoji-Icon. Wenn gesetzt, ersetzt das Emoji den farbigen Kreis in Seitenleisten-Zeilen, Drag-Vorschauen und Label-Chips in der gesamten App.
- Das Anlegen eines Labels bietet ein Formular mit Emoji-Picker-Button (oeffnet die System-Zeichenpalette), Namensfeld und Farbmenue.
- Das Bearbeiten eines Labels (Doppelklick oder Kontextmenue "Edit") zeigt dasselbe Inline-Formular wie beim Anlegen, mit allen Feldern — Emoji, Name, Farbe — gleichzeitig editierbar.
- Die Dokument-Detailansicht erlaubt direkte Zuweisung und Entfernung bestehender Labels sowie das Anlegen und sofortige Zuweisen neuer Labels per Tastatur oder Direktaktion.
- Die Seitenleiste bietet Mehrfachfilter ueber Labels. Wenn mehrere Labels aktiv sind, zeigt die Liste nur Dokumente, die alle ausgewaehlten Labels enthalten.
- Das Loeschen eines Labels entfernt nur die Zuordnung. Dokumente und Originaldateien bleiben unveraendert in der Library.
- Die Dokumentliste unterstuetzt Mehrfachselektion. Der Inspector kann Labels fuer die gesamte Auswahl hinzufuegen oder von der gesamten Auswahl entfernen.
- Bei gemischten Label-Zustaenden zeigt der Inspector gemeinsame Labels getrennt von partiell vergebenen Labels an und bietet Aktionen wie "zu verbleibenden Dokumenten hinzufuegen" an.
- Die Label-Verwaltung ist in die linke Seitenleiste integriert (anlegen, bearbeiten, loeschen).
- Labels lassen sich in der Seitenleiste neu anordnen; die Reihenfolge wird ueber ein persistiertes `sortOrder`-Feld gespeichert.

### Phase 5: Suche und Wiederfinden
Ziel: Dokumente lassen sich schnell wiederfinden.

- Suche ueber Titel, Dateiname, Labels.
- Optional Textindex fuer PDF-Inhalte.
- Kombinierbare Filter.
- Gespeicherte Smart Filter, wenn Phase 4 stabil ist.

Aktueller Stand:
- Die Hauptansicht bietet ein eingebautes Suchfeld fuer die geoeffnete Library.
- Die Suche filtert live ueber Titel, Originaldateiname, Labelnamen und extrahierten PDF-Volltext.
- Mehrwort-Suchen arbeiten token-basiert; ein Dokument bleibt nur sichtbar, wenn alle Suchterme ueber die durchsuchbaren Metadaten und den Volltext hinweg gefunden werden.
- Suchtext und Label-Filter lassen sich kombinieren und wirken gemeinsam auf dieselbe Dokumentliste.
- PDF-Text wird beim Import via PDFKit extrahiert und im Dokumentmodell gespeichert. Bestehende Dokumente ohne extrahierten Text werden beim App-Start nachtraeglich befuellt.

### Phase 6: Datenintegritaet und Betriebsfaehigkeit
Ziel: Die App ist alltagstauglich und fehlertolerant.

- Konsistenzchecks.
- Reindex oder Repair-Mechanismen.
- Undo fuer Metadatenaenderungen, wenn vertretbar.
- Belastungstests mit groesseren Libraries.

### Phase 7: Erweiterungen nach v1
- OCR.
- Regelbasierte Label-Vorschlaege.
- Erweiterte Metadatenfelder.
- Sync.
- Import weiterer Dateitypen.

## 12. MVP-Definition

Ein v1-MVP ist erreicht, wenn folgende Faehigkeiten stabil vorhanden sind:

- Neue Library erstellen und bestehende oeffnen.
- PDFs importieren und in der Library speichern.
- Dokumente in Liste anzeigen.
- PDF-Vorschau oeffnen.
- Labels anlegen und Dokumenten zuweisen.
- Suche und Filter ueber grundlegende Metadaten und Labels.
- Originaldatei im Finder anzeigen oder oeffnen.

## 13. Offene Produktentscheidungen

Diese Punkte sollten vor dem Start der Implementierung bewusst entschieden werden:

1. Package statt normales Verzeichnis: Soll die Library im Finder wie eine einzelne Datei erscheinen?
2. Core Data oder SwiftData: Welches Persistenzmodell ist fuer Debugbarkeit, Migrationen und Performance sinnvoller?
3. Eigener Suchindex oder nur DB-Suche: Reicht fuer v1 eine einfache Suche ueber persistierte Felder plus PDF-Text?
4. Hard Delete oder Soft Delete: Wie soll mit geloeschten Dokumenten umgegangen werden?
5. Labels nur flach oder spaeter hierarchisch erweiterbar?

## 14. Empfehlung fuer den Projektstart

Wenn du die App in Xcode sauber aufsetzen willst, ist diese Arbeitsreihenfolge sinnvoll:

1. Domain-Modell und Library-Format finalisieren.
2. Minimalen Persistenz-Layer bauen.
3. Import-Pipeline fertigstellen.
4. Dokumentliste und PDF-Vorschau anschliessen.
5. Label-System einfuehren.
6. Suche und Filter ergaenzen.
7. Danach erst OCR, Automatisierung oder Sync betrachten.

Diese Reihenfolge verhindert, dass UI-Funktionen auf unsauberem Dateimodell oder instabiler Persistenz aufbauen.