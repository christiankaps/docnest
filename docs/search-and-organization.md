# Search and Organization

## Labels

Labels are the primary organizational primitive in DocNest. A document can have many labels, and labels can be created, renamed, recolored, reordered, and removed without affecting document storage.

Important properties:

- labels are many-to-many with documents
- labels are used for filtering, drag and drop assignment, export naming, and smart folders
- deleting a label removes associations but never deletes documents
- labels can optionally define a short unit, enabling one manual numeric value per document-label assignment

## Label Values

When a label has a unit, each document assigned to that label can store one optional value for that label. For example, an `Invoice` label with unit `€` can store an invoice amount for each invoice document.

Value rules:

- values belong to the document-label pair, not to the document globally
- empty values mean missing, not zero
- clearing a label unit deletes existing values for that label after confirmation
- values are edited from the inspector; list values are contextual read-only indicators

## Label Groups

Label groups are purely a sidebar organization feature. They help cluster labels visually but do not change:

- filtering logic
- smart-folder matching
- search behavior

## Smart Folders

Smart folders are saved combinations of labels. They provide a persistent sidebar shortcut to a specific label combination without introducing filesystem folders or custom query logic.

Smart folders:

- match documents by label combination
- appear as virtual sidebar destinations
- can be reordered and edited
- do not own documents

## Filter Semantics

Label filters use AND semantics. If multiple labels are active, a document must contain all selected labels to match.

This same mental model also applies to smart folders: a smart folder’s label set represents the complete required set for a match.

If the effective filter context contains exactly one unit-enabled label, DocNest shows value statistics for that label at the bottom of the sidebar. Other non-unit labels can still narrow the document set. The statistics footer names the active value label and always shows the filtered documents; it also shows the visible selection when more than one visible document is selected. Missing values are counted separately and are excluded from sum, average, minimum, maximum, and median calculations.

## Search

Search operates across document snapshots built from:

- title
- original filename
- label names
- extracted full text

`SearchDocumentsUseCase` evaluates the current text query alongside the current label filter context.

## Sidebar Organization

The sidebar combines:

- static sections such as all documents, recent, unlabeled, and bin
- smart folders
- label groups and labels

Counts shown in the sidebar are scoped to the active section and filter context rather than being naive global totals.

## Watch Folders as Organization Inputs

Watch folders are not part of the sidebar hierarchy, but they influence organization by:

- importing newly discovered PDFs automatically
- assigning configured labels at import time

This lets external folder-based workflows feed into DocNest’s label-based organization model without making filesystem folders part of the user-facing taxonomy.
