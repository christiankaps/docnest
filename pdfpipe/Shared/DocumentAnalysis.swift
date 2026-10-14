import Foundation
import PDFKit
import UIKit

enum TextSource: Hashable, Sendable { case embedded, ocr, plain }

struct AnalysisToken: Sendable {
    var text: String
    var size: Double?
    var bold: Bool
    var italic: Bool
    var confidence: Float
    var source: TextSource
}

struct AnalysisLine: Sendable {
    var text: String
    var tokens: [AnalysisToken]
    var topFraction: Double?
}

struct AnalysisPage: Sendable {
    var text: String
    var lines: [AnalysisLine]
}

struct RankedWord: Identifiable, Sendable, Equatable {
    var text: String
    var score: Double
    var id: String { text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
}

struct DateSuggestion: Identifiable, Sendable, Equatable {
    var value: String
    var score: Int
    var isAmbiguous: Bool
    var id: String { value }
}

enum DocumentDate: Sendable, Equatable {
    case found(String)
    case fallback
    case ambiguous([String])
    var value: String? { if case .found(let value) = self { value } else { nil } }
    var isAmbiguous: Bool { if case .ambiguous = self { true } else { false } }
}

struct DocumentAnalysis: Sendable {
    var date: DocumentDate
    var dates: [DateSuggestion]
    var words: [RankedWord]
    var hasText: Bool
    static let empty = DocumentAnalysis(date: .fallback, dates: [], words: [], hasText: false)
}

enum DocumentAnalyzer {
    private static let wordPattern = try! NSRegularExpression(pattern: #"[\p{L}][\p{L}\p{M}]{2,}"#)

    private struct DateCandidate {
        var value: String
        var score: Int
        var order: Int
        var ambiguous: Bool
    }

    static func analyze(_ url: URL) throws -> DocumentAnalysis {
        guard let document = PDFDocument(url: url) else { throw PipeError.message("Cannot read the PDF text for filename analysis.") }
        let pages = (0..<document.pageCount).map { index in
            document.page(at: index).map(extractPage) ?? AnalysisPage(text: "", lines: [])
        }
        return analyze(pages: pages)
    }

    static func analyze(pages: [String]) -> DocumentAnalysis {
        analyze(pages: pages.map { page in
            AnalysisPage(text: page, lines: page.split(separator: "\n").map { line in
                let value = String(line)
                return AnalysisLine(text: value, tokens: tokens(in: value, source: .plain), topFraction: nil)
            })
        })
    }

    static func analyze(pages: [AnalysisPage]) -> DocumentAnalysis {
        let text = pages.map(\.text).joined(separator: "\n")
        let resolved = resolveDates(text)
        return .init(date: resolved.date, dates: resolved.suggestions, words: rankWords(pages),
            hasText: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    static func extractPage(_ page: PDFPage) -> AnalysisPage {
        let fullText = page.string ?? ""
        let text = String(fullText.prefix(200_000))
        let attributed = page.attributedString
        let stylesAligned = attributed?.string == fullText
        let nsText = text as NSString
        let box = page.bounds(for: .cropBox)
        var lines: [AnalysisLine] = []
        // Keep dense pages bounded while retaining their text for date detection.
        var remainingWords = 4_000
        nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length), options: .byLines) { substring, range, _, stop in
            guard remainingWords > 0 else { stop.pointee = true; return }
            guard let substring, !substring.isEmpty else { return }
            let nsLine = substring as NSString
            let matches = Array(wordPattern.matches(in: substring, range: NSRange(location: 0, length: nsLine.length)).prefix(remainingWords))
            remainingWords -= matches.count
            var tokens = matches.map { match in
                AnalysisToken(text: nsLine.substring(with: match.range), size: nil, bold: false,
                    italic: false, confidence: 1, source: .embedded)
            }
            var topFraction: Double?
            for (index, match) in matches.enumerated() {
                let offset = range.location + match.range.location
                if offset < page.numberOfCharacters {
                    let bounds = page.characterBounds(at: offset)
                    if bounds.height.isFinite, bounds.height > 0 {
                        tokens[index].size = Double(bounds.height)
                        if topFraction == nil, box.height > 0 {
                            topFraction = Double((box.maxY - bounds.maxY) / box.height)
                        }
                    }
                }
                if stylesAligned, let attributed, offset < attributed.length,
                   let font = attributed.attribute(.font, at: offset, effectiveRange: nil) as? UIFont {
                    if tokens[index].size == nil { tokens[index].size = Double(font.pointSize) }
                    let traits = font.fontDescriptor.symbolicTraits
                    let name = font.fontName.lowercased()
                    tokens[index].bold = traits.contains(.traitBold) || name.contains("bold") || name.contains("heavy")
                    tokens[index].italic = traits.contains(.traitItalic) || name.contains("italic") || name.contains("oblique")
                }
            }
            lines.append(AnalysisLine(text: substring, tokens: tokens, topFraction: topFraction))
        }
        return AnalysisPage(text: text, lines: lines)
    }

    static func ocrLine(_ text: String, bounds: CGRect, pageHeight: CGFloat, confidence: Float) -> AnalysisLine {
        let size = Double(bounds.height * pageHeight)
        let usableSize = size.isFinite && size > 0 ? size : nil
        let tokens = tokens(in: text, source: .ocr).map { token in
            AnalysisToken(text: token.text, size: usableSize, bold: false, italic: false,
                confidence: confidence, source: .ocr)
        }
        return AnalysisLine(text: text, tokens: tokens, topFraction: Double(1 - bounds.maxY))
    }

    private static func lineKey(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func wordKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func tokens(in text: String, source: TextSource) -> [AnalysisToken] {
        let nsText = text as NSString
        return wordPattern.matches(in: text, range: NSRange(location: 0, length: nsText.length)).map { match in
            AnalysisToken(text: nsText.substring(with: match.range), size: nil, bold: false,
                italic: false, confidence: 1, source: source)
        }
    }

    private static func resolveDates(_ text: String) -> (date: DocumentDate, suggestions: [DateSuggestion]) {
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
        guard !candidates.isEmpty else { return (.fallback, []) }
        let top = candidates.map(\.score).max() ?? 0
        let best = candidates.filter { $0.score == top }.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.order < $1.order
        }
        let dates = Array(Set(best.map(\.value))).sorted(by: >)
        let ranked = Dictionary(grouping: candidates, by: \.value).map { value, matches in
            (suggestion: DateSuggestion(value: value, score: matches.map(\.score).max() ?? 0,
                isAmbiguous: matches.contains(where: \.ambiguous)),
             first: matches.map(\.order).min() ?? Int.max)
        }.sorted { lhs, rhs in
            if lhs.suggestion.score != rhs.suggestion.score { return lhs.suggestion.score > rhs.suggestion.score }
            if lhs.suggestion.value != rhs.suggestion.value { return lhs.suggestion.value > rhs.suggestion.value }
            if lhs.first != rhs.first { return lhs.first < rhs.first }
            return lhs.suggestion.value < rhs.suggestion.value
        }.map(\.suggestion)
        if dates.count == 1, !best.contains(where: \.ambiguous), let only = dates.first {
            return (.found(only), ranked)
        }
        return (.ambiguous(dates), ranked)
    }

    private static func validDate(year: Int, month: Int, day: Int) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        guard actual.year == year, actual.month == month, actual.day == day else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    // Do not hard-exclude document topics or field labels; ranking can demote boilerplate.
    private static let stopwords: Set<String> = Set("""
        the and for with from this that your you are was were have has had but not all can will would should one two three
        der die das den dem des ein eine einer eines einem und oder mit von vom zur zum aus auf bei für ist sind war wurden
        sie wir ihr ihre ihren nicht auch über unter durch nach vor bis als am im in an zu du de la le les et en un une
        page seite www http https com net org
        """.split(whereSeparator: \.isWhitespace).map(String.init))

    private struct SizeGroup: Hashable {
        var page: Int
        var source: TextSource
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private static func rankWords(_ pages: [AnalysisPage]) -> [RankedWord] {
        var counts: [String: (display: String, count: Int, bonus: Double, first: Int)] = [:]
        var order = 0
        var linePages: [String: Set<Int>] = [:]
        var sizesByGroup: [SizeGroup: [Double]] = [:]
        var sizesBySource: [TextSource: [Double]] = [:]
        for (pageIndex, page) in pages.enumerated() {
            for line in page.lines {
                let key = lineKey(line.text)
                if !key.isEmpty { linePages[key, default: []].insert(pageIndex) }
                for token in line.tokens {
                    guard let size = token.size, size.isFinite, size > 0, size < 1_000,
                          token.confidence >= 0.5 else { continue }
                    sizesByGroup[SizeGroup(page: pageIndex, source: token.source), default: []].append(size)
                    sizesBySource[token.source, default: []].append(size)
                }
            }
        }
        let groupMedians = sizesByGroup.compactMapValues(median)
        let sourceMedians = sizesBySource.compactMapValues(median)
        var countedRepeatedLines: Set<String> = []
        for (pageIndex, page) in pages.enumerated() {
            let pageBonus = 1.2 / (1 + 0.6 * Double(pageIndex))
            for (lineIndex, line) in page.lines.enumerated() {
                let normalizedLine = lineKey(line.text)
                if (linePages[normalizedLine]?.count ?? 0) > 1,
                   !countedRepeatedLines.insert(normalizedLine).inserted { continue }
                var wordsOnLine: Set<String> = []
                for token in line.tokens {
                    let display = token.text
                    let key = wordKey(display)
                    guard !stopwords.contains(key), display.count <= 36, wordsOnLine.insert(key).inserted else { continue }
                    let heading = pageIndex == 0 && lineIndex < 12 && (line.topFraction ?? 0) < 0.45 &&
                        line.tokens.count <= 10 ? 0.85 : 0
                    let footer = (line.topFraction ?? 0) > 0.85 ? -0.35 : 0
                    let uppercase = display.count > 3 && display == display.uppercased() ? 0.12 : 0
                    let group = SizeGroup(page: pageIndex, source: token.source)
                    let baseline = (sizesByGroup[group]?.count ?? 0) >= 4 ? groupMedians[group] : sourceMedians[token.source]
                    var sizeBonus = 0.0
                    if let size = token.size, let baseline, baseline > 0, token.confidence >= 0.5 {
                        sizeBonus = min(0.9, max(0, log2(size / baseline)) * 0.65)
                    }
                    let styleBonus = (token.bold ? 0.3 : 0) + (token.italic ? 0.08 : 0)
                    let bonus = pageBonus + heading + footer + uppercase + sizeBonus + styleBonus
                    if var item = counts[key] {
                        item.count += 1
                        item.bonus = max(item.bonus, bonus)
                        counts[key] = item
                    } else {
                        counts[key] = (display, 1, bonus, order)
                    }
                    order += 1
                }
            }
        }
        return counts.map { _, item in
            let lengthBonus = min(0.12, 0.01 * Double(max(0, item.display.count - 4)))
            return (word: RankedWord(text: item.display,
                score: 1 + min(0.75, log(Double(item.count)) * 0.45) + item.bonus + lengthBonus), first: item.first)
        }.sorted { a, b in
            if a.word.score != b.word.score { return a.word.score > b.word.score }
            if a.first != b.first { return a.first < b.first }
            return a.word.id < b.word.id
        }.prefix(30).map(\.word)
    }
}
