import SwiftUI

extension Color {
    /// Dumpert brand green (#65B32E)
    static let dumpiGreen = Color(red: 0.396, green: 0.702, blue: 0.180)

    /// Darker variant for backgrounds/subtle accents
    static let dumpiGreenDark = Color(red: 0.30, green: 0.55, blue: 0.12)

    /// Semantic error / destructive / NSFW color (systemRed). The single source so
    /// red can't drift across the offline banner, NSFW badge and destructive rows.
    static let dumpiError = Color(.systemRed)

    /// Sentiment color for a kudos score — the single source for the kudos ramp,
    /// shared by the video card meta, the kudos badge and the photo overlay so the
    /// thresholds can't drift: brand green ≥ 100, neutral gray 0–99, red when negative.
    static func kudos(_ score: Int) -> Color {
        if score >= 100 { return .dumpiGreen }
        if score >= 0 { return Color(.systemGray) }
        return Color(.systemRed)
    }
}

extension ShapeStyle where Self == Color {
    /// Dumpert brand green
    static var dumpiGreen: Color { .dumpiGreen }
}
