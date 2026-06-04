import Foundation

/// Classifies the bundled startup sounds as safe-for-work or not, driven by the
/// `Sounds.json` manifest. The policy is an *allowlist*: only sounds explicitly
/// marked `nsfw: false` are eligible while NSFW content is hidden. A sound that
/// is missing from the manifest is therefore withheld in that mode — so a newly
/// added, unclassified sound can never leak; at worst it is silently skipped
/// until someone rates it (the safe direction).
struct LoadingSoundCatalog: Sendable {
    private let safeFilenames: Set<String>
    private let nsfwFilenames: Set<String>

    init(entries: [Entry]) {
        var safe = Set<String>()
        var nsfw = Set<String>()
        for entry in entries {
            if entry.nsfw {
                nsfw.insert(entry.file)
            } else {
                safe.insert(entry.file)
            }
        }
        safeFilenames = safe
        nsfwFilenames = nsfw
    }

    /// Whether a sound is explicitly classified as safe-for-work. Unknown files
    /// (not in the manifest) return `false`.
    func isSafe(filename: String) -> Bool {
        safeFilenames.contains(filename)
    }

    /// Whether a sound is explicitly classified as NSFW. Primarily for tests and
    /// diagnostics; playback uses ``isSafe(filename:)`` as the allowlist.
    func isNSFW(filename: String) -> Bool {
        nsfwFilenames.contains(filename)
    }

    /// Filters `filenames` to those eligible to play given the NSFW preference.
    /// With NSFW allowed, everything passes; otherwise only safe-for-work sounds.
    func eligible(_ filenames: [String], allowNSFW: Bool) -> [String] {
        guard !allowNSFW else { return filenames }
        return filenames.filter(isSafe)
    }

    struct Entry: Decodable, Sendable {
        let file: String
        let nsfw: Bool
        var title: String?
    }

    private struct Manifest: Decodable {
        let sounds: [Entry]
    }

    /// Loads the catalog from the bundled `Sounds.json`. Returns an empty catalog
    /// (which withholds *every* sound while NSFW is hidden — fail-safe) if the
    /// manifest is missing or unreadable.
    static func bundled(
        bundle: Bundle = Bundle(for: BundleMarker.self),
        resource: String = "Sounds"
    ) -> LoadingSoundCatalog {
        guard let url = bundle.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
            return LoadingSoundCatalog(entries: [])
        }
        return LoadingSoundCatalog(entries: manifest.sounds)
    }

    /// Anchors `Bundle(for:)` to the module that ships `Sounds.json`, so the
    /// manifest is found whether this code runs in the app or is linked into a
    /// test bundle.
    private final class BundleMarker {}
}
