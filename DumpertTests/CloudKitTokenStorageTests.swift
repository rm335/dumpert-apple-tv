import Testing
import Foundation
@testable import Dumpert

/// The CloudKit change token must share the purge fate of the cached user data
/// it vouches for (watch progress, curation, search history live in Caches).
/// A token in UserDefaults survived a Caches purge, so every later fetch was a
/// delta against an empty local cache and the data never came back.
@Suite("CloudKit Token Storage Tests", .serialized)
struct CloudKitTokenStorageTests {

    private let legacyKey = "cloudkit_change_token"

    @Test("Init drops the legacy UserDefaults token so the next fetch is a full one")
    func initDropsLegacyToken() {
        UserDefaults.standard.set(Data([1, 2, 3]), forKey: legacyKey)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ck-token-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = CloudKitService(tokenDirectory: dir)

        #expect(UserDefaults.standard.data(forKey: legacyKey) == nil)
    }

    @Test("Default token directory is the cache directory that holds the user data")
    func defaultTokenDirectoryIsCacheDirectory() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        #expect(CloudKitService.defaultTokenDirectory == caches.appendingPathComponent("DumpertCache", isDirectory: true))
    }
}
