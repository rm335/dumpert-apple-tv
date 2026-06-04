import Foundation
import TVServices
import os

@Observable
@MainActor
final class VideoRepository {
    // Data
    private(set) var hotshiz: [MediaItem] = []
    private(set) var topWeek: [MediaItem] = []
    private(set) var topMonth: [MediaItem] = []
    private(set) var topDay: [MediaItem] = []
    private(set) var categoryVideos: [VideoCategory: [MediaItem]] = [:]
    private(set) var watchProgress: [String: WatchProgress] = [:]
    private(set) var curationEntries: [CurationEntry] = []
    private(set) var classics: [MediaItem] = []
    private(set) var watchedVideos: [MediaItem] = []
    private(set) var isLoadingWatched = false
    private(set) var searchHistory: [SearchHistoryEntry] = []

    // Sort order
    private(set) var categorySortOrder: [VideoCategory: SortOrder] = [:]

    // Pagination
    private(set) var categoryPages: [VideoCategory: Int] = [:]
    private(set) var categoryHasMore: [VideoCategory: Bool] = [:]
    private(set) var isCategoryLoadingMore: [VideoCategory: Bool] = [:]
    /// Raw item ids (pre-filter) seen so far per category, used to detect when an
    /// endpoint starts repeating items so pagination can stop. Bookkeeping only —
    /// views never read it, so it's excluded from observation.
    @ObservationIgnored private var categorySeenRawIDs: [VideoCategory: Set<String>] = [:]
    private(set) var classicsPage = 0
    private(set) var classicsHasMore = true
    private(set) var isClassicsLoadingMore = false

    // State
    private(set) var isLoading = true
    private(set) var error: String?
    private(set) var lastRefreshDate: Date?

    // Dependencies
    let apiClient: DumpertAPIClient
    private let cacheService: CacheService
    private let cloudKitService: CloudKitService
    private let categoryService: CategoryService
    let refreshScheduler = RefreshScheduler()
    var networkMonitor: NetworkMonitor?
    private var cloudKitAvailable = false

    // NOTE: A `didSet` here would only fire on whole-object reassignment, not
    // on inner property mutation of the @Observable UserSettings instance.
    // Persistence is wired through `settings.onChange` instead (see init).
    var settings: UserSettings

    @ObservationIgnored
    private var settingsSaveTask: Task<Void, Never>?

    init(
        apiClient: DumpertAPIClient = DumpertAPIClient(),
        cacheService: CacheService = CacheService(),
        cloudKitService: CloudKitService = CloudKitService()
    ) {
        self.apiClient = apiClient
        self.cacheService = cacheService
        self.cloudKitService = cloudKitService
        self.categoryService = CategoryService(apiClient: apiClient, cacheService: cacheService)
        self.settings = UserSettings()
        for category in VideoCategory.allCases {
            categorySortOrder[category] = .dateNewest
            categoryPages[category] = 0
            categoryHasMore[category] = true
            isCategoryLoadingMore[category] = false
        }
        refreshScheduler.onRefresh = { [weak self] in
            await self?.refreshAll()
        }
        // Persist on any UI-driven settings change. Debounced so bulk updates
        // (e.g. the "Restore defaults" action that mutates ~17 properties in
        // one tick) collapse into a single save round-trip.
        settings.onChange = { [weak self] in
            self?.scheduleSettingsSave()
        }
        Task {
            await loadFromCache()
            await setupCloudKit()
            await refreshAll()
            refreshScheduler.start()
        }
    }

    private func scheduleSettingsSave() {
        settingsSaveTask?.cancel()
        settingsSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await self?.saveSettings()
        }
    }

    // MARK: - Initial Load

    private func loadFromCache() async {
        settings.apply(await cacheService.loadSettings())
        await apiClient.setNSFWEnabled(settings.nsfwEnabled)
        // Seed the App Group so the Top Shelf extension and startup sound honor
        // the persisted NSFW preference even before any settings change.
        TopShelfDataStore.setNSFWEnabled(settings.nsfwEnabled)
        watchProgress = await cacheService.loadWatchProgress()
        curationEntries = await cacheService.loadCurationEntries()
        searchHistory = await cacheService.loadSearchHistory()

        for category in VideoCategory.allCases {
            let cached = await categoryService.loadCachedItems(
                for: category,
                curationEntries: curationEntries,
                minimumKudos: settings.minimumKudos,
                reetenMinimumMinutes: settings.reetenMinimumMinutes
            )
            if !cached.isEmpty {
                categoryVideos[category] = cached
            }
        }

        if let cachedClassics = await cacheService.loadCachedMediaItems(for: "classics") {
            classics = cachedClassics
        }
    }

    private func setupCloudKit() async {
        do {
            try await cloudKitService.setupZone()
            cloudKitAvailable = true
            // Use delta sync (with no token = full fetch) instead of queries.
            // This avoids the "recordName not queryable" index requirement.
            let changes = try await cloudKitService.fetchChanges()
            applyCloudKitChanges(changes)
            Logger.cloudKit.info("CloudKit initial sync: \(changes.changedRecords.count) records loaded")
        } catch {
            cloudKitAvailable = false
            Logger.cloudKit.info("CloudKit not available: \(error.localizedDescription). Using local data only.")
        }
    }

    // MARK: - Refresh

    func refreshAll() async {
        if let networkMonitor, !networkMonitor.isConnected {
            isLoading = false
            return
        }

        isLoading = true
        error = nil

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshToppers() }
            group.addTask { await self.refreshCategories() }
            group.addTask { await self.refreshClassics() }
        }

        isLoading = false
        lastRefreshDate = Date()
        updateTopShelf()

        // Delta sync CloudKit changes in background
        if cloudKitAvailable {
            Task {
                do {
                    let changes = try await cloudKitService.fetchChanges()
                    applyCloudKitChanges(changes)
                } catch {
                    Logger.cloudKit.warning("Delta sync failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // Internal (not private) so tests can drive merge behavior with synthetic CKRecords
    // without spinning up an actual CloudKit container.
    func applyCloudKitChanges(_ changes: CloudKitChanges) {
        var watchProgressDirty = false
        var curationDirty = false
        var searchHistoryDirty = false
        var settingsDirty = false

        for record in changes.changedRecords {
            switch record.recordType {
            case "WatchProgress":
                if let videoId = record["videoId"] as? String {
                    var remote = WatchProgress(
                        videoId: videoId,
                        watchedSeconds: record["watchedSeconds"] as? Double ?? 0,
                        totalSeconds: record["totalSeconds"] as? Double ?? 0
                    )
                    if let remoteDate = record["lastWatchedDate"] as? Date {
                        remote.lastWatchedDate = remoteDate
                    }
                    if let local = watchProgress[videoId] {
                        if remote.lastWatchedDate > local.lastWatchedDate {
                            watchProgress[videoId] = remote
                            watchProgressDirty = true
                        }
                    } else {
                        watchProgress[videoId] = remote
                        watchProgressDirty = true
                    }
                }
            case "CurationEntry":
                if let videoId = record["videoId"] as? String,
                   let categoryRaw = record["category"] as? String,
                   let category = VideoCategory(rawValue: categoryRaw),
                   let actionRaw = record["action"] as? String,
                   let action = CurationAction(rawValue: actionRaw) {
                    let entry = CurationEntry(videoId: videoId, category: category, action: action)
                    if !curationEntries.contains(where: { $0.videoId == videoId && $0.category == category && $0.action == action }) {
                        curationEntries.append(entry)
                        curationDirty = true
                    }
                }
            case "UserSettings":
                // Use the current local snapshot as fallback so unknown CloudKit
                // fields don't clobber valid local settings during merge.
                var fallback = settings.snapshot
                fallback.lastModified = .distantPast
                let remoteSettings = CloudKitService.makeSettings(from: record, fallback: fallback)
                if remoteSettings.lastModified > settings.lastModified {
                    settings.apply(remoteSettings)
                    settingsDirty = true
                }
            case "SearchHistory":
                if let query = record["query"] as? String {
                    let idString = record.recordID.recordName.replacingOccurrences(of: "search_", with: "")
                    if let uuid = UUID(uuidString: idString) {
                        let timestamp = record["timestamp"] as? Date ?? Date()
                        let entry = SearchHistoryEntry(id: uuid, query: query, timestamp: timestamp)
                        if !searchHistory.contains(where: { $0.id == entry.id }) {
                            searchHistory.append(entry)
                            searchHistoryDirty = true
                        }
                    }
                }
            default:
                break
            }
        }

        // Process deletions from other devices. Records are deleted via prefixed
        // recordName (e.g., "watch_<videoId>", "search_<uuid>") or the bare UUID
        // for curation entries.
        for recordID in changes.deletedRecordIDs {
            let name = recordID.recordName
            if name.hasPrefix("watch_") {
                let videoId = String(name.dropFirst("watch_".count))
                if watchProgress.removeValue(forKey: videoId) != nil {
                    watchProgressDirty = true
                }
            } else if name.hasPrefix("search_") {
                let idString = String(name.dropFirst("search_".count))
                if let uuid = UUID(uuidString: idString),
                   let index = searchHistory.firstIndex(where: { $0.id == uuid }) {
                    searchHistory.remove(at: index)
                    searchHistoryDirty = true
                }
            } else if let uuid = UUID(uuidString: name),
                      let index = curationEntries.firstIndex(where: { $0.id == uuid }) {
                curationEntries.remove(at: index)
                curationDirty = true
            }
        }

        if searchHistoryDirty {
            // Preserve newest-first order and the 20-entry cap maintained by
            // recordSearch — otherwise merging cloud entries would leave the
            // list unsorted and unbounded.
            searchHistory.sort { $0.timestamp > $1.timestamp }
            if searchHistory.count > 20 {
                searchHistory = Array(searchHistory.prefix(20))
            }
        }

        // Persist merged state to the local cache so it survives a launch
        // where CloudKit happens to be unavailable.
        let progressSnapshot = watchProgress
        let curationSnapshot = curationEntries
        let searchSnapshot = searchHistory
        let settingsSnapshot = settings.snapshot
        Task {
            if watchProgressDirty {
                await cacheService.saveWatchProgress(progressSnapshot)
            }
            if curationDirty {
                await cacheService.saveCurationEntries(curationSnapshot)
            }
            if searchHistoryDirty {
                await cacheService.saveSearchHistory(searchSnapshot)
            }
            if settingsDirty {
                await cacheService.saveSettings(settingsSnapshot)
            }
        }
    }

    private func refreshToppers() async {
        do {
            async let h = apiClient.fetchHotshiz()
            async let w = apiClient.fetchTopWeek()
            async let m = apiClient.fetchTopMonth()
            async let d = apiClient.fetchTopDay()

            let (hotshizResult, weekResult, monthResult, dayResult) = try await (h, w, m, d)

            hotshiz = filterByKudos(hotshizResult)
            topWeek = filterByKudos(weekResult)
            topMonth = filterByKudos(monthResult)
            topDay = filterByKudos(dayResult)

            recomputePopularTags()

            await cacheService.cacheMediaItems(hotshizResult, for: "hotshiz")
            await cacheService.cacheMediaItems(weekResult, for: "topweek")
            await cacheService.cacheMediaItems(monthResult, for: "topmonth")
            await cacheService.cacheMediaItems(dayResult, for: "topday")
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func refreshCategories() async {
        // Snapshot main-actor state up front so the concurrent child tasks only
        // touch Sendable locals (Swift 6 strict concurrency).
        let curationEntries = self.curationEntries
        let minimumKudos = settings.minimumKudos
        let reetenMinimum = settings.reetenMinimumMinutes
        let categoryService = self.categoryService

        var orders: [VideoCategory: SortOrder] = [:]
        for category in VideoCategory.allCases {
            categoryPages[category] = 0
            categoryHasMore[category] = true
            orders[category] = categorySortOrder[category] ?? .dateNewest
        }

        // Fetch every category concurrently (they're independent) instead of one
        // serial round-trip after another; assign results on the main actor as
        // each completes so the UI fills in progressively.
        await withTaskGroup(of: (VideoCategory, CategoryService.CategoryPage?, String?).self) { group in
            for category in VideoCategory.allCases {
                let order = orders[category] ?? .dateNewest
                group.addTask {
                    do {
                        let page = try await categoryService.fetchItems(
                            for: category,
                            order: order,
                            curationEntries: curationEntries,
                            minimumKudos: minimumKudos,
                            reetenMinimumMinutes: reetenMinimum
                        )
                        return (category, page, nil)
                    } catch {
                        return (category, nil, error.localizedDescription)
                    }
                }
            }

            for await (category, page, errorMessage) in group {
                if let page {
                    categoryVideos[category] = page.items
                    categoryHasMore[category] = !page.rawIDs.isEmpty
                    categorySeenRawIDs[category] = Set(page.rawIDs)
                } else if let errorMessage {
                    self.error = errorMessage
                }
            }
        }
    }

    private func refreshClassics() async {
        classicsPage = 0
        classicsHasMore = true
        do {
            let items = try await apiClient.fetchClassics()
            classics = filterByKudos(items)
            classicsHasMore = !items.isEmpty
            await cacheService.cacheMediaItems(items, for: "classics")
        } catch {
            self.error = error.localizedDescription
        }
    }

    func fetchRelatedVideos(for videoId: String) async -> [Video] {
        do {
            let items = try await apiClient.fetchRelated(id: videoId)
            return filterByKudos(items).compactMap { item -> Video? in
                if case .video(let v) = item { return v }
                return nil
            }
        } catch {
            Logger.network.warning("Failed to fetch related videos: \(error.localizedDescription)")
            return []
        }
    }

    func fetchTopComments(for itemId: String) async throws -> [DumpertComment] {
        try await apiClient.fetchTopComments(for: itemId)
    }

    // MARK: - Pagination

    func loadMoreForCategory(_ category: VideoCategory) async {
        guard isCategoryLoadingMore[category] != true,
              categoryHasMore[category] == true else { return }

        isCategoryLoadingMore[category] = true
        let nextPage = (categoryPages[category] ?? 0) + 1

        do {
            let page = try await categoryService.fetchItems(
                for: category,
                page: nextPage,
                order: categorySortOrder[category] ?? .dateNewest,
                curationEntries: curationEntries,
                minimumKudos: settings.minimumKudos,
                reetenMinimumMinutes: settings.reetenMinimumMinutes
            )

            if page.rawIDs.isEmpty {
                // The endpoint has no more items.
                categoryHasMore[category] = false
            } else {
                var seen = categorySeenRawIDs[category] ?? []
                let newRawIDs = page.rawIDs.filter { !seen.contains($0) }
                if newRawIDs.isEmpty {
                    // The page only repeats items we've already loaded (overlapping
                    // or wrapping pages), so there's genuinely nothing more to show.
                    categoryHasMore[category] = false
                } else {
                    seen.formUnion(page.rawIDs)
                    categorySeenRawIDs[category] = seen
                    // Advance the page even when every new item was filtered out for
                    // display, so a page that's entirely below the kudos threshold
                    // doesn't dead-end pagination before later pages that qualify.
                    categoryPages[category] = nextPage
                    var existing = categoryVideos[category] ?? []
                    let existingIds = Set(existing.map(\.id))
                    let uniqueItems = page.items.filter { !existingIds.contains($0.id) }
                    existing.append(contentsOf: uniqueItems)
                    categoryVideos[category] = existing
                }
            }
        } catch {
            self.error = error.localizedDescription
        }

        isCategoryLoadingMore[category] = false
    }

    func loadMoreClassics() async {
        guard !isClassicsLoadingMore, classicsHasMore else { return }

        isClassicsLoadingMore = true
        let nextPage = classicsPage + 1

        do {
            let newItems = try await apiClient.fetchClassics(page: nextPage)
            if newItems.isEmpty {
                classicsHasMore = false
            } else {
                let existingIds = Set(classics.map(\.id))
                let unique = filterByKudos(newItems).filter { !existingIds.contains($0.id) }
                classics.append(contentsOf: unique)
                classicsPage = nextPage
            }
        } catch {
            self.error = error.localizedDescription
        }

        isClassicsLoadingMore = false
    }

    // MARK: - Filtering

    func filterByKudos(_ items: [MediaItem]) -> [MediaItem] {
        items.filter { item in
            if settings.showNegativeKudos && item.kudosTotal < 0 {
                return true
            }
            return item.kudosTotal >= settings.minimumKudos
        }
    }

    func syncNSFWSetting() {
        Task { await apiClient.setNSFWEnabled(settings.nsfwEnabled) }
    }

    // MARK: - Sort Order

    func setSortOrder(_ order: SortOrder, for category: VideoCategory) {
        // Only the search-backed channels honor a sort order; ignore for the
        // latest/DumpertTV feeds so we don't store an order the endpoint drops and
        // trigger a needless clear-and-refetch.
        guard category.supportsSorting else { return }
        categorySortOrder[category] = order
        categoryPages[category] = 0
        categoryHasMore[category] = true
        categoryVideos[category] = []
        categorySeenRawIDs[category] = []
        Task {
            do {
                let page = try await categoryService.fetchItems(
                    for: category,
                    order: order,
                    curationEntries: curationEntries,
                    minimumKudos: settings.minimumKudos,
                    reetenMinimumMinutes: settings.reetenMinimumMinutes
                )
                categoryVideos[category] = page.items
                categoryHasMore[category] = !page.rawIDs.isEmpty
                categorySeenRawIDs[category] = Set(page.rawIDs)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// Updates the Reeten minimum-duration filter and refetches immediately so
    /// the change is visible on the channel right away. The minimum is applied
    /// at fetch time (not in `filteredItems`), so — like `setSortOrder` — this
    /// must clear and reload rather than just flip the setting.
    func setReetenMinimum(_ minutes: Int) {
        guard settings.reetenMinimumMinutes != minutes else { return }
        settings.reetenMinimumMinutes = minutes
        let category = VideoCategory.reeten
        categoryPages[category] = 0
        categoryHasMore[category] = true
        categoryVideos[category] = []
        categorySeenRawIDs[category] = []
        Task {
            do {
                let page = try await categoryService.fetchItems(
                    for: category,
                    order: categorySortOrder[category] ?? .dateNewest,
                    curationEntries: curationEntries,
                    minimumKudos: settings.minimumKudos,
                    reetenMinimumMinutes: settings.reetenMinimumMinutes
                )
                categoryVideos[category] = page.items
                categoryHasMore[category] = !page.rawIDs.isEmpty
                categorySeenRawIDs[category] = Set(page.rawIDs)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func filteredItems(_ items: [MediaItem]) -> [MediaItem] {
        var result = filterByKudos(items)
        if !settings.nsfwEnabled {
            result = result.filter { !$0.isNSFW }
        }
        if settings.hideWatched {
            result = result.filter { item in
                !(watchProgress[item.id]?.isCompleted ?? false)
            }
        }
        return result
    }

    // MARK: - Watch Progress

    func updateWatchProgress(videoId: String, watchedSeconds: Double, totalSeconds: Double) {
        var progress = watchProgress[videoId] ?? WatchProgress(videoId: videoId)
        progress.update(watchedSeconds: watchedSeconds, totalSeconds: totalSeconds)
        watchProgress[videoId] = progress

        Task {
            await cacheService.saveWatchProgress(watchProgress)
            guard cloudKitAvailable else { return }
            do {
                try await cloudKitService.saveWatchProgress(progress)
            } catch {
                Logger.cloudKit.warning("Failed to save watch progress: \(error.localizedDescription)")
            }
        }
    }

    func isWatched(_ videoId: String) -> Bool {
        watchProgress[videoId]?.isCompleted ?? false
    }

    func progressFor(_ videoId: String) -> Double {
        watchProgress[videoId]?.progress ?? 0
    }

    func markAsWatched(videoId: String) {
        guard !isWatched(videoId) else { return }
        var progress = watchProgress[videoId] ?? WatchProgress(videoId: videoId)
        progress.isCompleted = true
        progress.lastWatchedDate = Date()
        watchProgress[videoId] = progress

        Task {
            await cacheService.saveWatchProgress(watchProgress)
            guard cloudKitAvailable else { return }
            do {
                try await cloudKitService.saveWatchProgress(progress)
            } catch {
                Logger.cloudKit.warning("Failed to save watch mark: \(error.localizedDescription)")
            }
        }
    }

    func toggleWatched(videoId: String) {
        var progress = watchProgress[videoId] ?? WatchProgress(videoId: videoId)
        progress.isCompleted = !progress.isCompleted
        progress.lastWatchedDate = Date()
        watchProgress[videoId] = progress

        Task {
            await cacheService.saveWatchProgress(watchProgress)
            guard cloudKitAvailable else { return }
            do {
                try await cloudKitService.saveWatchProgress(progress)
            } catch {
                Logger.cloudKit.warning("Failed to save watch toggle: \(error.localizedDescription)")
            }
        }
    }

    func clearWatchHistory() async {
        watchProgress = [:]
        watchedVideos = []
        await cacheService.saveWatchProgress(watchProgress)
    }

    // MARK: - Watched Videos

    func fetchWatchedVideos() async {
        isLoadingWatched = true

        let sorted = watchProgress.values
            .sorted { $0.lastWatchedDate > $1.lastWatchedDate }
            .prefix(100)

        // Build lookup from all locally available items
        let allLocalItems = hotshiz + topWeek + topMonth + topDay + classics
            + VideoCategory.allCases.flatMap { categoryVideos[$0] ?? [] }
        let localLookup = Dictionary(allLocalItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Split into local hits and API misses
        var results: [(Int, MediaItem)] = []
        var missingIndices: [(Int, String)] = []
        for (index, progress) in sorted.enumerated() {
            if let local = localLookup[progress.videoId] {
                results.append((index, local))
            } else {
                missingIndices.append((index, progress.videoId))
            }
        }

        // Fetch missing items from API in batches of 5
        for batch in stride(from: 0, to: missingIndices.count, by: 5) {
            let end = min(batch + 5, missingIndices.count)
            let slice = missingIndices[batch..<end]
            await withTaskGroup(of: (Int, MediaItem?).self) { group in
                for (index, videoId) in slice {
                    group.addTask {
                        let item = try? await self.apiClient.fetchItem(id: videoId)
                        return (index, item)
                    }
                }
                for await (index, item) in group {
                    if let item { results.append((index, item)) }
                }
            }
        }

        watchedVideos = results.sorted { $0.0 < $1.0 }.map(\.1)
        isLoadingWatched = false
    }

    // MARK: - Curation

    func addToCategory(videoId: String, category: VideoCategory) {
        let entry = CurationEntry(videoId: videoId, category: category, action: .add)
        curationEntries.append(entry)
        Task {
            await cacheService.saveCurationEntries(curationEntries)
            guard cloudKitAvailable else { return }
            do {
                try await cloudKitService.saveCurationEntry(entry)
            } catch {
                Logger.cloudKit.warning("Failed to save curation entry: \(error.localizedDescription)")
            }
        }
    }

    func removeFromCategory(videoId: String, category: VideoCategory) {
        let entry = CurationEntry(videoId: videoId, category: category, action: .remove)
        curationEntries.append(entry)
        Task {
            await cacheService.saveCurationEntries(curationEntries)
            guard cloudKitAvailable else { return }
            do {
                try await cloudKitService.saveCurationEntry(entry)
            } catch {
                Logger.cloudKit.warning("Failed to save curation removal: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Search History

    func recordSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return }

        // Remove duplicate if same query exists
        searchHistory.removeAll { $0.query.lowercased() == trimmed }

        let entry = SearchHistoryEntry(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
        searchHistory.insert(entry, at: 0)

        // Keep max 20 entries
        if searchHistory.count > 20 {
            searchHistory = Array(searchHistory.prefix(20))
        }

        Task {
            await cacheService.saveSearchHistory(searchHistory)
            guard cloudKitAvailable else { return }
            do {
                try await cloudKitService.saveSearchEntry(entry)
            } catch {
                Logger.cloudKit.warning("Failed to save search entry: \(error.localizedDescription)")
            }
        }
    }

    func deleteSearchEntry(_ entry: SearchHistoryEntry) {
        searchHistory.removeAll { $0.id == entry.id }
        Task {
            await cacheService.saveSearchHistory(searchHistory)
            guard cloudKitAvailable else { return }
            do {
                try await cloudKitService.deleteSearchEntry(entry)
            } catch {
                Logger.cloudKit.warning("Failed to delete search entry: \(error.localizedDescription)")
            }
        }
    }

    func clearSearchHistory() {
        let entriesToDelete = searchHistory
        searchHistory = []
        Task {
            await cacheService.saveSearchHistory(searchHistory)
            guard cloudKitAvailable else { return }
            do {
                try await cloudKitService.deleteAllSearchHistory(entriesToDelete)
            } catch {
                Logger.cloudKit.warning("Failed to clear search history: \(error.localizedDescription)")
            }
        }
    }

    private(set) var popularTags: [String] = []

    private func recomputePopularTags() {
        let allItems = hotshiz + topWeek + topMonth + topDay
        var tagCounts: [String: Int] = [:]
        for item in allItems {
            for tag in item.tags {
                let normalized = tag.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty, normalized.count > 2 else { continue }
                tagCounts[normalized, default: 0] += 1
            }
        }
        popularTags = tagCounts
            .sorted { $0.value > $1.value }
            .prefix(12)
            .map(\.key)
    }

    // MARK: - Settings

    private func saveSettings() async {
        settings.lastModified = Date()
        let snapshot = settings.snapshot
        await cacheService.saveSettings(snapshot)
        guard cloudKitAvailable else { return }
        do {
            try await cloudKitService.saveSettings(snapshot)
        } catch {
            Logger.cloudKit.warning("Failed to save settings: \(error.localizedDescription)")
        }
    }

    // MARK: - Top Shelf

    private func updateTopShelf() {
        let nsfwHidden = !settings.nsfwEnabled
        let mapToShelfItems: ([MediaItem]) -> [TopShelfItem] = { items in
            let visible = nsfwHidden ? items.filter { !$0.isNSFW } : items
            return Array(visible.prefix(10).map {
                TopShelfItem(
                    id: $0.id,
                    title: $0.title,
                    thumbnailURL: $0.thumbnailURL,
                    streamURL: $0.streamURL,
                    description: $0.descriptionText.isEmpty ? nil : $0.descriptionText,
                    kudos: $0.kudosTotal,
                    duration: $0.isVideo ? $0.duration : nil,
                    date: $0.date
                )
            })
        }

        let hotshizItems = mapToShelfItems(hotshiz)
        let topWeekItems = mapToShelfItems(topWeek)
        let latestItems = mapToShelfItems(categoryVideos[.nieuwBinnen] ?? [])

        Logger.cache.info("updateTopShelf: hotshiz=\(hotshizItems.count), topWeek=\(topWeekItems.count), latest=\(latestItems.count)")
        TopShelfDataStore.save(hotshiz: hotshizItems)
        TopShelfDataStore.save(topWeek: topWeekItems)
        TopShelfDataStore.save(latest: latestItems)
        TVTopShelfContentProvider.topShelfContentDidChange()
    }

    // MARK: - Cache Helpers

    func clearAllCaches() async {
        await cacheService.clearCache()
        await ImageCacheService.shared.clearAll()
        await ThumbnailUpgradeService.shared.clearCache()
    }

    func totalCacheSize() async -> Int {
        let apiCacheBytes = await cacheService.cacheSize()
        let imageCacheBytes = await ImageCacheService.shared.diskSize()
        let thumbnailUpgradeBytes = await ThumbnailUpgradeService.shared.cacheSize()
        return apiCacheBytes + imageCacheBytes + thumbnailUpgradeBytes
    }

    // MARK: - Sync Helpers

    private func mergeWatchProgress(remote: [String: WatchProgress]) {
        for (videoId, remoteProgress) in remote {
            if let local = watchProgress[videoId] {
                if remoteProgress.lastWatchedDate > local.lastWatchedDate {
                    watchProgress[videoId] = remoteProgress
                }
            } else {
                watchProgress[videoId] = remoteProgress
            }
        }
        Task { await cacheService.saveWatchProgress(watchProgress) }
    }

    private func mergeSearchHistory(remote: [SearchHistoryEntry]) {
        let existingIds = Set(searchHistory.map(\.id))
        let newEntries = remote.filter { !existingIds.contains($0.id) }
        searchHistory.append(contentsOf: newEntries)
        searchHistory.sort { $0.timestamp > $1.timestamp }
        if searchHistory.count > 20 {
            searchHistory = Array(searchHistory.prefix(20))
        }
        Task { await cacheService.saveSearchHistory(searchHistory) }
    }

    private func mergeCurationEntries(remote: [CurationEntry]) {
        let existingIds = Set(curationEntries.map(\.id))
        let newEntries = remote.filter { !existingIds.contains($0.id) }
        curationEntries.append(contentsOf: newEntries)
        Task { await cacheService.saveCurationEntries(curationEntries) }
    }
}
