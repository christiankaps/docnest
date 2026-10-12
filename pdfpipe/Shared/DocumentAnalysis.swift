import Foundation
import PDFKit

struct RankedWord: Identifiable, Sendable, Equatable {
    var text: String
    var score: Double
    var id: String { text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
}

enum DocumentDate: Sendable, Equatable {
    case found(String)
    case fallback
    case ambiguous([String])
    var value: String? { if case .found(let value) = self { value } else { nil } }
    var isAmbiguous: Bool { if case .ambiguous = self { true } else { false } }
    var candidates: [String] { if case .ambiguous(let dates) = self { dates } else { [] } }
}

struct DocumentAnalysis: Sendable {
    var date: DocumentDate
    var words: [RankedWord]
    var hasText: Bool
    static let empty = DocumentAnalysis(date: .fallback, words: [], hasText: false)
}

enum DocumentAnalyzer {
    private struct DateCandidate {
        var value: String
        var score: Int
        var order: Int
        var ambiguous: Bool
    }

    static func analyze(_ url: URL) throws -> DocumentAnalysis {
        guard let document = PDFDocument(url: url) else { throw PipeError.message("Cannot read the PDF text for filename analysis.") }
        let pages = (0..<document.pageCount).map { String((document.page(at: $0)?.string ?? "").prefix(200_000)) }
        return analyze(pages: pages)
    }

    static func analyze(pages: [String]) -> DocumentAnalysis {
        let text = pages.joined(separator: "\n")
        return .init(date: resolveDate(text), words: rankWords(pages),
            hasText: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private static func resolveDate(_ text: String) -> DocumentDate {
        let patterns = [
            #"\b((?:19|20)\d{2})[-./](\d{1,2})[-./](\d{1,2})\b"#,
            #"\b(\d{1,2})[./](\d{1,2})[./]((?:19|20)\d{2})\b"#
        ]
        let source = text as NSString
        var candidates: [DateCandidate] = []
        for (patternIndex, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
                let a = Int(source.substring(with: match.range(at: 1))) ?? 0
                let b = Int(source.substring(with: match.range(at: 2))) ?? 0
                let c = Int(source.substring(with: match.range(at: 3))) ?? 0
                let year = patternIndex == 0 ? a : c
                let month = b
                let day = patternIndex == 0 ? c : a
                guard let value = validDate(year: year, month: month, day: day) else { continue }
                let start = max(0, match.range.location - 45)
                let context = source.substring(with: NSRange(location: start, length: match.range.location - start)).lowercased()
                let recent = String(context.suffix(30))
                var score = 0
                if recent.contains("rechnungsdatum") || recent.contains("invoice date") || recent.contains("ausgestellt") || recent.contains("issue date") { score += 4 }
                else if recent.contains("datum") || recent.contains("date") { score += 2 }
                if recent.contains("fällig") || recent.contains("due") || recent.contains("zahlbar") { score -= 5 }
                if recent.contains("leistungszeitraum") || recent.contains("service period") { score -= 3 }
                let ambiguousNumeric = patternIndex == 1 && source.substring(with: match.range).contains("/") && a <= 12 && b <= 12 && a != b
                candidates.append(.init(value: value, score: score, order: match.range.location, ambiguous: ambiguousNumeric))
                if ambiguousNumeric, let alternative = validDate(year: year, month: a, day: b) {
                    candidates.append(.init(value: alternative, score: score, order: match.range.location, ambiguous: true))
                }
            }
        }
        guard !candidates.isEmpty else { return .fallback }
        let top = candidates.map(\.score).max() ?? 0
        let best = candidates.filter { $0.score == top }.sorted { $0.order < $1.order }
        let dates = Array(Set(best.map(\.value))).sorted()
        if dates.count == 1, !best.contains(where: \.ambiguous), let only = dates.first { return .found(only) }
        return .ambiguous(dates)
    }

    private static func validDate(year: Int, month: Int, day: Int) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        guard actual.year == year, actual.month == month, actual.day == day else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static let stopwords: Set<String> = Set("""
        the and for with from this that your you are was were have has had but not all can will would should one two three
        der die das den dem des ein eine einer eines einem und oder mit von vom zur zum aus auf bei für ist sind war wurden
        sie wir ihr ihre ihren nicht auch über unter durch nach vor bis als am im in an zu du de la le les et en un une
        page seite www http https com net org bank iban bic ust id kundenservice telefon phone email info
        invoice date number total datum nummer betrag
        """.split(whereSeparator: \.isWhitespace).map(String.init))

    private static func rankWords(_ pages: [String]) -> [RankedWord] {
        guard let wordPattern = try? NSRegularExpression(pattern: #"[\p{L}][\p{L}\p{M}]{2,}"#) else { return [] }
        var counts: [String: (display: String, count: Int, bonus: Double, first: Int)] = [:]
        var order = 0
        var repeatedLines: [String: Int] = [:]
        for page in pages {
            for line in page.split(separator: "\n") {
                let key = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !key.isEmpty { repeatedLines[key, default: 0] += 1 }
            }
        }
        for (pageIndex, page) in pages.enumerated() {
            for (lineIndex, line) in page.split(separator: "\n").enumerated() {
                let normalizedLine = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if repeatedLines[normalizedLine, default: 0] > 1 && pages.count > 1 { continue }
                let lineText = String(line)
                let nsLine = lineText as NSString
                var wordsOnLine: Set<String> = []
                for match in wordPattern.matches(in: lineText, range: NSRange(location: 0, length: nsLine.length)) {
                    let display = nsLine.substring(with: match.range)
                    let key = display.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                    guard !stopwords.contains(key), display.count <= 36, wordsOnLine.insert(key).inserted else { continue }
                    let heading = pageIndex == 0 && lineIndex < 4 ? 2.5 : 0
                    let uppercase = display.count > 3 && display == display.uppercased() ? 0.3 : 0
                    if var item = counts[key] {
                        item.count += 1
                        item.bonus = max(item.bonus, heading + uppercase)
                        counts[key] = item
                    } else {
                        counts[key] = (display, 1, heading + uppercase, order)
                    }
                    order += 1
                }
            }
        }
        return counts.map { _, item in
            (word: RankedWord(text: item.display, score: 1 + log(Double(item.count)) + item.bonus), first: item.first)
        }.sorted { a, b in
            if a.word.score != b.word.score { return a.word.score > b.word.score }
            if a.first != b.first { return a.first < b.first }
            return a.word.id < b.word.id
        }.prefix(30).map(\.word)
    }
}
