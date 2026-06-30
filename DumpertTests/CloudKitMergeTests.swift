import Testing
import Foundation
import CloudKit
@testable import Dumpert

/// Regression tests for VideoRepository.applyCloudKitChanges.
///
/// Bugs being pinned:
/// 1. Merged CloudKit changes were never persisted to the local cache, so a
///    launch without CloudKit would lose them.
/// 2. Search history merges appended in arbitrary order and ignored the
///    20-entry cap that recordSearch enforces locally — the UI would show
///    an unsorted, unbounded list right after sync.
/// 3. Record deletions from other devices were ignored entirely.
@Suite("CloudKit Merge Tests")
@MainActor
struct CloudKitMergeTests {

    private let zoneID = CKRecordZone.ID(zoneName: "Test", ownerName: CKCurrentUserDefaultName)

    private func makeRepo() -> VideoRepository {
        VideoRepository()
    }

    // MARK: - Search history ordering and cap

    @Test("CloudKit search history merge sorts newest-first and caps at 20")
    func searchHistoryMergeSortsAndCaps() {
        let repo = makeRepo()
        let now = Date()

        // Build 25 search records from CloudKit spanning the last 25 days, ordered
        // newest-last on purpose so we can assert the merge sorts them.
        var records: [CKRecord] = []
        for offset in (1...25).reversed() {
            let uuid = UUID()
            let recordID = CKRecord.ID(recordName: "search_\(uuid.uuidString)", zoneID: zoneID)
            let record = CKRecord(recordType: "SearchHistory", recordID: recordID)
            record["query"] = "query-\(offset)" as CKRecordValue
            record["timestamp"] = now.addingTimeInterval(TimeInterval(-offset * 86400)) as CKRecordValue
            records.append(record)
        }

        repo.applyCloudKitChanges(CloudKitChanges(changedRecords: records, deletedRecordIDs: []))

        #expect(repo.searchHistory.count == 20, "Should be capped at 20 like recordSearch enforces")
        // Should be sorted newest-first (smallest day-offset first → "query-1")
        let queries = repo.searchHistory.map(\.query)
        #expect(queries.first == "query-1")
        let timestamps = repo.searchHistory.map(\.timestamp)
        #expect(timestamps == timestamps.sorted(by: >), "Newest-first ordering required for UI")
    }

    // MARK: - Deletion handling

    @Test("CloudKit watch-progress deletion removes the local entry")
    func deletionRemovesWatchProgress() {
        let repo = makeRepo()

        // Seed via the merge path (looks like a remote update).
        let recordID = CKRecord.ID(recordName: "watch_video-123", zoneID: zoneID)
        let record = CKRecord(recordType: "WatchProgress", recordID: recordID)
        record["videoId"] = "video-123" as CKRecordValue
        record["watchedSeconds"] = 30.0 as CKRecordValue
        record["totalSeconds"] = 100.0 as CKRecordValue
        record["lastWatchedDate"] = Date() as CKRecordValue

        repo.applyCloudKitChanges(CloudKitChanges(changedRecords: [record], deletedRecordIDs: []))
        #expect(repo.watchProgress["video-123"] != nil)

        // Now simulate the same video being deleted from another device.
        repo.applyCloudKitChanges(CloudKitChanges(changedRecords: [], deletedRecordIDs: [recordID]))
        #expect(repo.watchProgress["video-123"] == nil, "Deletion from CloudKit should propagate")
    }

    @Test("CloudKit search-history deletion removes the local entry by UUID")
    func deletionRemovesSearchHistoryEntry() {
        let repo = makeRepo()
        let uuid = UUID()
        let recordID = CKRecord.ID(recordName: "search_\(uuid.uuidString)", zoneID: zoneID)
        let record = CKRecord(recordType: "SearchHistory", recordID: recordID)
        record["query"] = "test" as CKRecordValue
        record["timestamp"] = Date() as CKRecordValue

        repo.applyCloudKitChanges(CloudKitChanges(changedRecords: [record], deletedRecordIDs: []))
        #expect(repo.searchHistory.contains(where: { $0.id == uuid }))

        repo.applyCloudKitChanges(CloudKitChanges(changedRecords: [], deletedRecordIDs: [recordID]))
        #expect(!repo.searchHistory.contains(where: { $0.id == uuid }))
    }

    @Test("CloudKit curation deletion removes the merged entry (un-curation syncs)")
    func deletionRemovesCurationEntry() {
        let repo = makeRepo()

        // A curation entry created on another device: its CKRecord recordName is
        // the entry's UUID, exactly how saveCurationEntry writes it.
        let uuid = UUID()
        let recordID = CKRecord.ID(recordName: uuid.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: "CurationEntry", recordID: recordID)
        record["videoId"] = "video-9" as CKRecordValue
        record["category"] = VideoCategory.dashcam.rawValue as CKRecordValue
        record["action"] = CurationAction.add.rawValue as CKRecordValue
        record["timestamp"] = Date() as CKRecordValue

        repo.applyCloudKitChanges(CloudKitChanges(changedRecords: [record], deletedRecordIDs: []))
        #expect(repo.curationEntries.contains { $0.id == uuid },
                "Merged entry must keep the record id, not mint a fresh UUID")

        // Un-curated on the other device → tombstone carries the recordName UUID.
        repo.applyCloudKitChanges(CloudKitChanges(changedRecords: [], deletedRecordIDs: [recordID]))
        #expect(!repo.curationEntries.contains { $0.id == uuid },
                "Deletion must match the local entry by id so un-curation syncs")
    }

    // MARK: - isCompleted flag survival

    @Test("A stored isCompleted flag survives the delta merge regardless of the watched ratio")
    func storedIsCompletedSurvivesMerge() {
        let repo = makeRepo()

        // markAsWatched scenario: explicitly completed but 0/0 seconds, so the
        // ratio-derived value would be false.
        let markedID = CKRecord.ID(recordName: "watch_marked", zoneID: zoneID)
        let marked = CKRecord(recordType: "WatchProgress", recordID: markedID)
        marked["videoId"] = "marked" as CKRecordValue
        marked["watchedSeconds"] = 0.0 as CKRecordValue
        marked["totalSeconds"] = 0.0 as CKRecordValue
        marked["isCompleted"] = 1 as CKRecordValue
        marked["lastWatchedDate"] = Date() as CKRecordValue

        // toggleWatched scenario: watched 95% but explicitly un-completed, so the
        // ratio-derived value would be true.
        let toggledID = CKRecord.ID(recordName: "watch_toggled", zoneID: zoneID)
        let toggled = CKRecord(recordType: "WatchProgress", recordID: toggledID)
        toggled["videoId"] = "toggled" as CKRecordValue
        toggled["watchedSeconds"] = 95.0 as CKRecordValue
        toggled["totalSeconds"] = 100.0 as CKRecordValue
        toggled["isCompleted"] = 0 as CKRecordValue
        toggled["lastWatchedDate"] = Date() as CKRecordValue

        repo.applyCloudKitChanges(CloudKitChanges(changedRecords: [marked, toggled], deletedRecordIDs: []))

        #expect(repo.watchProgress["marked"]?.isCompleted == true,
                "Explicit isCompleted=1 must survive even when the 0/0 ratio says incomplete")
        #expect(repo.watchProgress["toggled"]?.isCompleted == false,
                "Explicit isCompleted=0 must win over the >=0.9 ratio")
    }

    // MARK: - Idempotency and conflict resolution

    @Test("Older remote watch progress does not overwrite newer local progress")
    func olderRemoteDoesNotOverwriteNewerLocal() {
        let repo = makeRepo()
        let now = Date()

        // Seed with newer local state (via the merge path itself).
        let newerID = CKRecord.ID(recordName: "watch_v1", zoneID: zoneID)
        let newer = CKRecord(recordType: "WatchProgress", recordID: newerID)
        newer["videoId"] = "v1" as CKRecordValue
        newer["watchedSeconds"] = 80.0 as CKRecordValue
        newer["totalSeconds"] = 100.0 as CKRecordValue
        newer["lastWatchedDate"] = now as CKRecordValue
        repo.applyCloudKitChanges(CloudKitChanges(changedRecords: [newer], deletedRecordIDs: []))

        // Now feed an older record — must be ignored.
        let older = CKRecord(recordType: "WatchProgress", recordID: newerID)
        older["videoId"] = "v1" as CKRecordValue
        older["watchedSeconds"] = 10.0 as CKRecordValue
        older["totalSeconds"] = 100.0 as CKRecordValue
        older["lastWatchedDate"] = now.addingTimeInterval(-3600) as CKRecordValue
        repo.applyCloudKitChanges(CloudKitChanges(changedRecords: [older], deletedRecordIDs: []))

        #expect(repo.watchProgress["v1"]?.watchedSeconds == 80, "Newer local wins over older remote")
    }
}
