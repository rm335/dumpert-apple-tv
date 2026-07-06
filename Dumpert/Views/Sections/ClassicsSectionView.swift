import SwiftUI

struct ClassicsSectionView: View {
    /// When embedded under the Categorieën pill bar the pill already names the
    /// channel, so the in-grid title is suppressed to avoid a duplicate label.
    var showsHeader: Bool = true
    @Environment(VideoRepository.self) private var repository
    @Environment(ImmersiveBackgroundState.self) private var backgroundState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedVideo: Video?
    @State private var selectedPhoto: Photo?
    @State private var toastMessage: String?
    @FocusState private var focusedItem: String?

    private var items: [MediaItem] {
        repository.filteredItems(repository.classics)
    }

    var body: some View {
        ZStack {
            if repository.isLoading && items.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        if showsHeader {
                            classicsHeader
                        }
                        SkeletonGridView(columnCount: repository.settings.tileSize.gridColumnCount)
                    }
                    .padding(.vertical, 30)
                }
                .transition(.opacity)
            } else if items.isEmpty && !repository.isLoading {
                VStack(spacing: 30) {
                    if showsHeader {
                        classicsHeader
                    }

                    if let error = repository.classicsError ?? repository.error {
                        EmptyStateView(
                            title: "Er ging iets mis",
                            systemImage: "exclamationmark.triangle",
                            description: "\(error)"
                        ) {
                            Task { await repository.refreshAll() }
                        }
                    } else {
                        EmptyStateView(
                            title: "Geen video's",
                            systemImage: "video.slash",
                            description: "Geen classics gevonden"
                        ) {
                            Task { await repository.refreshAll() }
                        }
                    }
                }
                .transition(.opacity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 30) {
                            Color.clear.frame(height: 0).id("top")

                            if showsHeader {
                                classicsHeader
                            }

                            // The Vault, walkable by era: year is a section header
                            // rather than a tiny per-card badge.
                            yearGroupedGrid

                            if repository.isClassicsLoadingMore {
                                ProgressView(String(localized: "Meer laden...", comment: "Loading more results indicator"))
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .accessibilityLabel(Text("Meer classics laden", comment: "Accessibility: loading more classics"))
                            } else if repository.classicsHasMore && !items.isEmpty {
                                Button(String(localized: "Laad meer", comment: "Load more button")) {
                                    Task { await repository.loadMoreClassics() }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .accessibilityHint(Text("Laad meer classics", comment: "Accessibility: load more classics"))
                            }

                            // Scroll to top button (no native snap-to-top gesture on tvOS)
                            if items.count > repository.settings.tileSize.gridColumnCount * 3 {
                                Button {
                                    withAnimation(reduceMotion ? nil : .dumpiSelection) {
                                        proxy.scrollTo("top", anchor: .top)
                                    }
                                } label: {
                                    Label("Naar boven", systemImage: "arrow.up")
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
                        await repository.refreshAll()
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .dumpiStandard, value: repository.isLoading)
        .fullScreenCover(item: $selectedVideo) { video in
            let videoPlaylist = items.compactMap { item -> Video? in
                if case .video(let v) = item { return v }
                return nil
            }
            VideoPlayerView(
                video: video,
                playlist: videoPlaylist,
                repository: repository
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
        .onChange(of: repository.paginationError) { _, message in
            // Load-more failures surface here as a toast; the list stays.
            guard let message else { return }
            toastMessage = message
            repository.paginationError = nil
        }
        .onChange(of: focusedItem) { _, newId in
            Task { @MainActor in
                if let id = newId, let item = items.first(where: { $0.id == id }) {
                    backgroundState.update(for: item)
                }
            }
        }
    }

    // MARK: - Year-grouped grid

    private var yearGroupedGrid: some View {
        let lookup = flatIndexLookup
        return LazyVStack(alignment: .leading, spacing: 30) {
            ForEach(yearGroups, id: \.key) { group in
                VStack(alignment: .leading, spacing: 14) {
                    Text(group.label)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .padding(.horizontal, 50)
                        .accessibilityAddTraits(.isHeader)

                    LazyVGrid(columns: repository.settings.tileSize.gridColumns, spacing: 35) {
                        ForEach(group.items) { item in
                            card(for: item, index: lookup[item.id] ?? 0)
                        }
                    }
                    .padding(.horizontal, 50)
                }
            }
        }
    }

    @ViewBuilder
    private func card(for item: MediaItem, index: Int) -> some View {
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
            let prefetchRange = (index + 1)..<min(index + 6, items.count)
            if !prefetchRange.isEmpty {
                let upcoming = Array(items[prefetchRange])
                Task { await ImagePrefetchService.shared.prefetch(upcoming) }
            }
            if index >= items.count - 3 {
                Task { await repository.loadMoreClassics() }
            }
        }
    }

    private var flatIndexLookup: [String: Int] {
        var dict: [String: Int] = [:]
        for (i, item) in items.enumerated() { dict[item.id] = i }
        return dict
    }

    private var yearGroups: [(key: Int, label: String, items: [MediaItem])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: items) { item -> Int in
            guard let date = item.date else { return 0 }
            return cal.component(.year, from: date)
        }
        return grouped.keys.sorted(by: >).map { year in
            (
                key: year,
                label: year == 0
                    ? String(localized: "Onbekend jaar", comment: "Classics: section for items without a date")
                    : String(year),
                items: grouped[year] ?? []
            )
        }
    }

    private var classicsHeader: some View {
        SectionTitleView("Classics")
            .font(.title2)
            .padding(.horizontal, 50)
    }
}

// MARK: - Date Extension for Classics

extension Date {
    private static let classicsYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f
    }()

    var classicsYearString: String {
        Date.classicsYearFormatter.string(from: self)
    }
}
