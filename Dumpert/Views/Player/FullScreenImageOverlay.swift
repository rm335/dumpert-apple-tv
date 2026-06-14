import SwiftUI

extension FullScreenImageView {
    @ViewBuilder
    var overlay: some View {
        if #available(tvOS 26, *) {
            glassOverlay
        } else {
            gradientOverlay
        }
    }

    @available(tvOS 26, *)
    var glassOverlay: some View {
        VStack {
            // Top bar - glass panel
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(photo.title)
                        .font(.headline)
                        .lineLimit(2)
                    if !photo.descriptionText.isEmpty {
                        Text(photo.descriptionText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
            .glassEffect(in: UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 0,
                    bottomLeading: 16,
                    bottomTrailing: 16,
                    topTrailing: 0
                )
            ))

            Spacer()

            // Bottom info - glass panel
            kudosInfoBar
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
                .glassEffect(in: UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: 16,
                        bottomLeading: 0,
                        bottomTrailing: 0,
                        topTrailing: 16
                    )
                ))
        }
    }

    var gradientOverlay: some View {
        VStack {
            // Top bar
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(photo.title)
                        .font(.headline)
                        .lineLimit(2)
                    if !photo.descriptionText.isEmpty {
                        Text(photo.descriptionText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 40)
            .padding(.top, 30)
            .background(
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.7), location: 0),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )

            Spacer()

            // Bottom info
            kudosInfoBar
                .padding(.horizontal, 40)
                .padding(.bottom, 30)
                .background(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.7), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                )
        }
    }

    var kudosInfoBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: photo.kudosTotal >= 0 ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                    .font(.caption)
                Text(formattedKudos)
                    .font(.caption)
                    .fontWeight(.bold)
                    .monospacedDigit()
            }
            .foregroundStyle(Color.kudos(photo.kudosTotal))

            if photo.viewsTotal > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "eye.fill")
                        .font(.caption)
                    Text(photo.viewsTotal.formattedCount)
                        .font(.caption)
                        .fontWeight(.bold)
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("\(photo.viewsTotal.formattedCount) views", comment: "Views count label"))
            }

            if let date = photo.date {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(date.relativeString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    var formattedKudos: String { photo.kudosTotal.formattedCount }
}
