import SwiftUI

struct CategorySectionView: View {
    let category: VideoCategory
    /// When embedded under the Categorieën pill bar the pill already names the
    /// channel, so the in-grid title is suppressed (the sort picker stays).
    var showsTitle: Bool = true
    @Environment(VideoRepository.self) private var repository
    @Environment(ImmersiveBackgroundState.self) private var backgroundState
    @State private var selectedVideo: Video?
    @State private var selectedPhoto: Photo?
    @State private var toastMessage: String?
    @FocusState private var focusedItem: String?

    private var items: [MediaItem] {
        // DumpertTV's newest-first ordering is applied once in the data layer
        // (CategoryService) when each page is fetched, so the view just reads the
        // stored order — no per-access re-sort, and pages don't reorder on load-more.
        repository.filteredItems(repository.categoryVideos[category] ?? [])
    }

    private var sortOrder: SortOrder {
        repository.categorySortOrder[category] ?? .dateNewest
    }

    private var hasMore: Bool {
        repository.categoryHasMore[category] ?? false
    }

    private var isLoadingMore: Bool {
        repository.isCategoryLoadingMore[category] ?? false
    }

    var body: some View {
        ZStack {
            if repository.isLoading && items.isEmpty {
                loadingState
            } else if items.isEmpty && !repository.isLoading {
                emptyState
            } else {
                loadedState
            }
        }
        .animation(.easeOut(duration: 0.3), value: repository.isLoading)
        .fullScreenCover(item: $selectedVideo) { video in
            let videoPlaylist = items.compactMap { item -> Video? in
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
        .onChange(of: focusedItem) { _, newId in
            Task { @MainActor in
                if let id = newId, let item = items.first(where: { $0.id == id }) {
                    backgroundState.update(for: item)
                }
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if showsTitle {
                    SectionTitleView(category.displayName)
                        .font(.title2)
                        .padding(.horizontal, 50)
                }
                SkeletonGridView(columnCount: repository.settings.tileSize.gridColumnCount)
            }
            .padding(.vertical, 30)
        }
        .transition(.opacity)
    }

    private var emptyState: some View {
        VStack(spacing: 30) {
            if showsTitle {
                SectionTitleView(category.displayName)
                    .font(.title2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 50)
            }

            if let error = repository.error {
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
                    description: "Geen video's gevonden voor \(category.displayName)"
                ) {
                    Task { await repository.refreshAll() }
                }
            }
        }
        .transition(.opacity)
    }

    private var loadedState: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HStack {
                        if showsTitle {
                            SectionTitleView(category.displayName)
                                .font(.title2)
                        }
                        Spacer()
                        if category == .reeten {
                            reetenDurationMenu
                        }
                        if category.supportsSorting {
                            sortPicker
                        }
                    }
                    .padding(.horizontal, 50)
                    .id("top")

                    // The Nieuw feed groups by day so recency is legible;
                    // curated genres stay a single flat grid.
                    if category.endpoint == .latest {
                        groupedFeed
                    } else {
                        flatGrid
                    }

                    // Load more indicator
                    if isLoadingMore {
                        ProgressView(String(localized: "Meer laden...", comment: "Loading more results indicator"))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .accessibilityLabel(Text("Meer video's laden", comment: "Accessibility: loading more videos"))
                    } else if hasMore && !items.isEmpty {
                        Button(String(localized: "Laad meer", comment: "Load more button")) {
                            Task { await repository.loadMoreForCategory(category) }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .accessibilityHint(Text("Laad meer video's in \(category.displayName)", comment: "Accessibility: load more videos in category"))
                    }

                    // Scroll to top button (no native snap-to-top gesture on tvOS)
                    if items.count > repository.settings.tileSize.gridColumnCount * 3 {
                        Button {
                            withAnimation(.spring(duration: 0.5)) {
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

    // MARK: - Grids

    private var flatGrid: some View {
        LazyVGrid(columns: repository.settings.tileSize.gridColumns, spacing: 35) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                card(for: item, index: index)
            }
        }
        .padding(.horizontal, 50)
    }

    /// Reverse-chronological feed broken into day sections so "freshness" — the
    /// whole point of the Nieuw tab — is legible at a glance instead of being an
    /// anonymous wall of tiles.
    private var groupedFeed: some View {
        let lookup = flatIndexLookup
        return LazyVStack(alignment: .leading, spacing: 30) {
            ForEach(dayGroups, id: \.key) { group in
                VStack(alignment: .leading, spacing: 14) {
                    Text(group.label)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
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
                thumbnailPreviewEnabled: repository.settings.thumbnailPreviewEnabled,
                smartThumbnailsEnabled: repository.settings.smartThumbnailsEnabled && category != .reeten && category != .vrijmico
            )
        }
        .buttonStyle(.card)
        .focused($focusedItem, equals: item.id)
        .videoContextMenu(item: item, repository: repository, toastMessage: $toastMessage, currentCategory: category)
        .onAppear {
            let prefetchRange = (index + 1)..<min(index + 6, items.count)
            if !prefetchRange.isEmpty {
                let upcoming = Array(items[prefetchRange])
                Task { await ImagePrefetchService.shared.prefetch(upcoming) }
            }
            if index >= items.count - 3 {
                Task { await repository.loadMoreForCategory(category) }
            }
        }
    }

    // MARK: - Day Grouping (Nieuw feed)

    /// Maps each item id to its position in the flat `items` array so the grouped
    /// renderer can keep prefetch + pagination working off the real index.
    private var flatIndexLookup: [String: Int] {
        var dict: [String: Int] = [:]
        for (i, item) in items.enumerated() { dict[item.id] = i }
        return dict
    }

    private var dayGroups: [(key: Date, label: String, items: [MediaItem])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: items) { item in
            cal.startOfDay(for: item.date ?? .distantPast)
        }
        return grouped.keys.sorted(by: >).map { day in
            (key: day, label: dayLabel(for: day), items: grouped[day] ?? [])
        }
    }

    private func dayLabel(for day: Date) -> String {
        let cal = Calendar.current
        if let cutoff = cal.date(byAdding: .year, value: -50, to: Date()), day < cutoff {
            return String(localized: "Eerder", comment: "Date section header for items without a date")
        }
        if cal.isDateInToday(day) {
            return String(localized: "Vandaag", comment: "Date section header: today")
        }
        if cal.isDateInYesterday(day) {
            return String(localized: "Gisteren", comment: "Date section header: yesterday")
        }
        return Self.sectionDateFormatter.string(from: day)
    }

    private static let sectionDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    // MARK: - Controls

    private var sortPicker: some View {
        Menu {
            ForEach(SortOrder.allCases) { order in
                Button {
                    repository.setSortOrder(order, for: category)
                } label: {
                    if order == sortOrder {
                        Label(order.displayName, systemImage: "checkmark")
                    } else {
                        Label(order.displayName, systemImage: order.systemImage)
                    }
                }
            }
        } label: {
            Label(sortOrder.displayName, systemImage: sortOrder.systemImage)
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.dumpiGreen, in: Capsule())
        }
        .accessibilityLabel(Text("Sortering", comment: "Accessibility: sort order control"))
        .accessibilityValue(Text(sortOrder.displayName))
        .accessibilityHint(Text("Wijzig de sorteervolgorde", comment: "Accessibility: change sort order hint"))
    }

    /// Reeten-only: the minimum-duration filter that previously lived only in
    /// Settings, surfaced on the channel it actually affects. Refetches on
    /// change so the result is visible immediately.
    private var reetenDurationMenu: some View {
        let current = repository.settings.reetenMinimumMinutes
        let options: [(label: String, value: Int)] = [
            (String(localized: "Alle duur", comment: "Reeten minimum duration: no minimum"), 0),
            (String(localized: "5+ min", comment: "Reeten minimum duration: 5 minutes"), 5),
            (String(localized: "10+ min", comment: "Reeten minimum duration: 10 minutes"), 10),
            (String(localized: "15+ min", comment: "Reeten minimum duration: 15 minutes"), 15),
            (String(localized: "20+ min", comment: "Reeten minimum duration: 20 minutes"), 20),
        ]
        return Menu {
            ForEach(options, id: \.value) { option in
                Button {
                    repository.setReetenMinimum(option.value)
                } label: {
                    if option.value == current {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            Label(
                current == 0 ? String(localized: "Alle duur", comment: "Reeten minimum duration: no minimum") : "\(current)+ min",
                systemImage: "timer"
            )
            .font(.callout)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.15), in: Capsule())
        }
        .accessibilityLabel(Text("Minimale duur", comment: "Accessibility: reeten minimum duration filter"))
        .accessibilityValue(Text(current == 0 ? String(localized: "Alle duur", comment: "Reeten minimum duration: no minimum") : String(localized: "\(current) minuten", comment: "Accessibility: selected reeten minimum duration")))
    }
}
