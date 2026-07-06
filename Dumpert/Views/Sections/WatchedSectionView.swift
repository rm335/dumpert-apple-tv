import SwiftUI

struct WatchedSectionView: View {
    /// When embedded under the Categorieën pill bar the pill already names the
    /// channel, so the in-grid title is suppressed to avoid a duplicate label.
    var showsHeader: Bool = true
    @Environment(VideoRepository.self) private var repository
    @Environment(ImmersiveBackgroundState.self) private var backgroundState
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedVideo: Video?
    @State private var selectedPhoto: Photo?
    @State private var toastMessage: String?
    @FocusState private var focusedItem: String?
    /// Shelf snapshots taken while a player/photo cover is presented. Progress
    /// saves land every ~5s during playback and would otherwise reshuffle the
    /// shelves behind the cover — so on dismissal the originating card had
    /// moved (or vanished) and tvOS focus jumped to an arbitrary card.
    @State private var frozenContinueWatching: [MediaItem]?
    @State private var frozenEarlier: [MediaItem]?

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

                    if networkMonitor.isConnected {
                        EmptyStateView(
                            title: "Nog niets bekeken",
                            systemImage: "eye.slash",
                            description: "Video's die je bekijkt verschijnen hier"
                        ) {
                            Task { await repository.fetchWatchedVideos() }
                        }
                    } else {
                        // Offline the per-item fetches silently drop out —
                        // don't claim an intact history is empty.
                        EmptyStateView(
                            title: "Geen internetverbinding",
                            systemImage: "wifi.slash",
                            description: "Je kijkgeschiedenis kan niet geladen worden zonder internet"
                        ) {
                            Task { await repository.fetchWatchedVideos() }
                        }
                    }
                }
                .transition(.opacity)
            } else {
                ScrollViewReader { proxy in
                    // Frozen snapshots win while a cover is up (see property docs).
                    let continueWatching = frozenContinueWatching ?? self.continueWatching
                    let earlier = frozenEarlier ?? self.earlier
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
                                    withAnimation(reduceMotion ? nil : .dumpiSelection) {
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
        .animation(reduceMotion ? nil : .dumpiStandard, value: repository.isLoadingWatched)
        .task {
            // Refresh on every visit: .refreshable has no gesture on tvOS and
            // the 15-min scheduler doesn't cover this feed, so an isEmpty
            // guard froze the list at the session's first fetch — videos
            // watched later never appeared until app relaunch.
            await repository.fetchWatchedVideos()
        }
        .onChange(of: selectedVideo != nil || selectedPhoto != nil) { _, coverUp in
            if coverUp {
                frozenContinueWatching = continueWatching
                frozenEarlier = earlier
            } else {
                Task { @MainActor in
                    // Let tvOS restore focus onto the unchanged layout first,
                    // then re-sort the shelves under the user.
                    try? await Task.sleep(for: .milliseconds(600))
                    withAnimation(reduceMotion ? nil : .dumpiStandard) {
                        frozenContinueWatching = nil
                        frozenEarlier = nil
                    }
                }
            }
        }
        .fullScreenCover(item: $selectedVideo) { video in
            let videoPlaylist = repository.watchedVideos.compactMap { item -> Video? in
                if case .video(let v) = item { return v }
                return nil
            }
            // Finished videos replay from the start; in-progress videos resume
            // where you left off — resume is the point of a history view.
            VideoPlayerView(
                video: video,
                playlist: videoPlaylist,
                repository: repository,
                startFromBeginning: repository.isWatched(video.id)
            )
        }
        .fullScreenCover(item: $selectedPhoto) { photo in
            FullScreenImageView(photo: photo, repository: repository)
        }
        .toast(message: $toastMessage)
        .onChange(of: PlaybackCoordinator.shared.deepLinkTakeoverID) {
            // A Top Shelf/deep-link tap needs the stage: dismiss our covers
            // so the root-level deep-link presentation can succeed.
            selectedVideo = nil
            selectedPhoto = nil
        }
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
                suspendPreview: selectedVideo != nil || selectedPhoto != nil,
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
