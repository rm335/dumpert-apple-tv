import Foundation
import os

enum TopShelfDataStore: Sendable {
    static let appGroupIdentifier = "group.nl.dumpert.tvos"
    private static let logger = Logger(subsystem: "nl.dumpert.tvos.topshelf", category: "datastore")
    private static let hotshizKey = "topshelf_hotshiz"
    private static let topWeekKey = "topshelf_topweek"
    private static let latestKey = "topshelf_latest"
    private static let lastUpdatedKey = "topshelf_last_updated"
    private static let nsfwEnabledKey = "nsfw_enabled"

    // MARK: - NSFW Preference (shared from the app)

    /// The user's "show NSFW" preference, shared from the app via the App Group
    /// so the Top Shelf extension can honor it. Fails safe to `false` when the
    /// app has never written the flag (fresh install, first run after an update,
    /// or App Group unavailable): the Top Shelf is a public home-screen surface,
    /// so an unknown preference must hide NSFW rather than show it. The app
    /// seeds the real value on its first launch.
    static var nsfwEnabled: Bool { nsfwEnabledIfSet ?? false }

    /// Same as ``nsfwEnabled`` but `nil` when the app has never written the flag,
    /// so callers can fall back to another source.
    static var nsfwEnabledIfSet: Bool? {
        UserDefaults(suiteName: appGroupIdentifier)?.object(forKey: nsfwEnabledKey) as? Bool
    }

    /// Mirrors the app's NSFW preference into the App Group.
    static func setNSFWEnabled(_ enabled: Bool) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            logger.fault("setNSFWEnabled: App Group UserDefaults nil — not provisioned")
            return
        }
        defaults.set(enabled, forKey: nsfwEnabledKey)
        // Same cross-process flush the item-save path uses, so the extension
        // sees the new value immediately after a toggle.
        defaults.synchronize()
    }

    /// Returns true if cached data is older than the given interval (default 15 min).
    static var isStale: Bool {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let lastUpdated = defaults.object(forKey: lastUpdatedKey) as? Date else {
            return true
        }
        return Date().timeIntervalSince(lastUpdated) > 15 * 60
    }

    // MARK: - Diagnostics

    static func diagnose() {
        let process = ProcessInfo.processInfo.processName
        logger.notice("=== TopShelf diagnose from process: \(process) ===")

        // Check container URL
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let exists = FileManager.default.fileExists(atPath: url.path)
            logger.notice("Container URL: \(url.path) exists=\(exists)")
        } else {
            logger.fault("Container URL is nil — App Group NOT provisioned")
        }

        // Check UserDefaults read/write
        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            let testKey = "topshelf_diag"
            defaults.set(42, forKey: testKey)
            defaults.synchronize()
            let val = defaults.integer(forKey: testKey)
            logger.notice("UserDefaults test: wrote 42, read \(val) — \(val == 42 ? "OK" : "BROKEN")")
            defaults.removeObject(forKey: testKey)

            // Check if hotshiz data exists
            let hasData = defaults.data(forKey: hotshizKey) != nil
            logger.notice("UserDefaults has hotshiz data: \(hasData)")
        } else {
            logger.fault("UserDefaults(suiteName:) returned nil")
        }
    }

    // MARK: - Save

    static func save(hotshiz items: [TopShelfItem]) { save(items, forKey: hotshizKey) }
    static func save(topWeek items: [TopShelfItem]) { save(items, forKey: topWeekKey) }
    static func save(latest items: [TopShelfItem]) { save(items, forKey: latestKey) }

    // MARK: - Load

    static func loadHotshiz() -> [TopShelfItem] { load(forKey: hotshizKey) }
    static func loadTopWeek() -> [TopShelfItem] { load(forKey: topWeekKey) }
    static func loadLatest() -> [TopShelfItem] { load(forKey: latestKey) }

    // MARK: - Private Helpers

    private static func save(_ items: [TopShelfItem], forKey key: String) {
        guard !items.isEmpty else {
            logger.info("save(\(key)) called with empty array, skipping")
            return
        }

        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            logger.fault("save: UserDefaults(suiteName:) is nil — App Group not provisioned")
            return
        }

        do {
            let data = try JSONEncoder().encode(items)
            defaults.set(data, forKey: key)
            defaults.synchronize()

            let readBack = defaults.data(forKey: key)
            if readBack != nil {
                logger.notice("Saved \(items.count) items to \(key) (\(data.count) bytes) — verified OK")
                defaults.set(Date(), forKey: lastUpdatedKey)
            } else {
                logger.fault("Save FAILED for \(key) — wrote data but readback is nil")
            }
        } catch {
            logger.fault("Encode failed for \(key): \(error.localizedDescription)")
        }
    }

    private static func load(forKey key: String) -> [TopShelfItem] {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            logger.fault("load: UserDefaults(suiteName:) is nil — App Group not provisioned")
            return []
        }

        guard let data = defaults.data(forKey: key) else {
            logger.notice("No data for \(key) in UserDefaults")
            return []
        }

        do {
            let items = try JSONDecoder().decode([TopShelfItem].self, from: data)
            logger.notice("Loaded \(items.count) items from \(key) (\(data.count) bytes)")
            return nsfwFiltered(items)
        } catch {
            logger.fault("Decode failed for \(key): \(error.localizedDescription)")
            return []
        }
    }

    /// Read-side NSFW enforcement, applied to every cache load so no reader can
    /// serve NSFW items the current preference forbids — even from caches
    /// written before the preference changed (or before the `nsfw` flag
    /// existed: those items have `nsfw == nil` and are dropped, not trusted).
    private static func nsfwFiltered(_ items: [TopShelfItem]) -> [TopShelfItem] {
        guard !nsfwEnabled else { return items }
        let safe = items.filter { $0.nsfw == false }
        if safe.count != items.count {
            logger.notice("NSFW hidden: dropped \(items.count - safe.count) of \(items.count) cached items")
        }
        return safe
    }
}
