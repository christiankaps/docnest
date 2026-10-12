import Foundation

enum BuildInfo {
    static let timestamp: Date? = {
        guard let url = Bundle.main.url(forResource: "PdfPipeBuildInfo", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let properties = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let value = (properties as? [String: String])?["BuildTimestampUTC"] else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }()

    static var displayDate: String {
        guard let timestamp else { return "Build date unavailable" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = .autoupdatingCurrent
        let zone = formatter.timeZone.abbreviation(for: timestamp) ?? "UTC"
        return "\(formatter.string(from: timestamp)) \(zone)"
    }
}
