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

    var usesLatestEndpoint: Bool {
        self == .nieuwBinnen
    }

    /// DumpertTV has its own paginated endpoint (`/dumperttv/{page}`) rather than
    /// the search or latest endpoints used by the other channels.
    var usesDumpertTVEndpoint: Bool {
        self == .dumperttv
    }

    /// Channels backed by the search endpoint can be re-sorted server-side; the
    /// latest and DumpertTV feeds have a fixed order, so they hide the sort picker.
    var supportsSorting: Bool {
        !usesLatestEndpoint && !usesDumpertTVEndpoint
    }
}
