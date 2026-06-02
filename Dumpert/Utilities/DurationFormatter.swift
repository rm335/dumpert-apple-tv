import Foundation

extension Int {
    var formattedDuration: String {
        let minutes = self / 60
        let secs = self % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Abbreviated count for kudos/views badges, e.g. 1_234 -> "1.2k", 1_200_000 -> "1.2M".
    /// Preserves the sign and keeps the existing "%.1fk" formatting used across the app.
    var formattedCount: String {
        if abs(self) >= 1_000_000 {
            return String(format: "%.1fM", Double(self) / 1_000_000)
        }
        if abs(self) >= 1_000 {
            return String(format: "%.1fk", Double(self) / 1_000)
        }
        return "\(self)"
    }
}
