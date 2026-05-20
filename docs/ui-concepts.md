# DocNest UI Concepts

## Purpose

This document defines the basic user experience concepts used across DocNest. It is a shared vocabulary for product, design, and implementation decisions.

DocNest should feel like a focused native macOS document app: local, fast, predictable, and comfortable for repeated daily use.

## Target User Experience

- Users manage documents inside one local library package instead of maintaining many Finder folders.
- The app keeps original PDFs reachable through Finder-oriented actions.
- Organization is document-centric: labels, smart folders, search, and filters describe documents without moving files around.
- Core actions are close to the content: import, search, label, preview, export, reveal, and delete.
- UI feedback for selection, navigation, filtering, and import progress should be immediate even when heavier work continues in the background.

## Primary Surfaces

### Welcome State

The welcome state appears when no valid library is open. It should stay calm and direct, with actions for opening or creating a library. It is normal window content, not a blocking modal.

### Main Window

The main window is the everyday work surface. In open-library mode it uses a three-area structure:

- left sidebar for library sections, smart folders, label groups, and labels
- center content area for document browsing in list or thumbnail mode
- right inspector for selected-document metadata, preview, and detail actions

The sidebar is permanent in open-library mode. The inspector can be toggled, but when visible it must remain fully usable rather than clipped or overlaid.

### Toolbar

The toolbar is the command surface for high-frequency actions such as import, search, presentation mode, sharing, inspector visibility, OCR progress, and appearance. It should use native macOS toolbar behavior and avoid duplicating commands already available in obvious context menus.

### Sidebar

The sidebar is the user's navigation and organization map. It contains:

- library buckets such as All Documents, Recent Imports, Needs Labels, and Bin
- smart folders as saved label combinations
- labels, optionally grouped by label groups

Counts in the sidebar are scoped to the current library state and active filters where applicable. Label rows also act as drop targets for assigning labels to documents.

### Document Browser

The document browser is the main work area. It supports:

- list mode for dense scanning, sorting, optional columns, grouping, and inline label values
- thumbnail mode for visual recognition and Finder-like browsing

Selection must be reliable and visibly immediate. Keyboard navigation follows the currently visible order after filtering, sorting, and grouping.

### Inspector

The inspector is for focused detail, not primary navigation. It shows selected-document metadata, preview state, document date editing, labels, OCR/text extraction status, file availability, and Finder/export actions.

Heavy inspector work, such as preview loading and status recomputation, should be deferred or cancellable so it does not block document selection.

## Organization Concepts

### Library

A `.docnestlibrary` package is the user's local document collection. Finder presents it as one item, while the app stores metadata, originals, previews, and diagnostics inside.

### Document

A document is an imported PDF with a stable identity, title, stored file path, metadata, OCR/search text, document date, optional labels, and an availability state.

### Label

A label is the primary organization primitive. Labels can have colors, optional emoji icons, optional units, and optional per-document values when unit-enabled.

Label chips should be compact, readable, and quiet until interaction is useful. Removing a label or editing a label value must use clear isolated targets so normal selection remains dependable.

### Smart Folder

A smart folder is a saved label combination. It is a virtual view, not a filesystem folder and not a separate copy of documents.

### Label Group

A label group organizes labels in the sidebar. Groups affect presentation only and do not change filtering or smart folder behavior.

### Watch Folder

A watch folder is a library setting that monitors a local filesystem folder for new PDFs. Watch folders are managed from settings, not shown as sidebar navigation.

### Physical Location

A physical location is a reusable place where an original paper document can be found. Locations appear in the sidebar as filters, can be assigned from the inspector, and can have one cover photo copied into the library for visual recognition.

## Interaction Principles

### Native macOS First

Use platform conventions for menus, keyboard shortcuts, window behavior, dialogs, drag and drop, pasteboard handling, share sheets, Quick Look-style preview, Finder reveal, Services, and fullscreen.

Custom styling should clarify DocNest-specific concepts without replacing familiar macOS behavior.

### Reliable Selection

Single-click selection is the foundation of the document browser and sidebar. Drag handles, inline editing, context menus, and hover controls should not make ordinary selection feel fragile.

### Direct Manipulation

Users should be able to organize documents by dragging:

- files or folders into the app to import
- documents onto labels, smart folders, or Bin
- labels onto documents
- documents out to Finder or Desktop to export

Every drag path should use the same validation and business rules as the equivalent menu or button action.

### Background Work With Visible Progress

Import, OCR, preview loading, metadata extraction, and filesystem checks may run in the background. User-visible progress should appear near the workflow that caused it, and cancellation should be available for long-running work.

### Local Trust

DocNest should make storage behavior understandable. Users should know when files are imported, skipped, exported, moved to Bin, permanently removed, repaired, or missing.

### Appearance

The app supports system, light, and dark appearance. Colors, labels, separators, row states, thumbnail surfaces, and preview containers must remain readable in both appearances.

## UX Boundaries

- DocNest is not a cloud-first collaboration workspace.
- DocNest is not a PDF editor.
- DocNest does not require users to understand the internal library folder layout.
- Labels and smart folders should reduce reliance on Finder folders, while Finder access remains available as a fallback.
- Watch folders are automation settings, not primary navigation.
