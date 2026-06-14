import SwiftUI

struct TopCommentOverlayView: View {
    let comment: DumpertComment?
    let isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            Spacer()

            if isVisible {
                HStack {
                    commentContent
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 60)
                .padding(.bottom, 20)
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: isVisible)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: comment?.id)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var commentContent: some View {
        if let comment {
            HStack(spacing: 16) {
                Image(systemName: "quote.opening")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.5))

                VStack(alignment: .leading, spacing: 6) {
                    Text(comment.displayContent.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .lineLimit(10)

                    HStack(spacing: 8) {
                        Text("@\(comment.authorUsername)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))

                        HStack(spacing: 3) {
                            Image(systemName: "hand.thumbsup.fill")
                                .font(.caption2)
                            Text("\(comment.kudosCount)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        .foregroundStyle(.dumpiGreen)
                    }
                }

            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.black.opacity(0.75))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .id(comment.id)
            .transition(.opacity)
            .accessibilityLabel(Text("Top reaguursel van \(comment.authorUsername): \(comment.displayContent)", comment: "Accessibility: top comment by author"))
        } else {
            HStack(spacing: 12) {
                Image(systemName: "text.bubble")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.5))
                Text("Geen reaguursels", comment: "No comments available")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.black.opacity(0.6))
            )
            .accessibilityLabel(Text("Geen reaguursels", comment: "No comments available"))
        }
    }
}
