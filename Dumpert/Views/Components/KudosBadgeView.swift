import SwiftUI

struct KudosBadgeView: View {
    let kudos: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: kudos >= 0 ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                .font(.caption)
            Text(formattedKudos)
                .font(.caption)
                .fontWeight(.bold)
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(kudosColor)
        .cornerRadius(6)
        .accessibilityLabel(Text("\(formattedKudos) kudos", comment: "Kudos count label"))
    }

    private var formattedKudos: String {
        if abs(kudos) >= 1000 {
            return String(format: "%.1fk", Double(kudos) / 1000)
        }
        return "\(kudos)"
    }

    private var kudosColor: Color {
        if kudos >= 100 { return .dumpiGreen }
        if kudos >= 0 { return Color(.systemGray).opacity(0.7) }
        return Color(.systemRed)
    }
}
