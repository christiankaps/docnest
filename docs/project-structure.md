# DocNest Project Structure

## Ziel

Die Projektstruktur ist so aufgeteilt, dass Produktlogik, Feature-UI und Infrastruktur sauber getrennt bleiben, ohne frueh in unnoetige Modularisierung zu kippen.

## Verzeichnislayout

```text
DocNest/
  App/
  Domain/
    Entities/
    UseCases/
  Features/
    Library/
    Documents/
  Infrastructure/
    Library/
    Preview/
  Resources/
  Shared/
    Design/

DocNestTests/
DocNestUITests/
SampleLibraries/
docs/
```

## Verantwortlichkeiten

### App

- App-Einstiegspunkt
- globale Navigation
- Window- und Scene-Konfiguration

### Domain

- fachliche Kerntypen wie Dokument, Label und spaetere Filtermodelle
- spaetere Use Cases fuer Import, Labeling, Suche und Library-Operationen

### Features

- UI und Ablauf pro Fachbereich
- Aufteilung nach Library und Documents
- jedes Feature kann spaeter eigene ViewModels, Commands und Unteransichten enthalten

### Infrastructure

- Dateisystemzugriff fuer die Library
- PDF-Vorschau und spaetere Thumbnail-Erzeugung

### Shared

- wiederverwendbare UI-Bausteine und Theme-Definitionen (AppTypography, LabelChip)
- kein unklarer Sammelplatz fuer Fachlogik

## Startpunkt in Xcode

- Das Repository enthaelt eine versionierte Projektdefinition in [project.yml](project.yml).
- Daraus wird [DocNest.xcodeproj](DocNest.xcodeproj) generiert.
- Die bestehende Ordnerstruktur wird direkt als Group- und Source-Struktur im Xcode-Projekt verwendet.

## Naechste sinnvolle Schritte

1. App- und Test-Schemes ueber `xcodebuild` in CI oder lokal standardisieren.
2. Persistenzentscheidung zwischen SwiftData und Core Data treffen.
3. Library-Service in `Infrastructure/Library` anlegen.
4. PDFKit-basierte Vorschau in `Features/Documents` und `Infrastructure/Preview` verdrahten.
