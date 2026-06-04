import Foundation

/// Parses the ISO 8601 timestamps the dumpert API emits into `Date`.
///
/// The `/latest` feed mixes several shapes within a single response:
///   - fractional seconds + "Z":  `2026-06-03T06:50:58.833Z` (2–6 digits observed)
///   - whole seconds + "Z":       `2026-06-02T15:14:00Z`
///   - numeric offset:            `2026-03-10T14:19:14+01:00`
///
/// The previous per-model parsers (`DateFormatter("yyyy-MM-dd'T'HH:mm:ssZ")`
/// with a bare `ISO8601DateFormatter()` fallback) covered only whole-second
/// timestamps, so every fractional-seconds item — the majority of the feed —
/// decoded to `nil` and fell into the wrong day section. `ISO8601DateFormatter`
/// with `.withFractionalSeconds` accepts a variable number of fractional digits;
/// a non-fractional formatter handles the remaining whole-second/offset strings.
enum DumpertDate {
    private nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private nonisolated(unsafe) static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Parse a dumpert API timestamp, or `nil` if it is missing/unparseable.
    static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return fractional.date(from: string) ?? plain.date(from: string)
    }
}

extension Date {
    /// Convenience initialiser around ``DumpertDate/parse(_:)`` for a known
    /// non-optional timestamp string. Returns `nil` when parsing fails.
    init?(dumpertAPIString string: String) {
        guard let date = DumpertDate.parse(string) else { return nil }
        self = date
    }
}
