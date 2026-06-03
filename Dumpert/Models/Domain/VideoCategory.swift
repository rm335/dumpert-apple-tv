import Foundation

enum VideoCategory: String, CaseIterable, Identifiable, Codable {
    case nieuwBinnen
    case reeten
    case vrijmico
    case dashcam
    case dumperttv

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nieuwBinnen: String(localized: "Nieuw", comment: "Category name for new videos")
        case .reeten: String(localized: "Dumpert Reeten", comment: "Category name for hall of fame videos")
        case .vrijmico: String(localized: "VrijMiCo", comment: "Category name for Friday/Saturday/Sunday content")
        case .dashcam: String(localized: "Dashcam", comment: "Category name for dashcam videos")
        case .dumperttv: String(localized: "DumpertTV", comment: "Category name for DumpertTV editorial videos")
        }
    }

    var searchQuery: String {
        switch self {
        case .nieuwBinnen: ""
        case .reeten: "dumpertreeten"
        case .vrijmico: "vrijmico"
        case .dashcam: "dashcam"
        case .dumperttv: ""
        }
    }

    var systemImage: String {
        switch self {
        case .nieuwBinnen: "sparkles"
        case .reeten: "fork.knife"
        case .vrijmico: "party.popper.fill"
        case .dashcam: "car.fill"
        case .dumperttv: "tv"
        }
    }

    /// Which backend feed this channel is served by. Selecting the endpoint via a
    /// single enum — rather than a growing set of `usesXEndpoint` booleans — keeps
    /// the routing switch exhaustive (the compiler flags a new case) and lets the
    /// derived capabilities below live in one place.
    var endpoint: CategoryEndpoint {
        switch self {
        case .nieuwBinnen: .latest
        case .reeten, .vrijmico, .dashcam: .search
        case .dumperttv: .dumpertTV
        }
    }

    /// Only the search-backed channels accept a server-side sort order; the latest
    /// and DumpertTV feeds have a fixed order, so they hide the sort picker.
    var supportsSorting: Bool {
        endpoint == .search
    }

    /// Whether individual videos can be pinned/hidden in this channel. Only the
    /// search-backed genre channels are curatable: the Nieuw feed is a plain
    /// chronological stream and DumpertTV is an editorial feed we don't control,
    /// so curation entries there have no meaningful effect.
    var supportsCuration: Bool {
        endpoint == .search
    }
}

/// The backend feed backing a `VideoCategory`.
enum CategoryEndpoint {
    /// `/json/latest` — the chronological "Nieuw" feed.
    case latest
    /// `/search` — the genre channels (Reeten, VrijMiCo, Dashcam), re-sortable server-side.
    case search
    /// `/dumperttv/{page}` — the editorial DumpertTV feed.
    case dumpertTV
}
