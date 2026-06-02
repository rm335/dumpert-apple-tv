import SwiftUI

struct WatchedSectionView: View {
    /// When embedded under the Categorieën pill bar the pill already names the
    /// channel, so the in-grid title is suppressed to avoid a duplicate label.
    var showsHeader: Bool = true
    @Environment(VideoRepository.self) private var repository
    @Environment(ImmersiveBackgroundState.self) private var backgroundState
    @State private var selectedVideo: Video?
    @State private var selectedPhoto: Photo?
    @State private var toastMessage: String?
    @FocusState private var focusedItem: String?

    /// In-progress items get a dedicated, prioritized shelf — resuming is the
    /// Library's whole reason to exist, so it leads.
    private var continueWatching: [MediaItem] {
        repository.watchedVideos.filter {
            !repository.isWatched($0.id) && repository.progressFor($0.id) > 0
        }
    }

    /// Everything finished (or with no saved position) — the archive below.
    private var earlier: [MediaItem] {
        repository.watchedVideos.filter {
            repository.isWatched($0.id) || repository.progressFor($0.id) == 0
        }
    }

    var body: some View {
        ZStack {
            if repository.isLoadingWatched && repository.watchedVideos.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        if showsHeader {
                            watchedHeader
                        }
                        SkeletonGridView(columnCount: repository.settings.tileSize.gridColumnCount)
                    }
                    .padding(.vertical, 30)
                }
                .transition(.opacity)
            } else if repository.watchedVideos.isEmpty && !repository.isLoadingWatched {
                VStack(spacing: 30) {
                    if showsHeader {
                        watchedHeader
                    }

                    EmptyStateView(
                        title: "Nog niets bekeken",
                        systemImage: "eye.slash",
                        description: "Video's die je bekijkt verschijnen hier"
                    ) {
                        Task { await repository.fetchWatchedVideos() }
                    }
                }
                .transition(.opacity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 40) {
                            Color.clear.frame(height: 0).id("top")

                            if showsHeader {
                                watchedHeader
                            }

                            if !continueWatching.isEmpty {
                                watchedSection(
                                    title: String(localized: "Verder kijken", comment: "Watched tab: continue watching section"),
                                    items: continueWatching
                                )
                            }

                            if !earlier.isEmpty {
                                watchedSection(
                                    title: String(localized: "Eerder bekeken", comment: "Watched tab: previously finished section"),
                                    items: earlier
                                )
                            }

                            // Scroll to top button (no native snap-to-top gesture on tvOS)
                            if repository.watchedVideos.count > repository.settings.tileSize.gridColumnCount * 3 {
                                Button {
                                    withAnimation(.spring(duration: 0.5)) {
                                        proxy.scrollTo("top", anchor: .top)
                                    }
                                } label: {
                                    Label(
                                        String(localized: "Naar boven", comment: "Scroll to top button"),
                                        systemImage: "arrow.up"
                                    )
                                    .font(.callout)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, 20)
                                .accessibilityLabel(Text("Scroll naar boven", comment: "Accessibility: scroll to top"))
                            }
                        }
                        .padding(.vertical, 30)
                    }
                    .refreshable {
                        await repository.fetchWatchedVideos()
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.3), value: repository.isLoadingWatched)
        .task {
            if repository.watchedVideos.isEmpty {
                await repository.fetchWatchedVideos()
            }
        }
        .fullScreenCover(item: $selectedVideo) { video in
            let videoPlaylist = repository.watchedVideos.compactMap { item -> Video? in
                if case .video(let v) = item { return v }
                return nil
            }
            // Finished videos replay from the start; in-progress videos resume
            // where you left off — resume is the point of a history view.
            VideoPlayerView(viewModel: VideoPlayerViewModel(
                video: video,
                playlist: videoPlaylist,
                repository: repository,
                startFromBeginning: repository.isWatched(video.id)
            ))
        }
        .fullScreenCover(item: $selectedPhoto) { photo in
            FullScreenImageView(photo: photo, repository: repository)
        }
        .toast(message: $toastMessage)
        .onChange(of: focusedItem) { _, newId in
            Task { @MainActor in
                if let id = newId, let item = repository.watchedVideos.first(where: { $0.id == id }) {
                    backgroundState.update(for: item)
                }
            }
        }
    }

    private func watchedSection(title: String, items: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitleView(title)
                .font(.title3)
                .padding(.horizontal, 50)

            LazyVGrid(
                columns: repository.settings.tileSize.gridColumns,
                spacing: 35
            ) {
                ForEach(items) { item in
                    card(for: item)
                }
            }
            .padding(.horizontal, 50)
        }
    }

    @ViewBuilder
    private func card(for item: MediaItem) -> some View {
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
        .focused($focusedItem, equals: item.id)
        .videoContextMenu(item: item, repository: repository, toastMessage: $toastMessage)
        .onAppear {
            if let idx = repository.watchedVideos.firstIndex(where: { $0.id == item.id }) {
                let prefetchRange = (idx + 1)..<min(idx + 6, repository.watchedVideos.count)
                if !prefetchRange.isEmpty {
                    let upcoming = Array(repository.watchedVideos[prefetchRange])
                    Task { await ImagePrefetchService.shared.prefetch(upcoming) }
                }
            }
        }
    }

    private var watchedHeader: some View {
        SectionTitleView(String(localized: "Gekeken", comment: "Watched tab: section title"))
            .font(.title2)
            .padding(.horizontal, 50)
    }
}
