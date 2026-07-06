import Foundation

extension Int {
    var formattedDuration: String {
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        let secs = self % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Abbreviated count for kudos/views badges, e.g. 1_234 -> "1,2k" (nl) /
    /// "1.2k" (en), 1_200_000 -> "1,2M". Locale-aware decimal separator;
    /// preserves the sign.
    var formattedCount: String {
        if abs(self) >= 1_000_000 {
            return String(format: "%.1fM", locale: .current, Double(self) / 1_000_000)
        }
        if abs(self) >= 1_000 {
            return String(format: "%.1fk", locale: .current, Double(self) / 1_000)
        }
        return "\(self)"
    }
}
