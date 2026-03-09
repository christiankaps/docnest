# docnest

Native macOS Document Management System.

Die erste fachliche Grundlage liegt in [docs/requirements.md](docs/requirements.md).
Die Projektstruktur und technische Startaufteilung liegen in [docs/project-structure.md](docs/project-structure.md).

Das Dokument beschreibt:
- Produktziele und Abgrenzung
- funktionale und nicht-funktionale Anforderungen
- Vorschlag fuer die Struktur der Document Library
- priorisierte Implementierungsphasen fuer Xcode/macOS

Aktuell ist das Repository als fruehes SwiftUI/macOS Scaffold mit klarer Ordnerstruktur angelegt.

Der native Xcode-Einstieg besteht aus:
- [project.yml](project.yml) als reproduzierbare Projektdefinition
- [DocNest.xcodeproj](DocNest.xcodeproj) als generiertem Xcode-Projekt
- [Package.swift](Package.swift) als zusaetzlichem SwiftPM-Einstieg fuer fruehe Build-Validierung
