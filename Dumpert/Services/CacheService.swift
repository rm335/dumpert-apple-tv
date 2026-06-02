import Foundation
import os

actor CacheService {
    private let cacheDirectory: URL
    private let maxCacheSize: Int = 50 * 1024 * 1024 // 50MB
    private var cachedDiskSize: Int?

    /// Production initializer — caches go into the standard Caches directory.
    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.init(cacheDirectory: caches.appendingPathComponent("DumpertCache", isDirectory: true))
    }

    /// Test-friendly initializer that lets each test use its own isolated
    /// directory. Avoids parallel-test pollution where another suite's
    /// markAsWatched write would overwrite this suite's seeded data.
    init(cacheDirectory: URL) {
        self.cacheDirectory = cacheDirectory
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Watch Progress

    private var watchProgressURL: URL {
        cacheDirectory.appendingPathComponent("watch_progress.json")
    }

    func loadWatchProgress() -> [String: WatchProgress] {
        guard let data = try? Data(contentsOf: watchProgressURL),
              let progress = try? JSONDecoder().decode([String: WatchProgress].self, from: data) else {
            return [:]
        }
        return progress
    }

    func saveWatchProgress(_ progress: [String: WatchProgress]) {
        do {
            let data = try JSONEncoder().encode(progress)
            try data.write(to: watchProgressURL, options: .atomic)
        } catch {
            Logger.cache.warning("Failed to save watch progress: \(error.localizedDescription)")
        }
        cachedDiskSize = nil
    }

    // MARK: - Settings

    private var settingsURL: URL {
        cacheDirectory.appendingPathComponent("settings.json")
    }

    func loadSettings() -> UserSettingsSnapshot {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(UserSettingsSnapshot.self, from: data) else {
            return UserSettingsSnapshot()
        }
        return settings
    }

    func saveSettings(_ settings: UserSettingsSnapshot) {
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: settingsURL, options: .atomic)
        } catch {
            Logger.cache.warning("Failed to save settings: \(error.localizedDescription)")
        }
        cachedDiskSize = nil
    }

    // MARK: - Curation Entries

    private var curationURL: URL {
        cacheDirectory.appendingPathComponent("curation_entries.json")
    }

    func loadCurationEntries() -> [CurationEntry] {
        guard let data = try? Data(contentsOf: curationURL),
              let entries = try? JSONDecoder().decode([CurationEntry].self, from: data) else {
            return []
        }
        return entries
    }

    func saveCurationEntries(_ entries: [CurationEntry]) {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: curationURL, options: .atomic)
        } catch {
            Logger.cache.warning("Failed to save curation entries: \(error.localizedDescription)")
        }
        cachedDiskSize = nil
    }

    // MARK: - Search History

    private var searchHistoryURL: URL {
        cacheDirectory.appendingPathComponent("search_history.json")
    }

    func loadSearchHistory() -> [SearchHistoryEntry] {
        guard let data = try? Data(contentsOf: searchHistoryURL),
              let entries = try? JSONDecoder().decode([SearchHistoryEntry].self, from: data) else {
            return []
        }
        return entries
    }

    func saveSearchHistory(_ entries: [SearchHistoryEntry]) {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: searchHistoryURL, options: .atomic)
        } catch {
            Logger.cache.warning("Failed to save search history: \(error.localizedDescription)")
        }
        cachedDiskSize = nil
    }

    // MARK: - Media Item Cache

    func loadCachedMediaItems(for key: String) -> [MediaItem]? {
        let url = cacheDirectory.appendingPathComponent("videos_\(key).json")
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([CachedMediaItem].self, from: data) else {
            return nil
        }
        return items.map { $0.toMediaItem() }
    }

    func cacheMediaItems(_ items: [MediaItem], for key: String) {
        let cached = items.map { CachedMediaItem(from: $0) }
        do {
            let data = try JSONEncoder().encode(cached)
            var url = cacheDirectory.appendingPathComponent("videos_\(key).json")
            try data.write(to: url, options: .atomic)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? url.setResourceValues(resourceValues)
        } catch {
            Logger.cache.warning("Failed to cache media items for '\(key)': \(error.localizedDescription)")
        }
        cachedDiskSize = nil

        evictIfNeeded()
    }

    // MARK: - Cache Management

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        cachedDiskSize = nil
    }

    func cacheSize() -> Int {
        if let cached = cachedDiskSize {
            return cached
        }
        let size = computeDiskSize()
        cachedDiskSize = size
        return size
    }

    private func computeDiskSize() -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var totalSize = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            totalSize += size
        }
        return totalSize
    }

    /// Evicts oldest video cache files when total cache exceeds maxCacheSize
    private func evictIfNeeded() {
        let currentSize = cacheSize()
        guard currentSize > maxCacheSize else { return }

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        // Collect video cache files (evictable), sorted by oldest first
        var cacheFiles: [(url: URL, date: Date, size: Int)] = []
        let protectedNames: Set<String> = ["watch_progress.json", "settings.json", "curation_entries.json", "search_history.json"]

        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent
            guard name.hasPrefix("videos_"), name.hasSuffix(".json") else {
                if protectedNames.contains(name) { continue }
                continue
            }
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = values?.fileSize ?? 0
            let date = values?.contentModificationDate ?? Date.distantPast
            cacheFiles.append((url: fileURL, date: date, size: size))
        }

        // Sort oldest first
        cacheFiles.sort { $0.date < $1.date }

        var freedSize = 0
        let targetSize = maxCacheSize * 3 / 4 // Free down to 75% capacity
        let bytesToFree = currentSize - targetSize

        for file in cacheFiles {
            guard freedSize < bytesToFree else { break }
            try? fm.removeItem(at: file.url)
            freedSize += file.size
        }

        cachedDiskSize = nil
    }
}

// MARK: - CachedMediaItem (Codable wrapper for MediaItem)

private struct CachedMediaItem: Codable {
    let id: String
    let title: String
    let descriptionText: String
    let date: Date?
    let duration: Int
    let kudosTotal: Int
    let viewsTotal: Int?
    let thumbnailURL: String?
    let streamURL: String?
    let videoFileURL: String?
    let imageURL: String?
    let tags: [String]
    let isNSFW: Bool
    let mediaType: String // "video" or "photo"

    init(from item: MediaItem) {
        self.id = item.id
        self.title = item.title
        self.descriptionText = item.descriptionText
        self.date = item.date
        self.kudosTotal = item.kudosTotal
        self.viewsTotal = item.viewsTotal
        self.thumbnailURL = item.thumbnailURL?.absoluteString
        self.tags = item.tags
        self.isNSFW = item.isNSFW

        switch item {
        case .video(let video):
            self.mediaType = "video"
            self.duration = video.duration
            self.streamURL = video.streamURL?.absoluteString
            self.videoFileURL = video.videoFileURL?.absoluteString
            self.imageURL = nil
        case .photo(let photo):
            self.mediaType = "photo"
            self.duration = 0
            self.streamURL = nil
            self.videoFileURL = nil
            self.imageURL = photo.imageURL?.absoluteString
        }
    }

    func toMediaItem() -> MediaItem {
        if mediaType == "photo" {
            return .photo(Photo(
                id: id,
                title: title,
                descriptionText: descriptionText,
                date: date,
                kudosTotal: kudosTotal,
                viewsTotal: viewsTotal ?? 0,
                thumbnailURL: thumbnailURL.flatMap { URL(string: $0) },
                imageURL: imageURL.flatMap { URL(string: $0) },
                tags: tags,
                isNSFW: isNSFW
            ))
        } else {
            return .video(Video(
                id: id,
                title: title,
                descriptionText: descriptionText,
                date: date,
                duration: duration,
                kudosTotal: kudosTotal,
                viewsTotal: viewsTotal ?? 0,
                thumbnailURL: thumbnailURL.flatMap { URL(string: $0) },
                streamURL: streamURL.flatMap { URL(string: $0) },
                videoFileURL: videoFileURL.flatMap { URL(string: $0) },
                tags: tags,
                isNSFW: isNSFW
            ))
        }
    }
}
