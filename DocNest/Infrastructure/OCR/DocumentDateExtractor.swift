import Foundation

/// Extracts a document content date from OCR-extracted text.
///
/// Attempts multiple date format patterns for both English and German locales.
/// Returns the first plausible date found, or `nil` if no date can be parsed.
enum DocumentDateExtractor {

    // MARK: - Public API

    /// Extracts a document date from the given text.
    /// - Parameter text: Full text extracted from the document via OCR or embedded text.
    /// - Returns: The first plausible date found, or `nil`.
    static func extractDate(from text: String) -> Date? {
        let candidates = extractCandidateStrings(from: text)
        for candidate in candidates {
            if let date = parseDate(from: candidate) {
                return date
            }
        }
        return nil
    }

    // MARK: - Candidate Extraction

    private static func extractCandidateStrings(from text: String) -> [String] {
        var candidates: [String] = []
        for pattern in candidatePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: range)
            for match in matches {
                if let swiftRange = Range(match.range, in: text) {
                    candidates.append(String(text[swiftRange]))
                }
            }
        }
        return candidates
    }

    // MARK: - Candidate Regex Patterns

    /// Ordered from most specific to least specific to prefer high-confidence matches.
    private static let candidatePatterns: [String] = [
        // ISO 8601: 2024-03-15
        #"\b\d{4}-\d{2}-\d{2}\b"#,

        // English long: "March 15, 2024" / "15 March 2024"
        #"\b(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},?\s+\d{4}\b"#,
        #"\b\d{1,2}\s+(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{4}\b"#,

        // English abbreviated: "Mar 15, 2024" / "15 Mar 2024"
        #"\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\.?\s+\d{1,2},?\s+\d{4}\b"#,
        #"\b\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\.?\s+\d{4}\b"#,

        // German long: "15. März 2024" / "15. März 2024"
        #"\b\d{1,2}\.\s*(?:Januar|Februar|März|April|Mai|Juni|Juli|August|September|Oktober|November|Dezember)\s+\d{4}\b"#,

        // German abbreviated: "15. Mär. 2024" / "15. Jan. 2024"
        #"\b\d{1,2}\.\s*(?:Jan|Feb|Mär|Apr|Mai|Jun|Jul|Aug|Sep|Okt|Nov|Dez)\.?\s+\d{4}\b"#,

        // Numeric DD.MM.YYYY (German/European)
        #"\b\d{1,2}\.\d{1,2}\.\d{4}\b"#,

        // Numeric MM/DD/YYYY (US)
        #"\b\d{1,2}/\d{1,2}/\d{4}\b"#,
    ]

    // MARK: - Date Parsing

    private static func parseDate(from string: String) -> Date? {
        for formatter in dateFormatters {
            formatter.locale = nil // already set on each formatter
            if let date = formatter.date(from: string.trimmingCharacters(in: .whitespaces)) {
                if isPlausibleDocumentDate(date) {
                    return date
                }
            }
        }
        return nil
    }

    /// Returns `true` for dates between 1900 and 10 years from now, excluding implausible values.
    private static func isPlausibleDocumentDate(_ date: Date) -> Bool {
        let earliest = Date(timeIntervalSince1970: -2_208_988_800) // 1900-01-01
        let latest = Calendar.current.date(byAdding: .year, value: 10, to: Date()) ?? Date()
        return date >= earliest && date <= latest
    }

    // MARK: - Formatters

    /// All formatters are created once and reused. Order matters: more specific formats first.
    private static let dateFormatters: [DateFormatter] = {
        let specs: [(format: String, locale: String)] = [
            // ISO 8601
            ("yyyy-MM-dd", "en_US_POSIX"),

            // English long
            ("MMMM d, yyyy", "en_US"),
            ("MMMM d yyyy", "en_US"),
            ("d MMMM yyyy", "en_US"),

            // English abbreviated
            ("MMM d, yyyy", "en_US"),
            ("MMM d yyyy", "en_US"),
            ("d MMM yyyy", "en_US"),
            ("MMM. d, yyyy", "en_US"),
            ("d MMM. yyyy", "en_US"),

            // German long
            ("d. MMMM yyyy", "de_DE"),

            // German abbreviated (normalize trailing dot away by trying both)
            ("d. MMM yyyy", "de_DE"),
            ("d. MMM. yyyy", "de_DE"),

            // Numeric European DD.MM.YYYY
            ("d.M.yyyy", "de_DE"),
            ("dd.MM.yyyy", "de_DE"),

            // Numeric US MM/DD/YYYY
            ("M/d/yyyy", "en_US"),
            ("MM/dd/yyyy", "en_US"),
        ]

        return specs.map { spec in
            let f = DateFormatter()
            f.dateFormat = spec.format
            f.locale = Locale(identifier: spec.locale)
            f.isLenient = false
            return f
        }
    }()
}
