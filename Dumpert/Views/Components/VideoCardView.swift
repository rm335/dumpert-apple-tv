import SwiftUI

struct VideoCardView: View {
    let item: MediaItem
    let isWatched: Bool
    let progress: Double
    var isFocused: Bool = false
    /// Suppresses the focus video preview while a full-screen player (or photo
    /// viewer) is presented over the grid. A `.fullScreenCover` keeps this card
    /// mounted and, on tvOS, retains its `@FocusState` for restoration — so the
    /// preview's looping `AVPlayer` would otherwise keep decoding behind the
    /// active player and starve its audio render thread (stuttering audio while
    /// the foreground video stays smooth). Setting this true tears the preview
    /// player down for the duration of playback.
    var suspendPreview: Bool = false
    var thumbnailPreviewEnabled: Bool = true
    var smartThumbnailsEnabled: Bool = true
    /// Optional extra badge (e.g. the Classics vintage year) rendered bottom-leading
    /// on the thumbnail, coordinated with the other corner badges.
    var cornerBadge: String? = nil

    @State private var showPreview = false
    @State private var upgradedThumbnail: UIImage?
    @State private var upgradedFaceCenter: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @State private var upgradeAnimating = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption2) private var metaIconSize: CGFloat = 9

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail
            ZStack {
                ZStack {
                    FaceCenteredThumbnailView(url: item.thumbnailURL)

                    if let upgradedThumbnail {
                        Color.clear
                            .aspectRatio(16/9, contentMode: .fit)
                            .overlay {
                                GeometryReader { geo in
                                    let imgSize = upgradedThumbnail.size
                                    let scale = max(
                                        geo.size.width / imgSize.width,
                                        geo.size.height / imgSize.height
                                    )
                                    let scaledW = imgSize.width * scale
                                    let scaledH = imgSize.height * scale
                                    let offsetX = clampedOffset(face: upgradedFaceCenter.x, scaled: scaledW, container: geo.size.width)
                                    let offsetY = clampedOffset(face: upgradedFaceCenter.y, scaled: scaledH, container: geo.size.height)

                                    Image(uiImage: upgradedThumbnail)
                                        .resizable()
                                        .frame(width: scaledW, height: scaledH)
                                        .offset(x: offsetX, y: offsetY)
                                }
                            }
                            .clipped()
                            .scaleEffect(upgradeAnimating ? 1.0 : 1.03)
                            .transition(.opacity)
                    }
                }
                .brightness(isFocused ? 0.05 : 0)
                .saturation(isFocused ? 1.15 : 1.0)
                .accessibilityHidden(true)

                // Video preview overlay (max 10% of duration, minimum 10s)
                if showPreview, let streamURL = item.streamURL {
                    VideoPreviewView(
                        url: streamURL,
                        maxDuration: previewMaxDuration
                    )
                    .transition(.opacity)
                }

                // Top leading: NSFW label and mute indicator
                HStack(spacing: 4) {
                    if item.isNSFW {
                        Text("NSFW")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.dumpiError)
                            .cornerRadius(4)
                    }

                    if showPreview {
                        Image(systemName: "speaker.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .modifier(GlassPillModifier())
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(6)

                // Watched badge - top trailing
                if isWatched {
                    WatchedBadgeView()
                }

                // Duration pill or photo icon - bottom trailing (hidden during preview)
                if !showPreview {
                    if case .video(let video) = item, video.duration > 0 {
                        Text(video.duration.formattedDuration)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .modifier(GlassPillModifier())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(6)
                    } else if item.isPhoto {
                        Image(systemName: "photo.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .modifier(GlassPillModifier())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(6)
                    }
                }

                // Optional corner badge (e.g. Classics year) — bottom-leading,
                // coordinated with the bottom-trailing duration pill.
                if let cornerBadge, !showPreview {
                    Text(cornerBadge)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .modifier(GlassPillModifier())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(6)
                }

                // Progress bar at bottom (only for videos)
                if item.isVideo && progress > 0 && !isWatched {
                    GeometryReader { geo in
                        VStack {
                            Spacer()
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(.white.opacity(0.15))
                                    .frame(height: 5)
                                Rectangle()
                                    .fill(Color.dumpiGreen)
                                    .frame(width: geo.size.width * progress, height: 5)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            // Green brand shadow on focus; scale + parallax handled by .buttonStyle(.card)
            .shadow(color: .dumpiGreen.opacity(isFocused ? 0.3 : 0), radius: 15)
            .animation(reduceMotion ? nil : .dumpiCard, value: isFocused)

            // Info below thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(isWatched ? .secondary : .primary)

                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: item.kudosTotal >= 0 ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                            .font(.system(size: metaIconSize))
                        Text(formattedKudos)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .monospacedDigit()
                    }
                    .foregroundStyle(Color.kudos(item.kudosTotal))

                    if item.viewsTotal > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: metaIconSize))
                            Text(item.viewsTotal.formattedCount)
                                .font(.caption2)
                                .monospacedDigit()
                        }
                        .foregroundStyle(.secondary)
                    }

                    if let date = item.date {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(date.relativeString)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .task(id: previewActive) {
            if previewActive {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .dumpiStandard) {
                    showPreview = true
                }
            } else if showPreview {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    showPreview = false
                }
            }
        }
        .task(id: deferThumbnailUpgrade) {
            guard smartThumbnailsEnabled, item.isVideo,
                  case .video(let video) = item,
                  video.streamURL != nil else { return }

            // Check disk cache first — cheap, always allowed.
            if let cached = await ThumbnailUpgradeService.shared.cachedImage(for: item.id) {
                let center = await detectFaceCenter(in: cached)
                applyUpgrade(image: cached, faceCenter: center)
                return
            }

            // Frame extraction spins up a second AVPlayer/decoder. Never run it
            // while a player is active: a long upgrade queue keeps decoding behind
            // the cover and starves the foreground player's audio render thread —
            // stuttering sound while the video itself stays smooth. Gating on
            // `deferThumbnailUpgrade` cancels any in-flight extraction (this .task
            // restarts) and re-runs once playback ends.
            guard !deferThumbnailUpgrade else { return }

            // Run upgrade analysis in background
            if let upgraded = await ThumbnailUpgradeService.shared.upgradeIfNeeded(
                itemId: item.id,
                thumbnailURL: item.thumbnailURL,
                streamURL: video.streamURL,
                duration: video.duration
            ) {
                let center = await detectFaceCenter(in: upgraded)
                applyUpgrade(image: upgraded, faceCenter: center)
            }
        }
    }

    /// Whether the focus video preview should be running. Gated on both the
    /// per-section suspend flag and the global `PlaybackCoordinator` so the
    /// preview's `AVPlayer` is torn down whenever *any* primary player is live —
    /// including deep-link / Top Shelf videos and PiP, which `suspendPreview`
    /// (driven by this section's `selectedVideo`) never sees. A live preview
    /// decoder behind the player starves its audio render thread.
    private var previewActive: Bool {
        isFocused
            && item.isVideo
            && item.streamURL != nil
            && thumbnailPreviewEnabled
            && !suspendPreview
            && !PlaybackCoordinator.shared.isPlaybackActive
    }

    /// Whether smart-thumbnail frame extraction must stand down. Same reasoning
    /// as `previewActive`: the extractor spins up a second decoder, so defer it
    /// while a player is active (per-section *or* via any other playback path).
    /// Used as the `.task` id so extraction re-runs once playback ends.
    private var deferThumbnailUpgrade: Bool {
        suspendPreview || PlaybackCoordinator.shared.isPlaybackActive
    }

    /// Preview shows at most 10% of the video, but never less than 10 seconds.
    private var previewMaxDuration: TimeInterval? {
        let duration = item.duration
        guard duration > 0 else { return nil }
        return max(10, Double(duration) * 0.10)
    }

    private var formattedKudos: String { item.kudosTotal.formattedCount }

    private var accessibilityDescription: String {
        var parts: [String] = []
        if item.isNSFW {
            parts.append("NSFW")
        }
        parts.append(item.title)
        if item.isVideo {
            parts.append(String(localized: "Video", comment: "Accessibility: content type video"))
            if item.duration > 0 {
                parts.append(item.duration.formattedDuration)
            }
        } else {
            parts.append(String(localized: "Foto", comment: "Accessibility: content type photo"))
        }
        parts.append(String(localized: "\(formattedKudos) kudos", comment: "Kudos count label"))
        if item.viewsTotal > 0 {
            parts.append(String(localized: "\(item.viewsTotal.formattedCount) views", comment: "Views count label"))
        }
        if isWatched {
            parts.append(String(localized: "Bekeken", comment: "Accessibility: video has been watched"))
        } else if progress > 0 {
            parts.append(String(localized: "\(Int(progress * 100))% bekeken", comment: "Accessibility: percentage of video watched"))
        }
        return parts.joined(separator: ", ")
    }

    /// Applies the upgraded thumbnail with a crossfade + subtle scale-down animation.
    private func applyUpgrade(image: UIImage, faceCenter: CGPoint) {
        upgradedFaceCenter = faceCenter
        upgradedThumbnail = image
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.7)) {
            upgradeAnimating = true
        }
    }

    private func detectFaceCenter(in image: UIImage) async -> CGPoint {
        guard let cgImage = image.cgImage else { return CGPoint(x: 0.5, y: 0.5) }
        return await FaceDetectionService.shared.faceCenter(for: URL(string: "upgraded://\(item.id)")!, in: cgImage)
    }

    /// Compute offset to center face in container, clamped so no gaps appear.
    private func clampedOffset(face: CGFloat, scaled: CGFloat, container: CGFloat) -> CGFloat {
        let facePos = face * scaled
        let idealOffset = container / 2 - facePos
        let minOffset = container - scaled
        return min(0, max(minOffset, idealOffset))
    }

}

/// Applies Liquid Glass on tvOS 26+, falls back to dark pill on older versions.
struct GlassPillModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(tvOS 26, *) {
            content
                .glassEffect(in: RoundedRectangle(cornerRadius: 4))
        } else {
            content
                .background(.black.opacity(0.75))
                .cornerRadius(4)
        }
    }
}
