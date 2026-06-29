import Foundation
import CloudKit
import os

actor CloudKitService {
    private let container: CKContainer
    private let privateDB: CKDatabase
    private let zoneID: CKRecordZone.ID
    private var changeToken: CKServerChangeToken?
    private var isAvailable = false

    private static let zoneName = "DumpertZone"
    private static let changeTokenKey = "cloudkit_change_token"

    init() {
        self.container = CKContainer.default()
        self.privateDB = container.privateCloudDatabase
        self.zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
        // Restore the persisted change token so a cold launch resumes delta sync
        // from where it left off — a tokenless fetch returns no deletion
        // tombstones, so without this records deleted elsewhere resurrect here.
        self.changeToken = Self.loadPersistedChangeToken()
    }

    private static func loadPersistedChangeToken() -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: changeTokenKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func persistChangeToken(_ token: CKServerChangeToken) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: Self.changeTokenKey)
    }

    private func clearPersistedChangeToken() {
        changeToken = nil
        UserDefaults.standard.removeObject(forKey: Self.changeTokenKey)
    }

    // MARK: - Account Check

    private func checkAccountStatus() async -> Bool {
        do {
            let status = try await container.accountStatus()
            return status == .available
        } catch {
            return false
        }
    }

    private func guardAvailable() throws {
        guard isAvailable else {
            throw CKError(.notAuthenticated)
        }
    }

    // MARK: - Setup

    func setupZone() async throws {
        isAvailable = await checkAccountStatus()
        try guardAvailable()
        let zone = CKRecordZone(zoneID: zoneID)
        try await privateDB.save(zone)
    }

    // MARK: - Watch Progress

    func saveWatchProgress(_ progress: WatchProgress) async throws {
        try guardAvailable()
        let recordID = CKRecord.ID(recordName: "watch_\(progress.videoId)", zoneID: zoneID)
        let record = CKRecord(recordType: "WatchProgress", recordID: recordID)
        record["videoId"] = progress.videoId as CKRecordValue
        record["watchedSeconds"] = progress.watchedSeconds as CKRecordValue
        record["totalSeconds"] = progress.totalSeconds as CKRecordValue
        record["isCompleted"] = (progress.isCompleted ? 1 : 0) as CKRecordValue
        record["lastWatchedDate"] = progress.lastWatchedDate as CKRecordValue

        _ = try await privateDB.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
    }

    // MARK: - User Settings

    func saveSettings(_ settings: UserSettingsSnapshot) async throws {
        try guardAvailable()
        let recordID = CKRecord.ID(recordName: "global_settings", zoneID: zoneID)
        let record = CKRecord(recordType: "UserSettings", recordID: recordID)
        Self.populate(record: record, with: settings)

        _ = try await privateDB.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
    }

    func fetchSettings() async throws -> UserSettingsSnapshot? {
        try guardAvailable()
        let recordID = CKRecord.ID(recordName: "global_settings", zoneID: zoneID)
        do {
            let record = try await privateDB.record(for: recordID)
            return Self.makeSettings(from: record, fallback: UserSettingsSnapshot())
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    /// Writes every UserSettingsSnapshot field onto the CKRecord. Keeping save and
    /// read symmetric in one place prevents the bug where a field is saved but
    /// never read (or vice versa) and the user's value gets reset during sync.
    static func populate(record: CKRecord, with settings: UserSettingsSnapshot) {
        record["minimumKudos"] = settings.minimumKudos as CKRecordValue
        record["autoplayEnabled"] = (settings.autoplayEnabled ? 1 : 0) as CKRecordValue
        record["hideWatched"] = (settings.hideWatched ? 1 : 0) as CKRecordValue
        record["reetenMinimumMinutes"] = settings.reetenMinimumMinutes as CKRecordValue
        record["showNegativeKudos"] = (settings.showNegativeKudos ? 1 : 0) as CKRecordValue
        record["nsfwEnabled"] = (settings.nsfwEnabled ? 1 : 0) as CKRecordValue
        record["thumbnailPreviewEnabled"] = (settings.thumbnailPreviewEnabled ? 1 : 0) as CKRecordValue
        record["smartThumbnailsEnabled"] = (settings.smartThumbnailsEnabled ? 1 : 0) as CKRecordValue
        record["tileSize"] = settings.tileSize.rawValue as CKRecordValue
        record["upNextOverlayEnabled"] = (settings.upNextOverlayEnabled ? 1 : 0) as CKRecordValue
        record["upNextCountdownSeconds"] = settings.upNextCountdownSeconds as CKRecordValue
        record["upNextMinimumVideoSeconds"] = settings.upNextMinimumVideoSeconds as CKRecordValue
        record["topCommentMode"] = settings.topCommentMode.rawValue as CKRecordValue
        record["readingSpeed"] = settings.readingSpeed.rawValue as CKRecordValue
        record["remoteSkipMode"] = settings.remoteSkipMode.rawValue as CKRecordValue
        record["showResumeOverlay"] = (settings.showResumeOverlay ? 1 : 0) as CKRecordValue
        record["lastModified"] = settings.lastModified as CKRecordValue
    }

    /// Reads every UserSettingsSnapshot field off a CKRecord. Any field that's
    /// absent from the record falls back to the supplied snapshot's value — this
    /// preserves the local value when older clients (or future clients) omit a
    /// key, instead of silently overwriting it with a hard-coded default.
    static func makeSettings(from record: CKRecord, fallback: UserSettingsSnapshot) -> UserSettingsSnapshot {
        // Migration: old CloudKit records stored Bool topComment as Int "showTopComment"
        let topCommentMode: TopCommentMode = (record["topCommentMode"] as? String)
            .flatMap(TopCommentMode.init(rawValue:))
            ?? (record["showTopComment"] as? Int).map { $0 == 1 ? .all : .off }
            ?? fallback.topCommentMode

        return UserSettingsSnapshot(
            minimumKudos: record["minimumKudos"] as? Int ?? fallback.minimumKudos,
            autoplayEnabled: (record["autoplayEnabled"] as? Int).map { $0 == 1 } ?? fallback.autoplayEnabled,
            hideWatched: (record["hideWatched"] as? Int).map { $0 == 1 } ?? fallback.hideWatched,
            reetenMinimumMinutes: record["reetenMinimumMinutes"] as? Int ?? fallback.reetenMinimumMinutes,
            showNegativeKudos: (record["showNegativeKudos"] as? Int).map { $0 == 1 } ?? fallback.showNegativeKudos,
            nsfwEnabled: (record["nsfwEnabled"] as? Int).map { $0 == 1 } ?? fallback.nsfwEnabled,
            thumbnailPreviewEnabled: (record["thumbnailPreviewEnabled"] as? Int).map { $0 == 1 } ?? fallback.thumbnailPreviewEnabled,
            smartThumbnailsEnabled: (record["smartThumbnailsEnabled"] as? Int).map { $0 == 1 } ?? fallback.smartThumbnailsEnabled,
            tileSize: (record["tileSize"] as? String).flatMap(TileSize.init(rawValue:)) ?? fallback.tileSize,
            upNextOverlayEnabled: (record["upNextOverlayEnabled"] as? Int).map { $0 == 1 } ?? fallback.upNextOverlayEnabled,
            upNextCountdownSeconds: record["upNextCountdownSeconds"] as? Int ?? fallback.upNextCountdownSeconds,
            upNextMinimumVideoSeconds: record["upNextMinimumVideoSeconds"] as? Int ?? fallback.upNextMinimumVideoSeconds,
            topCommentMode: topCommentMode,
            readingSpeed: (record["readingSpeed"] as? Int).flatMap(ReadingSpeed.init(rawValue:)) ?? fallback.readingSpeed,
            remoteSkipMode: (record["remoteSkipMode"] as? String).flatMap(RemoteSkipMode.init(rawValue:)) ?? fallback.remoteSkipMode,
            showResumeOverlay: (record["showResumeOverlay"] as? Int).map { $0 == 1 } ?? fallback.showResumeOverlay,
            lastModified: record["lastModified"] as? Date ?? fallback.lastModified
        )
    }

    // MARK: - Curation Entries

    func saveCurationEntry(_ entry: CurationEntry) async throws {
        try guardAvailable()
        let recordID = CKRecord.ID(recordName: entry.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: "CurationEntry", recordID: recordID)
        record["videoId"] = entry.videoId as CKRecordValue
        record["category"] = entry.category.rawValue as CKRecordValue
        record["action"] = entry.action.rawValue as CKRecordValue
        record["timestamp"] = entry.timestamp as CKRecordValue

        _ = try await privateDB.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
    }

    // MARK: - Search History

    func saveSearchEntry(_ entry: SearchHistoryEntry) async throws {
        try guardAvailable()
        let recordID = CKRecord.ID(recordName: "search_\(entry.id.uuidString)", zoneID: zoneID)
        let record = CKRecord(recordType: "SearchHistory", recordID: recordID)
        record["query"] = entry.query as CKRecordValue
        record["timestamp"] = entry.timestamp as CKRecordValue

        _ = try await privateDB.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
    }

    func deleteSearchEntry(_ entry: SearchHistoryEntry) async throws {
        try guardAvailable()
        let recordID = CKRecord.ID(recordName: "search_\(entry.id.uuidString)", zoneID: zoneID)
        _ = try await privateDB.modifyRecords(saving: [], deleting: [recordID])
    }

    func deleteAllSearchHistory(_ entries: [SearchHistoryEntry]) async throws {
        try guardAvailable()
        let recordIDs = entries.map { CKRecord.ID(recordName: "search_\($0.id.uuidString)", zoneID: zoneID) }
        guard !recordIDs.isEmpty else { return }
        _ = try await privateDB.modifyRecords(saving: [], deleting: recordIDs)
    }

    // MARK: - Delta Sync

    func fetchChanges() async throws -> CloudKitChanges {
        try guardAvailable()
        do {
            return try await performFetchChanges()
        } catch let error as CKError where error.code == .changeTokenExpired {
            // The server purged our persisted token (too old, or the zone was
            // re-created elsewhere). Discard it and re-fetch the whole zone.
            Logger.cloudKit.info("CloudKit change token expired; resetting and re-fetching full zone")
            clearPersistedChangeToken()
            return try await performFetchChanges()
        }
    }

    private func performFetchChanges() async throws -> CloudKitChanges {
        let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        config.previousServerChangeToken = changeToken

        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneID],
            configurationsByRecordZoneID: [zoneID: config]
        )

        // Use Sendable containers to collect results from callbacks
        let collector = ChangeCollector()

        operation.recordWasChangedBlock = { _, result in
            guard let record = try? result.get() else { return }
            collector.addChanged(record)
        }

        operation.recordWithIDWasDeletedBlock = { recordID, _ in
            collector.addDeleted(recordID)
        }

        operation.recordZoneChangeTokensUpdatedBlock = { _, token, _ in
            if let token {
                collector.setToken(token)
            }
        }

        operation.recordZoneFetchResultBlock = { _, result in
            switch result {
            case .success(let (token, _, _)):
                collector.setToken(token)
            case .failure(let error):
                // Per-zone failures (e.g. an expired token) aren't always
                // rethrown by the operation-level result block; capture it so
                // fetchChanges can react.
                collector.setError(error)
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            privateDB.add(operation)
        }

        if let zoneError = collector.error {
            throw zoneError
        }

        // Only advance and persist the token after a fully successful fetch.
        // Persisting lets the next cold launch resume from here and receive
        // deletion tombstones instead of doing a tokenless full re-fetch.
        if let token = collector.token {
            self.changeToken = token
            persistChangeToken(token)
        }
        return CloudKitChanges(
            changedRecords: collector.changedRecords,
            deletedRecordIDs: collector.deletedRecordIDs
        )
    }
}

struct CloudKitChanges: Sendable {
    var changedRecords: [CKRecord] = []
    var deletedRecordIDs: [CKRecord.ID] = []
}

// Thread-safe collector for CKFetchRecordZoneChangesOperation callbacks
private final class ChangeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _changedRecords: [CKRecord] = []
    private var _deletedRecordIDs: [CKRecord.ID] = []
    private var _token: CKServerChangeToken?
    private var _error: Error?

    var changedRecords: [CKRecord] {
        lock.withLock { _changedRecords }
    }

    var deletedRecordIDs: [CKRecord.ID] {
        lock.withLock { _deletedRecordIDs }
    }

    var token: CKServerChangeToken? {
        lock.withLock { _token }
    }

    var error: Error? {
        lock.withLock { _error }
    }

    func addChanged(_ record: CKRecord) {
        lock.withLock { _changedRecords.append(record) }
    }

    func addDeleted(_ recordID: CKRecord.ID) {
        lock.withLock { _deletedRecordIDs.append(recordID) }
    }

    func setToken(_ token: CKServerChangeToken) {
        lock.withLock { _token = token }
    }

    func setError(_ error: Error) {
        lock.withLock { _error = error }
    }
}
