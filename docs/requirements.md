# DocNest Requirements

## 1. Produktziel

DocNest ist eine native macOS App zur Verwaltung persoenlicher und beruflicher Dokumente mit Fokus auf PDF-Dateien. Die App kombiniert drei Kernideen:

1. Eine lokale Document Library, die aehnlich wie Apple Fotos als zusammenhaengende Bibliothek verwaltet wird.
2. Ein intuitives Labelling-System fuer schnelles Organisieren, Filtern und Wiederfinden.
3. Direkten Fallback-Zugriff im Dateisystem, falls Dokumente ausserhalb der App eingesehen oder gesichert werden muessen.

Die App soll lokal, schnell und vertrauenswuerdig wirken. Cloud-Funktionen sind optional spaetere Erweiterungen, aber nicht Teil des ersten Releases.

## 2. Produktprinzipien

### 2.1 Lokaler Besitz der Daten
- Alle Originaldokumente liegen lokal in einer vom Nutzer kontrollierten Library.
- Die App versteckt Dateien nicht in proprietaeren, unzugaenglichen Datenbanken.
- Metadaten duerfen intern verwaltet werden, aber die Rohdokumente muessen im Dateisystem auffindbar bleiben.

### 2.2 PDF-First, dokumentzentriert
- PDFs haben Prioritaet in Import, Vorschau, Suche und Metadatenbearbeitung.
- Andere Formate koennen spaeter folgen, duerfen das erste Release aber nicht verkomplizieren.

### 2.3 Organisieren ohne Ordnerzwang
- Labels sind das primaere Ordnungssystem.
- Physische Ablagestruktur dient Robustheit und interner Verwaltung, nicht der fachlichen Organisation.

### 2.4 Native macOS Experience
- Die App fuehlt sich wie eine echte Mac-Anwendung an: schnell, dateisystemnah, drag-and-drop-faehig, mit guter Tastaturbedienung und systemnahen Dialogen.
- Die App unterstuetzt den nativen macOS Vollbildmodus.
- Die App passt sich konsistent an Light Mode und Dark Mode an.

## 3. Zielgruppe

### 3.1 Primaere Nutzergruppen
- Einzelpersonen mit vielen PDFs: Rechnungen, Vertraege, Steuerunterlagen, Handbuecher, Scans.
- Freiberufler oder kleine Teams mit lokalem Dokumentenbestand.
- Nutzer, die Dokumente strukturiert verwalten wollen, ohne in starre Ordnerhierarchien gezwungen zu werden.

### 3.2 Typische Anwendungsfaelle
- Rechnung importieren, mit Labels versehen und spaeter ueber Suche wiederfinden.
- Vertrag nach Kunde, Jahr und Status markieren.
- Eingescannte Unterlagen zentral sammeln und inhaltlich auffindbar machen.
- Dokumente ausserhalb der App per Finder oeffnen oder exportieren.

## 4. Scope und Abgrenzung

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
- Wenn keine zuletzt geoeffnete Library bekannt ist oder die gespeicherte Library nicht mehr validiert werden kann, zeigt die App einen Willkommensdialog mit den Optionen "Library oeffnen" und "Library erstellen", damit Nutzer sofort starten koennen.
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
- Detailansicht fuer Metadaten.
- PDF-Vorschau fuer das ausgewaehlte Dokument.
- Finder-Integration: Originaldatei oeffnen, im Finder zeigen, exportieren.

#### Sollte
- Quick Look aehnliches Vorschauverhalten.
- Split View: Liste links, Vorschau rechts.

### 6.4 Labels

#### Muss
- Nutzer kann Labels anlegen, umbenennen, loeschen.
- Ein Dokument kann mehrere Labels haben.
- Labels koennen schnell per Tastatur oder Direktaktion zugewiesen werden.
- Filter nach einem oder mehreren Labels sind moeglich.

#### Sollte
- Farbige Labels.
- Label-Vorschlaege auf Basis zuletzt genutzter Labels.
- Label-Verwaltung als eigene Seitenleiste oder Inspector.

#### Kann spaeter folgen
- Hierarchische Labels.
- Regeln wie "wenn Dateiname enthaelt X, schlage Label Y vor".

### 6.5 Suche und Filter

#### Muss
- Volltextnahe Suche ueber Dateiname, Titel, Notizen und Labels.
- Kombination aus Suchtext und Label-Filtern.
- Sortierung nach Importdatum, Dokumentdatum, Name, Dateigroesse.

#### Sollte
- Gespeicherte Smart Filter.
- Facettierte Filter fuer Jahr, Label, Dateityp, Duplikatstatus.

#### Annahme fuer v1
- Bei PDFs mit extrahierbarem Text wird der eingebettete Text indexiert.
- OCR fuer Bild-PDFs ist nicht Teil von v1.

### 6.6 Metadatenbearbeitung

#### Muss
- Nutzer kann Titel, Notizen, Dokumentdatum und Labels bearbeiten.
- Technische Metadaten bleiben nachvollziehbar, auch wenn der Titel geaendert wird.

#### Sollte
- Benutzerdefinierte Felder sind als spaetere Erweiterung vorbereitbar, aber nicht zwingend in v1.

### 6.7 Datenintegritaet und Wiederherstellung

#### Muss
- App darf Originaldateien nicht stillschweigend verlieren oder ueberschreiben.
- Loeschen eines Dokuments aus der App muss klar zwischen "aus Library entfernen" und "Datei wirklich loeschen" unterscheiden.
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
- `textContent` oder Referenz auf Suchindex
- `isDeleted` oder Statusfeld falls Soft Delete genutzt wird

### 9.2 Entity Label
- `id`
- `name`
- `color`
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

### 10.2 Kerninteraktionen
- Dateien auf Fenster ziehen und importieren.
- Dokument in Liste waehlen und sofort Vorschau sehen.
- Labels per Shortcut oder Inspector zuweisen.
- Trefferliste live beim Tippen filtern.

### 10.4 Drag-and-drop UX
- Bei einem gueltigen PDF-Drop ist die aktive Drop-Zone sofort erkennbar.
- Die visuelle Rueckmeldung darf Listen- oder Inspector-Inhalte nicht unnoetig verdecken.
- Nach erfolgreichem Drop bleibt der Nutzer im aktuellen Fensterkontext; der Import soll keine neue Library oder kein neues Fenster oeffnen.
- Nach einem abgeschlossenen Drop sieht der Nutzer dieselbe Importzusammenfassung wie beim Dateidialog.

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
- Der Inspector bietet Finder-Aktionen fuer Originaldatei und Library.
- Die Split-View reserviert mehr Breite fuer Seitenleiste und Detailbereich, damit Library-Namen und die PDF-Vorschau im Alltagsbetrieb besser lesbar bleiben.
- Die Detailansicht trennt PDF-Vorschau und Metadaten ueber einen vertikal verschiebbaren Splitter, damit Nutzer die Vorschauhoehe direkt anpassen koennen.
- Die App startet mit einer Fensterbreite und Split-View-Konfiguration, in der die linke Seitenleiste standardmaessig sichtbar bleibt; Nutzer sollen die Library-Navigation nicht erst durch manuelles Verbreitern des Fensters wiederherstellen muessen.
- Ein Sidebar-Toggle-Button in der Toolbar bleibt immer sichtbar und erlaubt das Ein- und Ausblenden der Seitenleiste unabhaengig vom aktuellen Layout-Zustand.

### Phase 4: Labels als primaeres Ordnungssystem
Ziel: Nutzer kann Dokumente sinnvoll organisieren.

- CRUD fuer Labels.
- Zuweisung zu Dokumenten.
- Filter nach Labels.
- Gute Tastatur- und Multi-Select-Flows.

Aktueller Stand:
- Labels koennen global angelegt, umbenannt, zusammengefuehrt und geloescht werden.
- Die Dokument-Detailansicht erlaubt direkte Zuweisung und Entfernung bestehender Labels sowie das Anlegen und sofortige Zuweisen neuer Labels per Tastatur oder Direktaktion.
- Die Seitenleiste bietet Mehrfachfilter ueber Labels. Wenn mehrere Labels aktiv sind, zeigt die Liste nur Dokumente, die alle ausgewaehlten Labels enthalten.
- Das Loeschen eines Labels entfernt nur die Zuordnung. Dokumente und Originaldateien bleiben unveraendert in der Library.
- Die Dokumentliste unterstuetzt Mehrfachselektion. Der Inspector kann Labels fuer die gesamte Auswahl hinzufügen oder von der gesamten Auswahl entfernen.
- Bei gemischten Label-Zustaenden zeigt der Inspector gemeinsame Labels getrennt von partiell vergebenen Labels an und bietet Aktionen wie "zu verbleibenden Dokumenten hinzufuegen" an.

### Phase 5: Suche und Wiederfinden
Ziel: Dokumente lassen sich schnell wiederfinden.

- Suche ueber Titel, Dateiname, Notizen, Labels.
- Optional Textindex fuer PDF-Inhalte.
- Kombinierbare Filter.
- Gespeicherte Smart Filter, wenn Phase 4 stabil ist.

Aktueller Stand:
- Die Hauptansicht bietet ein eingebautes Suchfeld fuer die geoeffnete Library.
- Die Suche filtert live ueber Titel, Originaldateiname, Notizen und Labelnamen.
- Mehrwort-Suchen arbeiten token-basiert; ein Dokument bleibt nur sichtbar, wenn alle Suchterme ueber die durchsuchbaren Metadaten hinweg gefunden werden.
- Suchtext und Label-Filter lassen sich kombinieren und wirken gemeinsam auf dieselbe Dokumentliste.
- PDF-Volltextsuche oder ein separater Suchindex sind noch nicht Teil des aktuellen Schritts.

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