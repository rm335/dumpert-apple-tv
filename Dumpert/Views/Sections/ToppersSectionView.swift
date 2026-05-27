import SwiftUI

struct ToppersSectionView: View {
    @Environment(VideoRepository.self) private var repository
    @Environment(ImmersiveBackgroundState.self) private var backgroundState
    @State private var selectedVideo: Video?
    @State private var selectedPhoto: Photo?
    @State private var toastMessage: String?
    @State private var heroIndex = 0
    @State private var heroAutoRotate = true
    @State private var resumeAutoRotateTask: Task<Void, Never>?
    @FocusState private var focusedItem: String?

    private var heroItems: [MediaItem] {
        Array(repository.filteredItems(repository.hotshiz).prefix(5))
    }

    private var safeHeroIndex: Int {
        heroItems.isEmpty ? 0 : heroIndex % heroItems.count
    }

    var body: some View {
        ZStack {
            if repository.isLoading && repository.hotshiz.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 40) {
                        // Skeleton hero — matches heroCarousel layout
                        ZStack(alignment: .bottomLeading) {
                            Color.white.opacity(0.05)
                                .shimmering()

                            // Info overlay placeholder
                            VStack(alignment: .leading, spacing: 8) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.white.opacity(0.1))
                                    .frame(width: 320, height: 22)
                                    .shimmering()
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.white.opacity(0.06))
                                    .frame(width: 200, height: 14)
                                HStack(spacing: 10) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(.white.opacity(0.06))
                                        .frame(width: 60, height: 12)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(.white.opacity(0.06))
                                        .frame(width: 40, height: 12)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(.white.opacity(0.06))
                                        .frame(width: 70, height: 12)
                                }
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 16)

                            // Page indicators placeholder
                            HStack(spacing: 8) {
                                ForEach(0..<5, id: \.self) { i in
                                    Circle()
                                        .fill(i == 0 ? Color.white.opacity(0.3) : .white.opacity(0.1))
                                        .frame(width: 10, height: 10)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(20)
                        }
                        .aspectRatio(16/6, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 24))

                        SkeletonRowView(cardWidth: repository.settings.tileSize.horizontalCardWidth)
                        SkeletonRowView(cardWidth: repository.settings.tileSize.horizontalCardWidth)
                        SkeletonRowView(cardWidth: repository.settings.tileSize.horizontalCardWidth)
                    }
                    .padding(.horizontal, 50)
                    .padding(.vertical, 30)
                }
                .transition(.opacity)
            } else if let error = repository.error, repository.hotshiz.isEmpty {
                errorView(message: error)
                    .transition(.opacity)
            } else if !repository.isLoading && repository.hotshiz.isEmpty
                        && repository.topWeek.isEmpty {
                EmptyStateView(
                    title: "Geen video's",
                    systemImage: "video.slash",
                    description: "Kon geen video's laden. Controleer je internetverbinding."
                ) {
                    Task { await repository.refreshAll() }
                }
                .transition(.opacity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 40) {
                        // Hero Carousel
                        if !heroItems.isEmpty {
                            heroCarousel
                        }

                        let trendingItems = repository.filteredItems(repository.hotshiz)
                        let weekItems = repository.filteredItems(repository.topWeek)
                        let monthItems = repository.filteredItems(repository.topMonth)

                        mediaRow(title: "Trending Nu", items: trendingItems)
                        mediaRow(title: "Top Deze Week", items: weekItems)
                        mediaRow(title: "Top Deze Maand", items: monthItems)
                    }
                    .padding(.horizontal, 50)
                    .padding(.vertical, 30)
                }
                .refreshable {
                    await repository.refreshAll()
                }
            }
        }
        .animation(.easeOut(duration: 0.3), value: repository.isLoading)
        .fullScreenCover(item: $selectedVideo) { video in
            let videoPlaylist = repository.filteredItems(repository.hotshiz).compactMap { item -> Video? in
                if case .video(let v) = item { return v }
                return nil
            }
            VideoPlayerView(viewModel: VideoPlayerViewModel(
                video: video,
                playlist: videoPlaylist,
                repository: repository
            ))
        }
        .fullScreenCover(item: $selectedPhoto) { photo in
            FullScreenImageView(photo: photo, repository: repository)
        }
        .toast(message: $toastMessage)
        .task {
            if !heroItems.isEmpty {
                backgroundState.update(for: heroItems[safeHeroIndex])
            }
        }
        .onChange(of: heroIndex) { _, newIndex in
            guard newIndex < heroItems.count, focusedItem == nil else { return }
            Task { @MainActor in
                backgroundState.update(for: heroItems[newIndex])
            }
        }
        .onChange(of: focusedItem) { _, newId in
            Task { @MainActor in
                if let id = newId {
                    let allItems = repository.filteredItems(repository.hotshiz)
                        + repository.filteredItems(repository.topWeek)
                        + repository.filteredItems(repository.topMonth)
                    if let item = allItems.first(where: { $0.id == id }) {
                        backgroundState.update(for: item)
                    }
                } else if !heroItems.isEmpty {
                    backgroundState.update(for: heroItems[safeHeroIndex])
                }
            }
        }
    }

    @ViewBuilder
    private func mediaRow(title: LocalizedStringKey, items: [MediaItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitleView(title)
                    .font(.title3)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 50) {
                        ForEach(items) { item in
                            Button {
                                item.present(selectedVideo: $selectedVideo, selectedPhoto: $selectedPhoto)
                            } label: {
                                VideoCardView(
                                    item: item,
                                    isWatched: repository.isWatched(item.id),
                                    progress: repository.progressFor(item.id),
                                    isFocused: focusedItem == item.id,
                                    thumbnailPreviewEnabled: repository.settings.thumbnailPreviewEnabled,
                                    smartThumbnailsEnabled: repository.settings.smartThumbnailsEnabled
                                )
                            }
                            .buttonStyle(.card)
                            .frame(width: repository.settings.tileSize.horizontalCardWidth)
                            .focused($focusedItem, equals: item.id)
                            .videoContextMenu(item: item, repository: repository, toastMessage: $toastMessage)
                        }
                    }
                    .padding(.vertical, 20)
                }
                .scrollClipDisabled()
            }
        }
    }

    // MARK: - Hero Carousel

    private var heroCarousel: some View {
        Button {
            heroItems[safeHeroIndex].present(selectedVideo: $selectedVideo, selectedPhoto: $selectedPhoto)
        } label: {
            ZStack(alignment: .bottomLeading) {
                // All hero thumbnails stacked, crossfading via opacity
                ZStack {
                    ForEach(Array(heroItems.enumerated()), id: \.element.id) { index, item in
                        FaceCenteredThumbnailView(
                            url: item.thumbnailURL,
                            useIntrinsicAspectRatio: false
                        )
                        .clipped()
                        .opacity(index == safeHeroIndex ? 1 : 0)
                    }
                }

                // Info overlay crossfades with the thumbnail
                heroInfoOverlay(for: heroItems[safeHeroIndex])
                    .id(heroItems[safeHeroIndex].id)
                    .transition(.asymmetric(
                        insertion: .offset(y: 12).combined(with: .opacity),
                        removal: .opacity
                    ))

                // Page indicators
                if heroItems.count > 1 {
                    pageIndicators
                }
            }
            .aspectRatio(16/6, contentMode: .fit)
            .cornerRadius(24)
            .animation(.spring(duration: 0.7, bounce: 0.15), value: safeHeroIndex)
        }
        .buttonStyle(.card)
        .onMoveCommand { direction in
            switch direction {
            case .left:
                heroAutoRotate = false
                withAnimation(.spring(duration: 0.7, bounce: 0.15)) {
                    heroIndex = (heroIndex - 1 + heroItems.count) % heroItems.count
                }
                resumeAutoRotateAfterDelay()
            case .right:
                heroAutoRotate = false
                withAnimation(.spring(duration: 0.7, bounce: 0.15)) {
                    heroIndex = (heroIndex + 1) % heroItems.count
                }
                resumeAutoRotateAfterDelay()
            default:
                break
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(
            "\(heroItems[safeHeroIndex].title), item \(safeHeroIndex + 1) van \(heroItems.count)",
            comment: "Accessibility label for hero carousel item position"
        ))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                heroIndex = (heroIndex + 1) % heroItems.count
            case .decrement:
                heroIndex = (heroIndex - 1 + heroItems.count) % heroItems.count
            @unknown default:
                break
            }
        }
        .onChange(of: heroItems.count) {
            if heroIndex >= heroItems.count && !heroItems.isEmpty {
                heroIndex = 0
            }
        }
        .task(id: heroItems.count) {
            guard heroItems.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                if heroAutoRotate {
                    heroIndex = (heroIndex + 1) % heroItems.count
                }
            }
        }
    }

    private var pageIndicators: some View {
        HStack(spacing: 10) {
            if !heroAutoRotate {
                Image(systemName: "pause.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                    .transition(.scale.combined(with: .opacity))
            }
            Text("\(safeHeroIndex + 1) / \(heroItems.count)")
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .animation(.smooth(duration: 0.3), value: heroAutoRotate)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(20)
    }

    @ViewBuilder
    private func heroInfoOverlay(for hero: MediaItem) -> some View {
        let infoContent = VStack(alignment: .leading, spacing: 8) {
            Text(hero.title)
                .font(.title2)
                .fontWeight(.bold)
            if !hero.descriptionText.isEmpty {
                Text(hero.descriptionText)
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.8))
            }
            HStack(spacing: 10) {
                KudosBadgeView(kudos: hero.kudosTotal)
                if hero.isVideo && hero.duration > 0 {
                    Text(hero.duration.formattedDuration)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.7))
                }
                if hero.isPhoto {
                    Image(systemName: "photo.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                if let date = hero.date {
                    Text(date.relativeString)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }

        if #available(tvOS 26, *) {
            infoContent
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(in: UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: 0,
                        bottomLeading: 20,
                        bottomTrailing: 20,
                        topTrailing: 0
                    )
                ))
        } else {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.3),
                        .init(color: .black.opacity(0.9), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                infoContent
                    .padding(36)
            }
        }
    }

    private func resumeAutoRotateAfterDelay() {
        resumeAutoRotateTask?.cancel()
        resumeAutoRotateTask = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            heroAutoRotate = true
        }
    }

    private func errorView(message: String) -> some View {
        EmptyStateView(
            title: "Er ging iets mis",
            systemImage: "exclamationmark.triangle",
            description: "\(message)"
        ) {
            Task { await repository.refreshAll() }
        }
    }
}
