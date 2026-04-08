import Foundation
import CloudKit

actor CloudKitService {
    private let container: CKContainer
    private let privateDB: CKDatabase
    private let zoneID: CKRecordZone.ID
    private var changeToken: CKServerChangeToken?
    private var isAvailable = false

    private static let zoneName = "DumpertZone"

    init() {
        self.container = CKContainer.default()
        self.privateDB = container.privateCloudDatabase
        self.zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
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

    func fetchAllWatchProgress() async throws -> [String: WatchProgress] {
        try guardAvailable()
        let query = CKQuery(recordType: "WatchProgress", predicate: NSPredicate(value: true))
        let (results, _) = try await privateDB.records(matching: query, inZoneWith: zoneID)

        var progress: [String: WatchProgress] = [:]
        for (_, result) in results {
            guard let record = try? result.get(),
                  let videoId = record["videoId"] as? String else { continue }
            let watched = record["watchedSeconds"] as? Double ?? 0
            let total = record["totalSeconds"] as? Double ?? 0
            var wp = WatchProgress(videoId: videoId, watchedSeconds: watched, totalSeconds: total)
            wp.isCompleted = (record["isCompleted"] as? Int ?? 0) == 1
            wp.lastWatchedDate = record["lastWatchedDate"] as? Date ?? Date()
            progress[videoId] = wp
        }
        return progress
    }

    // MARK: - User Settings

    func saveSettings(_ settings: UserSettingsSnapshot) async throws {
        try guardAvailable()
        let recordID = CKRecord.ID(recordName: "global_settings", zoneID: zoneID)
        let record = CKRecord(recordType: "UserSettings", recordID: recordID)
        record["minimumKudos"] = settings.minimumKudos as CKRecordValue
        record["autoplayEnabled"] = (settings.autoplayEnabled ? 1 : 0) as CKRecordValue
        record["hideWatched"] = (settings.hideWatched ? 1 : 0) as CKRecordValue
        record["showNegativeKudos"] = (settings.showNegativeKudos ? 1 : 0) as CKRecordValue
        record["thumbnailPreviewEnabled"] = (settings.thumbnailPreviewEnabled ? 1 : 0) as CKRecordValue
        record["upNextOverlayEnabled"] = (settings.upNextOverlayEnabled ? 1 : 0) as CKRecordValue
        record["upNextCountdownSeconds"] = settings.upNextCountdownSeconds as CKRecordValue
        record["upNextMinimumVideoSeconds"] = settings.upNextMinimumVideoSeconds as CKRecordValue
        record["topCommentMode"] = settings.topCommentMode.rawValue as CKRecordValue
        record["readingSpeed"] = settings.readingSpeed.rawValue as CKRecordValue
        record["lastModified"] = settings.lastModified as CKRecordValue

        _ = try await privateDB.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
    }

    func fetchSettings() async throws -> UserSettingsSnapshot? {
        try guardAvailable()
        let recordID = CKRecord.ID(recordName: "global_settings", zoneID: zoneID)
        do {
            let record = try await privateDB.record(for: recordID)
            return UserSettingsSnapshot(
                minimumKudos: record["minimumKudos"] as? Int ?? 0,
                autoplayEnabled: (record["autoplayEnabled"] as? Int ?? 1) == 1,
                hideWatched: (record["hideWatched"] as? Int ?? 0) == 1,
                showNegativeKudos: (record["showNegativeKudos"] as? Int ?? 0) == 1,
                thumbnailPreviewEnabled: (record["thumbnailPreviewEnabled"] as? Int ?? 1) == 1,
                upNextOverlayEnabled: (record["upNextOverlayEnabled"] as? Int ?? 1) == 1,
                upNextCountdownSeconds: record["upNextCountdownSeconds"] as? Int ?? 5,
                upNextMinimumVideoSeconds: record["upNextMinimumVideoSeconds"] as? Int ?? 60,
                topCommentMode: (record["topCommentMode"] as? String).flatMap(TopCommentMode.init(rawValue:)) ?? {
                    // Migration: old CloudKit records stored Bool as Int
                    if let oldValue = record["showTopComment"] as? Int {
                        return oldValue == 1 ? .all : .off
                    }
                    return .all
                }(),
                readingSpeed: (record["readingSpeed"] as? Int).flatMap(ReadingSpeed.init(rawValue:)) ?? .normal,
                lastModified: record["lastModified"] as? Date ?? Date()
            )
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
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

    func fetchAllCurationEntries() async throws -> [CurationEntry] {
        try guardAvailable()
        let query = CKQuery(recordType: "CurationEntry", predicate: NSPredicate(value: true))
        let (results, _) = try await privateDB.records(matching: query, inZoneWith: zoneID)

        var entries: [CurationEntry] = []
        for (_, result) in results {
            guard let record = try? result.get(),
                  let videoId = record["videoId"] as? String,
                  let categoryRaw = record["category"] as? String,
                  let category = VideoCategory(rawValue: categoryRaw),
                  let actionRaw = record["action"] as? String,
                  let action = CurationAction(rawValue: actionRaw) else { continue }
            let entry = CurationEntry(videoId: videoId, category: category, action: action)
            entries.append(entry)
        }
        return entries
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

    func fetchAllSearchHistory() async throws -> [SearchHistoryEntry] {
        try guardAvailable()
        let query = CKQuery(recordType: "SearchHistory", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        let (results, _) = try await privateDB.records(matching: query, inZoneWith: zoneID)

        var entries: [SearchHistoryEntry] = []
        for (recordID, result) in results {
            guard let record = try? result.get(),
                  let query = record["query"] as? String else { continue }
            let idString = recordID.recordName.replacingOccurrences(of: "search_", with: "")
            guard let uuid = UUID(uuidString: idString) else { continue }
            let timestamp = record["timestamp"] as? Date ?? Date()
            let entry = SearchHistoryEntry(id: uuid, query: query, timestamp: timestamp)
            entries.append(entry)
        }
        return entries
    }

    // MARK: - Delta Sync

    func fetchChanges() async throws -> CloudKitChanges {
        try guardAvailable()
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
            if case .success(let (token, _, _)) = result {
                collector.setToken(token)
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

        self.changeToken = collector.token
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

    var changedRecords: [CKRecord] {
        lock.withLock { _changedRecords }
    }

    var deletedRecordIDs: [CKRecord.ID] {
        lock.withLock { _deletedRecordIDs }
    }

    var token: CKServerChangeToken? {
        lock.withLock { _token }
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
}
