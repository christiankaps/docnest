import Foundation

enum StringNormalization {
    static func collapsedWhitespace(_ rawValue: String) -> String {
        rawValue
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func nonEmptyCollapsedWhitespace<E: Error>(
        _ rawValue: String,
        emptyError: @autoclosure () -> E
    ) throws -> String {
        let collapsed = collapsedWhitespace(rawValue)
        guard !collapsed.isEmpty else {
            throw emptyError()
        }
        return collapsed
    }
}
