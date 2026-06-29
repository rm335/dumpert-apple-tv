import Foundation

struct CurationEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let videoId: String
    let category: VideoCategory
    let action: CurationAction
    let timestamp: Date

    init(videoId: String, category: VideoCategory, action: CurationAction) {
        self.id = UUID()
        self.videoId = videoId
        self.category = category
        self.action = action
        self.timestamp = Date()
    }

    /// Rebuilds an entry that already exists in CloudKit, keeping its record id
    /// (the CKRecord's recordName). The default initializer mints a fresh UUID,
    /// which would never match the recordName a deletion tombstone arrives with —
    /// so un-curation from another device could never be applied locally.
    init(id: UUID, videoId: String, category: VideoCategory, action: CurationAction, timestamp: Date) {
        self.id = id
        self.videoId = videoId
        self.category = category
        self.action = action
        self.timestamp = timestamp
    }
}

enum CurationAction: String, Codable, Sendable {
    case add
    case remove
}
