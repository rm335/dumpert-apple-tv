import SwiftUI

/// Full-screen blurred background image with dark gradient overlay.
/// Uses a double-buffer (ping-pong) technique for smooth crossfade transitions.
///
/// Reference values modeled after Netflix/Disney+ on tvOS:
/// - Blur radius: 20pt (shapes recognizable, details hidden)
/// - Saturation: 0.8 (slightly muted colors)
/// - Gradient: strong bottom darkening for content readability,
///   moderate top darkening for tab bar area
struct ImmersiveBackgroundView: View {
    // Read the active URL from the environment object HERE rather than taking it
    // as a parameter from ContentView. Under @Observable, whoever reads
    // `backgroundState.activeURL` in its body is invalidated when it changes —
    // and activeURL changes constantly (every focus hop drives currentImageURL).
    // Reading it in ContentView recomputed the ZStack that hosts the TabView's
    // UITabBarController on every focus move, which can reconcile/free the flip
    // transition's destination view mid-animation and crash in
    // setToViewXFlippedScreenShot:. Confining the read here keeps the tab-bar
    // parent stable; only this background view redraws.
    // ponytail: env read, not a param — that's the whole fix.
    @Environment(ImmersiveBackgroundState.self) private var backgroundState

    // Double-buffer for crossfade: alternate between A and B layers
    @State private var imageA: UIImage?
    @State private var imageB: UIImage?
    @State private var showingA = true
    @State private var loadedURL: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if let imageA {
                    backgroundLayer(imageA, size: geo.size)
                        .opacity(showingA ? 1 : 0)
                }

                if let imageB {
                    backgroundLayer(imageB, size: geo.size)
                        .opacity(showingA ? 0 : 1)
                }

                gradientOverlay
            }
        }
        .ignoresSafeArea()
        .task(id: backgroundState.activeURL) {
            await loadImage(backgroundState.activeURL)
        }
    }

    // MARK: - Image Layer

    private func backgroundLayer(_ image: UIImage, size: CGSize) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size.width, height: size.height)
            .blur(radius: 20)
            .saturation(0.8)
            .clipped()
    }

    // MARK: - Netflix/Disney+ Gradient Overlay

    private var gradientOverlay: some View {
        ZStack {
            // Primary gradient: dark bottom for content rows, lighter middle, moderate top for tab bar
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.9), location: 0),
                    .init(color: .black.opacity(0.5), location: 0.35),
                    .init(color: .black.opacity(0.3), location: 0.6),
                    .init(color: .black.opacity(0.5), location: 1.0)
                ],
                startPoint: .bottom,
                endPoint: .top
            )

            // Subtle overall dimming for consistent readability
            Color.black.opacity(0.2)
        }
    }

    // MARK: - Image Loading with Crossfade

    private func loadImage(_ imageURL: URL?) async {
        guard let url = imageURL, url != loadedURL else { return }

        guard let image = try? await ImageCacheService.shared.image(for: url) else { return }

        loadedURL = url

        // Calm by default; instant swap under Reduce Motion (no crossfade).
        let crossfade: Animation? = reduceMotion ? nil : .easeInOut(duration: 0.6)

        if showingA {
            // Currently showing A → load into B, crossfade to B
            imageB = image
            withAnimation(crossfade) {
                showingA = false
            }
        } else {
            // Currently showing B → load into A, crossfade to A
            imageA = image
            withAnimation(crossfade) {
                showingA = true
            }
        }
    }
}
