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
        .background(Color.kudos(kudos))
        .cornerRadius(6)
        .accessibilityLabel(Text("\(formattedKudos) kudos", comment: "Kudos count label"))
    }

    private var formattedKudos: String { kudos.formattedCount }
}
