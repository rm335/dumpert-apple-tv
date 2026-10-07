import Testing
import UIKit
import OSLog
@testable import Dumpert

@Suite("Thumbnail Upgrade Service Tests")
struct ThumbnailUpgradeServiceTests {

    @Test("Concurrent upgrades of one item run the analysis only once")
    func concurrentCallsDeduplicate() async throws {
        // Solid gray PNG: no face, so the service reaches frame extraction.
        let png = FileManager.default.temporaryDirectory
            .appendingPathComponent("gray-\(UUID().uuidString).png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        try image.pngData()!.write(to: png)
        let stream = URL(fileURLWithPath: "/nonexistent/stream.m3u8")
        let itemId = "dedupe-\(UUID().uuidString)"

        let service = ThumbnailUpgradeService()
        let start = Date()
        async let a = service.upgradeIfNeeded(itemId: itemId, thumbnailURL: png, streamURL: stream, duration: 30)
        async let b = service.upgradeIfNeeded(itemId: itemId, thumbnailURL: png, streamURL: stream, duration: 30)
        _ = await (a, b)

        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let started = try store.getEntries(at: store.position(date: start))
            .compactMap { $0 as? OSLogEntryLog }
            .filter { $0.category == "Thumbnail" && $0.composedMessage.contains("[\(itemId)] starting analysis") }
        #expect(started.count == 1)
    }
}
