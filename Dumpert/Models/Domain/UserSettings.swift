import Foundation
import SwiftUI

enum TopCommentMode: String, Codable, Sendable, CaseIterable {
    case off, single, all

    var displayName: String {
        switch self {
        case .off: String(localized: "Uit", comment: "Top comment mode - off")
        case .single: String(localized: "Alleen het top reaguursel", comment: "Top comment mode - single top comment")
        case .all: String(localized: "Alle reaguursels", comment: "Top comment mode - all top comments carousel")
        }
    }
}

enum ReadingSpeed: Int, Codable, Sendable, CaseIterable {
    case slow = 2
    case normal = 3
    case fast = 4
    case veryFast = 5
    case ultraFast = 6

    var displayName: String {
        switch self {
        case .slow: String(localized: "Langzaam (2 woorden/sec)", comment: "Reading speed - slow")
        case .normal: String(localized: "Normaal (3 woorden/sec)", comment: "Reading speed - normal")
        case .fast: String(localized: "Snel (4 woorden/sec)", comment: "Reading speed - fast")
        case .veryFast: String(localized: "Zeer snel (5 woorden/sec)", comment: "Reading speed - very fast")
        case .ultraFast: String(localized: "Razendsnel (6 woorden/sec)", comment: "Reading speed - ultra fast")
        }
    }

    /// Calculates reading duration in seconds for the given text, with a minimum of 5 seconds.
    func readingDuration(for text: String) -> Double {
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        return max(5.0, Double(wordCount) / Double(rawValue))
    }
}

enum TileSize: String, Codable, Sendable, CaseIterable {
    case small, normal, large

    var displayName: String {
        switch self {
        case .small: String(localized: "Klein", comment: "Tile size option - small")
        case .normal: String(localized: "Normaal", comment: "Tile size option - normal")
        case .large: String(localized: "Groot", comment: "Tile size option - large")
        }
    }

    var horizontalCardWidth: CGFloat {
        switch self {
        case .small: 400
        case .normal: 450
        case .large: 500
        }
    }

    var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 30), count: gridColumnCount)
    }

    var gridColumnCount: Int {
        switch self {
        case .small: 4
        case .normal: 3
        case .large: 2
        }
    }
}

enum RemoteSkipMode: String, Codable, Sendable, CaseIterable {
    case off, swipe

    var displayName: String {
        switch self {
        case .off: String(localized: "Uit", comment: "Remote skip mode - off")
        case .swipe: String(localized: "Swipe", comment: "Remote skip mode - swipe on touchpad")
        }
    }
}

@Observable
@MainActor
final class UserSettings {
    var minimumKudos: Int { didSet { notifyChange() } }
    var autoplayEnabled: Bool { didSet { notifyChange() } }
    var hideWatched: Bool { didSet { notifyChange() } }
    var reetenMinimumMinutes: Int { didSet { notifyChange() } }
    var showNegativeKudos: Bool { didSet { notifyChange() } }
    var nsfwEnabled: Bool { didSet { notifyChange() } }
    var thumbnailPreviewEnabled: Bool { didSet { notifyChange() } }
    var smartThumbnailsEnabled: Bool { didSet { notifyChange() } }
    var tileSize: TileSize { didSet { notifyChange() } }
    var upNextOverlayEnabled: Bool { didSet { notifyChange() } }
    var upNextCountdownSeconds: Int { didSet { notifyChange() } }
    var upNextMinimumVideoSeconds: Int { didSet { notifyChange() } }
    var topCommentMode: TopCommentMode { didSet { notifyChange() } }
    var readingSpeed: ReadingSpeed { didSet { notifyChange() } }
    var remoteSkipMode: RemoteSkipMode { didSet { notifyChange() } }
    var showResumeOverlay: Bool { didSet { notifyChange() } }
    var lastModified: Date

    /// Invoked whenever any user-facing setting changes. Set by the owner
    /// (typically VideoRepository) to persist the snapshot. The class itself
    /// holds no persistence knowledge — it just signals that a save is needed.
    @ObservationIgnored
    var onChange: (@MainActor () -> Void)?

    /// When true, per-property `didSet` notifications do not propagate to
    /// `onChange`. Used by `apply(_:)` so bulk restoration of a remote/cached
    /// snapshot doesn't echo back through the save handler.
    @ObservationIgnored
    private var suppressNotifications = false

    private func notifyChange() {
        guard !suppressNotifications else { return }
        onChange?()
    }

    init(minimumKudos: Int = 0, autoplayEnabled: Bool = true, hideWatched: Bool = true, reetenMinimumMinutes: Int = 10, showNegativeKudos: Bool = false, nsfwEnabled: Bool = true, thumbnailPreviewEnabled: Bool = true, smartThumbnailsEnabled: Bool = true, tileSize: TileSize = .normal, upNextOverlayEnabled: Bool = true, upNextCountdownSeconds: Int = 5, upNextMinimumVideoSeconds: Int = 60, topCommentMode: TopCommentMode = .all, readingSpeed: ReadingSpeed = .normal, remoteSkipMode: RemoteSkipMode = .swipe, showResumeOverlay: Bool = true) {
        self.minimumKudos = minimumKudos
        self.autoplayEnabled = autoplayEnabled
        self.hideWatched = hideWatched
        self.reetenMinimumMinutes = reetenMinimumMinutes
        self.showNegativeKudos = showNegativeKudos
        self.nsfwEnabled = nsfwEnabled
        self.thumbnailPreviewEnabled = thumbnailPreviewEnabled
        self.smartThumbnailsEnabled = smartThumbnailsEnabled
        self.tileSize = tileSize
        self.upNextOverlayEnabled = upNextOverlayEnabled
        self.upNextCountdownSeconds = upNextCountdownSeconds
        self.upNextMinimumVideoSeconds = upNextMinimumVideoSeconds
        self.topCommentMode = topCommentMode
        self.readingSpeed = readingSpeed
        self.remoteSkipMode = remoteSkipMode
        self.showResumeOverlay = showResumeOverlay
        self.lastModified = Date()
    }

    var snapshot: UserSettingsSnapshot {
        UserSettingsSnapshot(
            minimumKudos: minimumKudos,
            autoplayEnabled: autoplayEnabled,
            hideWatched: hideWatched,
            reetenMinimumMinutes: reetenMinimumMinutes,
            showNegativeKudos: showNegativeKudos,
            nsfwEnabled: nsfwEnabled,
            thumbnailPreviewEnabled: thumbnailPreviewEnabled,
            smartThumbnailsEnabled: smartThumbnailsEnabled,
            tileSize: tileSize,
            upNextOverlayEnabled: upNextOverlayEnabled,
            upNextCountdownSeconds: upNextCountdownSeconds,
            upNextMinimumVideoSeconds: upNextMinimumVideoSeconds,
            topCommentMode: topCommentMode,
            readingSpeed: readingSpeed,
            remoteSkipMode: remoteSkipMode,
            showResumeOverlay: showResumeOverlay,
            lastModified: lastModified
        )
    }

    /// Restores every setting to its factory default in one shot and persists
    /// once. Data-driven: the defaults come from a fresh `UserSettingsSnapshot()`
    /// so this never drifts as new settings are added (no hand-maintained list).
    func resetToDefaults() {
        apply(UserSettingsSnapshot())
        onChange?()
    }

    func apply(_ snapshot: UserSettingsSnapshot) {
        suppressNotifications = true
        defer { suppressNotifications = false }
        minimumKudos = snapshot.minimumKudos
        autoplayEnabled = snapshot.autoplayEnabled
        hideWatched = snapshot.hideWatched
        reetenMinimumMinutes = snapshot.reetenMinimumMinutes
        showNegativeKudos = snapshot.showNegativeKudos
        nsfwEnabled = snapshot.nsfwEnabled
        thumbnailPreviewEnabled = snapshot.thumbnailPreviewEnabled
        smartThumbnailsEnabled = snapshot.smartThumbnailsEnabled
        tileSize = snapshot.tileSize
        upNextOverlayEnabled = snapshot.upNextOverlayEnabled
        upNextCountdownSeconds = snapshot.upNextCountdownSeconds
        upNextMinimumVideoSeconds = snapshot.upNextMinimumVideoSeconds
        topCommentMode = snapshot.topCommentMode
        readingSpeed = snapshot.readingSpeed
        remoteSkipMode = snapshot.remoteSkipMode
        showResumeOverlay = snapshot.showResumeOverlay
        lastModified = snapshot.lastModified
    }
}

struct UserSettingsSnapshot: Codable, Sendable {
    var minimumKudos: Int
    var autoplayEnabled: Bool
    var hideWatched: Bool
    var reetenMinimumMinutes: Int
    var showNegativeKudos: Bool
    var nsfwEnabled: Bool
    var thumbnailPreviewEnabled: Bool
    var smartThumbnailsEnabled: Bool
    var tileSize: TileSize
    var upNextOverlayEnabled: Bool
    var upNextCountdownSeconds: Int
    var upNextMinimumVideoSeconds: Int
    var topCommentMode: TopCommentMode
    var readingSpeed: ReadingSpeed
    var remoteSkipMode: RemoteSkipMode
    var showResumeOverlay: Bool
    var lastModified: Date

    init(minimumKudos: Int = 0, autoplayEnabled: Bool = true, hideWatched: Bool = true, reetenMinimumMinutes: Int = 10, showNegativeKudos: Bool = false, nsfwEnabled: Bool = true, thumbnailPreviewEnabled: Bool = true, smartThumbnailsEnabled: Bool = true, tileSize: TileSize = .normal, upNextOverlayEnabled: Bool = true, upNextCountdownSeconds: Int = 5, upNextMinimumVideoSeconds: Int = 60, topCommentMode: TopCommentMode = .all, readingSpeed: ReadingSpeed = .normal, remoteSkipMode: RemoteSkipMode = .swipe, showResumeOverlay: Bool = true, lastModified: Date = Date()) {
        self.minimumKudos = minimumKudos
        self.autoplayEnabled = autoplayEnabled
        self.hideWatched = hideWatched
        self.reetenMinimumMinutes = reetenMinimumMinutes
        self.showNegativeKudos = showNegativeKudos
        self.nsfwEnabled = nsfwEnabled
        self.thumbnailPreviewEnabled = thumbnailPreviewEnabled
        self.smartThumbnailsEnabled = smartThumbnailsEnabled
        self.tileSize = tileSize
        self.upNextOverlayEnabled = upNextOverlayEnabled
        self.upNextCountdownSeconds = upNextCountdownSeconds
        self.upNextMinimumVideoSeconds = upNextMinimumVideoSeconds
        self.topCommentMode = topCommentMode
        self.readingSpeed = readingSpeed
        self.remoteSkipMode = remoteSkipMode
        self.showResumeOverlay = showResumeOverlay
        self.lastModified = lastModified
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        minimumKudos = try container.decode(Int.self, forKey: .minimumKudos)
        autoplayEnabled = try container.decode(Bool.self, forKey: .autoplayEnabled)
        hideWatched = try container.decode(Bool.self, forKey: .hideWatched)
        // Migration: old format stored Bool, new format stores Int (minutes)
        if let minutes = try? container.decode(Int.self, forKey: .reetenMinimumMinutes) {
            reetenMinimumMinutes = minutes
        } else if let oldBool = try? container.decode(Bool.self, forKey: .reetenMinimumMinutes) {
            reetenMinimumMinutes = oldBool ? 10 : 0
        } else {
            reetenMinimumMinutes = 10
        }
        showNegativeKudos = try container.decode(Bool.self, forKey: .showNegativeKudos)
        nsfwEnabled = try container.decodeIfPresent(Bool.self, forKey: .nsfwEnabled) ?? true
        thumbnailPreviewEnabled = try container.decode(Bool.self, forKey: .thumbnailPreviewEnabled)
        smartThumbnailsEnabled = try container.decodeIfPresent(Bool.self, forKey: .smartThumbnailsEnabled) ?? true
        tileSize = try container.decodeIfPresent(TileSize.self, forKey: .tileSize) ?? .normal
        upNextOverlayEnabled = try container.decodeIfPresent(Bool.self, forKey: .upNextOverlayEnabled) ?? true
        upNextCountdownSeconds = try container.decodeIfPresent(Int.self, forKey: .upNextCountdownSeconds) ?? 5
        upNextMinimumVideoSeconds = try container.decodeIfPresent(Int.self, forKey: .upNextMinimumVideoSeconds) ?? 60
        // Migration: old format stored Bool (showTopComment), new format stores TopCommentMode
        if let mode = try? container.decode(TopCommentMode.self, forKey: .topCommentMode) {
            topCommentMode = mode
        } else if let oldBool = try? container.decode(Bool.self, forKey: .topCommentMode) {
            topCommentMode = oldBool ? .all : .off
        } else {
            topCommentMode = .all
        }
        readingSpeed = try container.decodeIfPresent(ReadingSpeed.self, forKey: .readingSpeed) ?? .normal
        remoteSkipMode = try container.decodeIfPresent(RemoteSkipMode.self, forKey: .remoteSkipMode) ?? .swipe
        showResumeOverlay = try container.decodeIfPresent(Bool.self, forKey: .showResumeOverlay) ?? true
        lastModified = try container.decode(Date.self, forKey: .lastModified)
    }

    private enum CodingKeys: String, CodingKey {
        case minimumKudos, autoplayEnabled, hideWatched
        case reetenMinimumMinutes = "reetenMinimumDuration"
        case showNegativeKudos, nsfwEnabled, thumbnailPreviewEnabled, smartThumbnailsEnabled, tileSize
        case upNextOverlayEnabled, upNextCountdownSeconds, upNextMinimumVideoSeconds
        case topCommentMode = "showTopComment"
        case readingSpeed
        case remoteSkipMode
        case showResumeOverlay
        case lastModified
    }
}
