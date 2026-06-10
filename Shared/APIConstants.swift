import Foundation

/// API conventions shared between the app's `DumpertAPIClient` and the Top
/// Shelf extension's `TopShelfFetcher`, defined once so the two clients
/// cannot drift apart.
enum APIConstants {
    /// User-Agent sent on every API request.
    static let userAgent = "DumpertTV/1.0 (tvOS; unofficial)"

    /// Cookie value that opts a request into NSFW results server-side. Sent
    /// only when the user allows NSFW content; omitted otherwise so the server
    /// applies its safe default.
    static let nsfwOptInCookie = "nsfw=1"
}
