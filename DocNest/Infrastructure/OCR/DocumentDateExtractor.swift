import Foundation

/// Extracts a document content date from OCR-extracted text.
///
/// Uses the system `NSDataDetector` as the primary, native detector, which
/// recognizes dates across many formats and locales (ISO 8601, written month
/// names, and numeric day/month/year styles) without hand-maintained patterns.
///
/// A small explicit-date fallback preserves important fixed document formats the
/// detector can skip, notably numeric dates that immediately follow words like
/// "Invoice" and German month-name dates. Candidates from both sources are
/// merged and the earliest one in reading order wins, so a labeled invoice date
/// is preferred over a later, unrelated date.
enum DocumentDateExtractor {

    // MARK: - Public API

    /// Extracts a document date from the given text.
    /// - Parameter text: Full text extracted from the document via OCR or embedded text.
    /// - Returns: The first plausible calendar date found in reading order, or `nil`.
    static func extractDate(from text: String) -> Date? {
        guard !text.isEmpty else { return nil }

        var best: (location: Int, date: Date)?

        func consider(location: Int, date: Date) {
            guard isPlausibleDocumentDate(date) else { return }
            if best == nil || location < best!.location {
                best = (location, date)
            }
        }

        // Primary: native data detector.
        if let detector = Self.detector {
            let range = NSRange(text.startIndex..., in: text)
            detector.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match,
                      match.resultType == .date,
                      let date = match.date,
                      let matchedRange = Range(match.range, in: text),
                      Self.containsYear(text[matchedRange]) else {
                    return
                }
                consider(location: match.range.location, date: date)
            }
        }

        // Fallback: explicit formats the detector skips. Each candidate carries
        // its own text position so the earliest overall match is still chosen.
        for candidate in Self.explicitFallbackMatches(in: text) {
            consider(location: candidate.location, date: candidate.date)
        }

        return best?.date
    }

    /// Returns `true` for dates between 1900 and 10 years from now, excluding implausible values.
    static func isPlausibleDocumentDate(_ date: Date) -> Bool {
        let earliest = Date(timeIntervalSince1970: -2_208_988_800) // 1900-01-01
        let latest = Calendar.current.date(byAdding: .year, value: 10, to: Date()) ?? Date()
        return date >= earliest && date <= latest
    }

    // MARK: - Native detector

    /// Created once and reused; `NSDataDetector` is thread-safe.
    private static let detector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    }()

    /// Returns `true` if the substring contains four consecutive digits (a year).
    private static func containsYear(_ substring: Substring) -> Bool {
        var run = 0
        for character in substring {
            if character.isNumber {
                run += 1
                if run >= 4 { return true }
            } else {
                run = 0
            }
        }
        return false
    }

    // MARK: - Explicit fallback

    private struct DateFormatterSpec {
        let format: String
        let localeIdentifier: String
    }

    /// An explicit-date pattern and the formatter specs able to parse the strings it matches.
    private struct ExplicitDatePattern {
        let regex: NSRegularExpression
        let formatterSpecs: [DateFormatterSpec]
    }

    /// Explicit fallback patterns, each requiring an explicit four-digit year.
    /// Regexes are shared, but formatters are created per parse because
    /// `DateFormatter` is not thread-safe.
    private static let explicitFallbackPatterns: [ExplicitDatePattern] = {
        func spec(_ format: String, _ localeIdentifier: String) -> DateFormatterSpec {
            DateFormatterSpec(format: format, localeIdentifier: localeIdentifier)
        }

        func pattern(_ regex: String, _ formatterSpecs: [DateFormatterSpec]) -> ExplicitDatePattern? {
            guard let compiled = try? NSRegularExpression(pattern: regex, options: .caseInsensitive) else { return nil }
            return ExplicitDatePattern(regex: compiled, formatterSpecs: formatterSpecs)
        }

        return [
            // ISO 8601: 2024-03-15
            pattern(#"\b\d{4}-\d{1,2}-\d{1,2}\b"#, [spec("yyyy-MM-dd", "en_US_POSIX")]),
            // English long and abbreviated: March 15, 2024 / 15 Mar 2024
            pattern(#"\b(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},?\s+\d{4}\b"#, [
                spec("MMMM d, yyyy", "en_US"),
                spec("MMMM d yyyy", "en_US")
            ]),
            pattern(#"\b\d{1,2}\s+(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{4}\b"#, [
                spec("d MMMM yyyy", "en_US")
            ]),
            pattern(#"\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\.?\s+\d{1,2},?\s+\d{4}\b"#, [
                spec("MMM d, yyyy", "en_US"),
                spec("MMM d yyyy", "en_US"),
                spec("MMM. d, yyyy", "en_US")
            ]),
            pattern(#"\b\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\.?\s+\d{4}\b"#, [
                spec("d MMM yyyy", "en_US"),
                spec("d MMM. yyyy", "en_US")
            ]),
            // German long and abbreviated: 15. März 2024 / 15. Mär. 2024
            pattern(#"\b\d{1,2}\.\s*(?:Januar|Februar|März|April|Mai|Juni|Juli|August|September|Oktober|November|Dezember)\s+\d{4}\b"#, [
                spec("d. MMMM yyyy", "de_DE")
            ]),
            pattern(#"\b\d{1,2}\.\s*(?:Jan|Feb|Mär|Apr|Mai|Jun|Jul|Aug|Sep|Okt|Nov|Dez)\.?\s+\d{4}\b"#, [
                spec("d. MMM yyyy", "de_DE"),
                spec("d. MMM. yyyy", "de_DE")
            ]),
            // European numeric: 15.03.2024
            pattern(#"\b\d{1,2}\.\d{1,2}\.\d{4}\b"#, [
                spec("d.M.yyyy", "de_DE"),
                spec("dd.MM.yyyy", "de_DE")
            ]),
            // US numeric: 03/15/2024
            pattern(#"\b\d{1,2}/\d{1,2}/\d{4}\b"#, [
                spec("M/d/yyyy", "en_US"),
                spec("MM/dd/yyyy", "en_US")
            ])
        ].compactMap { $0 }
    }()

    private static func explicitFallbackMatches(in text: String) -> [(location: Int, date: Date)] {
        let range = NSRange(text.startIndex..., in: text)
        var matches: [(location: Int, date: Date)] = []

        for pattern in explicitFallbackPatterns {
            for result in pattern.regex.matches(in: text, options: [], range: range) {
                guard let matchedRange = Range(result.range, in: text) else { continue }
                let candidate = String(text[matchedRange])
                for formatter in pattern.formatterSpecs.map(Self.makeFormatter) {
                    if let date = formatter.date(from: candidate) {
                        matches.append((location: result.range.location, date: date))
                        break
                    }
                }
            }
        }

        return matches
    }

    private static func makeFormatter(spec: DateFormatterSpec) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = spec.format
        formatter.locale = Locale(identifier: spec.localeIdentifier)
        formatter.isLenient = false
        return formatter
    }
}
