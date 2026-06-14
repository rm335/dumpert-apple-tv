import SwiftUI

struct FullScreenImageView: View {
    let photo: Photo
    let repository: VideoRepository
    @Environment(\.dismiss) private var dismiss
    // `internal` (not `private`): the zoomControls extension lives in ZoomControlsView.swift.
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var loadFailed = false

    // Zoom & pan state (controlled via Siri Remote)
    @State var currentScale: CGFloat = 1.0
    @State private var offsetX: CGFloat = 0
    @State private var offsetY: CGFloat = 0
    // Lightbox opens to the image alone; Play/Pause reveals the chrome.
    @State var showOverlay = false

    // Top comment state
    @State private var topComments: [DumpertComment] = []
    @State private var currentCommentIndex = 0
    @State private var showTopComment = false
    @State private var topCommentCarouselTask: Task<Void, Never>?

    @FocusState private var isFocused: Bool

    let zoomStep: CGFloat = 0.5
    private let panStep: CGFloat = 100
    let minScale: CGFloat = 1.0
    let maxScale: CGFloat = 5.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView(String(localized: "Laden...", comment: "Loading indicator"))
            } else if loadFailed {
                VStack(spacing: 16) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Kon afbeelding niet laden", comment: "Error when image fails to load")
                        .foregroundStyle(.secondary)
                }
            } else if let image {
                imageContent(image)
            }

            // Overlay with title and info
            if showOverlay {
                overlay
            }

            // Top comment overlay
            TopCommentOverlayView(
                comment: topComments.isEmpty ? nil : topComments[currentCommentIndex],
                isVisible: showTopComment
            )

            // Zoom controls overlay (bottom right) — part of the chrome, so it
            // reveals and hides together with the title overlay via Play/Pause.
            if showOverlay && !isLoading && !loadFailed && image != nil {
                zoomControls
            }
        }
        .task {
            await loadImage()
            markAsWatched()
            await fetchAndShowTopComments()
        }
        .onDisappear {
            topCommentCarouselTask?.cancel()
            topCommentCarouselTask = nil
        }
        .onExitCommand {
            if currentScale > minScale {
                withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) {
                    resetZoom()
                }
            } else {
                dismiss()
            }
        }
        .onPlayPauseCommand {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                showOverlay.toggle()
            }
        }
    }

    @ViewBuilder
    private func imageContent(_ uiImage: UIImage) -> some View {
        let base = Image(uiImage: uiImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(currentScale)
            .offset(x: offsetX, y: offsetY)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(photo.title)
            .focusable()
            .focused($isFocused)
            .onAppear { isFocused = true }

        // Only intercept move commands when zoomed in;
        // at 1x the focus engine can navigate to the zoom buttons
        if currentScale > minScale {
            base.onMoveCommand { direction in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    switch direction {
                    case .left: offsetX += panStep
                    case .right: offsetX -= panStep
                    case .up: offsetY += panStep
                    case .down: offsetY -= panStep
                    @unknown default: break
                    }
                }
            }
        } else {
            base
        }
    }

    // MARK: - Helpers

    private func loadImage() async {
        guard let url = photo.imageURL ?? photo.thumbnailURL else {
            isLoading = false
            loadFailed = true
            return
        }

        do {
            let uiImage = try await ImageCacheService.shared.image(for: url)
            self.image = uiImage
            isLoading = false
        } catch {
            isLoading = false
            loadFailed = true
        }
    }

    private func markAsWatched() {
        repository.updateWatchProgress(
            videoId: photo.id,
            watchedSeconds: 1,
            totalSeconds: 1
        )
    }

    private func fetchAndShowTopComments() async {
        let mode = repository.settings.topCommentMode
        guard mode != .off else { return }
        do {
            let allComments = try await repository.fetchTopComments(for: photo.id)
            switch mode {
            case .off:
                topComments = []
            case .single:
                topComments = allComments.isEmpty ? [] : [allComments[0]]
            case .all:
                topComments = allComments.filter { $0.kudosCount >= 20 }
            }
        } catch {
            topComments = []
        }

        guard !topComments.isEmpty else { return }

        currentCommentIndex = 0
        withAnimation(reduceMotion ? nil : .default) { showTopComment = true }

        // Carousel: show each comment for dynamic duration, 5 second gap between
        let speed = repository.settings.readingSpeed
        topCommentCarouselTask = Task {
            // Show first comment for dynamic duration based on text length
            let firstDuration = speed.readingDuration(for: topComments[0].displayContent)
            try? await Task.sleep(for: .seconds(firstDuration))
            withAnimation(reduceMotion ? nil : .default) { showTopComment = false }

            // Cycle through remaining comments
            var index = 1
            while index < topComments.count {
                // 5 second gap between comments
                try? await Task.sleep(for: .seconds(5))
                withAnimation(reduceMotion ? nil : .default) {
                    currentCommentIndex = index
                    showTopComment = true
                }

                // Show comment for dynamic duration based on text length
                let duration = speed.readingDuration(for: topComments[index].displayContent)
                try? await Task.sleep(for: .seconds(duration))
                withAnimation(reduceMotion ? nil : .default) { showTopComment = false }
                index += 1
            }
        }
    }

    func resetZoom() {
        currentScale = minScale
        offsetX = 0
        offsetY = 0
    }
}
