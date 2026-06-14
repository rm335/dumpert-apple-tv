import SwiftUI

/// Shimmer animation modifier for skeleton loading states.
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -0.3
    @State private var isActive = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let leading = max(0, min(phase - 0.3, 1))
        let center = max(0, min(phase, 1))
        let trailing = max(0, min(phase + 0.3, 1))
        content
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: leading),
                        .init(color: Color.dumpiGreen.opacity(0.10), location: center),
                        .init(color: .clear, location: trailing)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipped()
            }
            .onAppear {
                isActive = true
                withAnimation(reduceMotion ? nil : .linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.3
                }
            }
            .onDisappear {
                isActive = false
                withAnimation(.linear(duration: 0)) { phase = -0.3 }
            }
    }
}

extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Skeleton Card

/// Matches the exact layout of VideoCardView: 16:9 thumbnail + title (2 lines) + kudos/date row.
private struct SkeletonCardView: View {
    /// Stable index to vary the second title line width without re-randomizing on each render.
    var index: Int = 0

    /// Varied widths for the second title line, keyed by index.
    private var secondLineWidth: CGFloat {
        let widths: [CGFloat] = [100, 75, 120, 60, 90, 110, 80, 95]
        return widths[abs(index) % widths.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail — same as FaceCenteredThumbnailView (16:9)
            ZStack {
                Color.white.opacity(0.05)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .shimmering()

                // Duration pill placeholder — bottom trailing, matches VideoCardView
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.06))
                    .frame(width: 42, height: 16)
                    .shimmering()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(6)
            }
            .clipped()

            // Info — matches VideoCardView info section
            VStack(alignment: .leading, spacing: 4) {
                // Title line 1: .caption, full width
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(0.08))
                    .frame(height: 12)
                    .shimmering()

                // Title line 2: .caption, varied width per card
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(0.05))
                    .frame(width: secondLineWidth, height: 12)

                // Kudos icon + count + bullet + date row: .caption2
                HStack(spacing: 6) {
                    // Thumbs-up icon placeholder
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.06))
                        .frame(width: 9, height: 9)

                    // Kudos count
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.06))
                        .frame(width: 32, height: 9)

                    Circle()
                        .fill(.white.opacity(0.04))
                        .frame(width: 3, height: 3)

                    // Relative date
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.06))
                        .frame(width: 55, height: 9)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .cornerRadius(12)
    }
}

// MARK: - Skeleton Grid

/// Matches CategorySectionView / ClassicsSectionView grid layout.
struct SkeletonGridView: View {
    let columnCount: Int

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 30), count: columnCount),
            spacing: 35
        ) {
            ForEach(0..<columnCount * 2, id: \.self) { index in
                SkeletonCardView(index: index)
            }
        }
        .padding(.horizontal, 50)
    }
}

// MARK: - Skeleton Row

/// Matches ToppersSectionView mediaRow: title + horizontal scroll of cards.
struct SkeletonRowView: View {
    let cardWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section title placeholder — matches .title3.bold
            RoundedRectangle(cornerRadius: 4)
                .fill(.white.opacity(0.08))
                .frame(width: 160, height: 18)
                .shimmering()

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 30) {
                    ForEach(0..<5, id: \.self) { index in
                        SkeletonCardView(index: index)
                            .frame(width: cardWidth)
                    }
                }
                .padding(.vertical, 20)
            }
            .scrollClipDisabled()
        }
    }
}
