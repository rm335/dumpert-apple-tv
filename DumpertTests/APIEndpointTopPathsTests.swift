import Testing
import Foundation
@testable import Dumpert

/// The top5 day/month path dates are API tokens: dumpert reckons them in
/// Europe/Amsterdam, not in the Apple TV's timezone. A device ahead of Amsterdam
/// would otherwise ask for "tomorrow", which the API answers with zero items.
/// Mutates the process-wide default timezone, hence `.serialized`.
@Suite("Top5 API path dates", .serialized)
struct APIEndpointTopPathsTests {

    private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }

    /// Last path component of `endpoint`'s URL, built while the device timezone is `id`.
    private func lastComponent(of endpoint: APIEndpoint, deviceTimeZone id: String) throws -> String {
        let saved = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: id)!
        defer { NSTimeZone.default = saved }
        return try endpoint.url.lastPathComponent
    }

    @Test("topDay uses the Amsterdam date even when the device is ahead of Amsterdam")
    func topDayUsesAmsterdamDate() throws {
        // 2026-10-16 22:30 Amsterdam (CEST) == 2026-10-17 05:30 Tokyo.
        let now = utc(2026, 10, 16, 20, 30)
        #expect(try lastComponent(of: APIEndpoint.topDay(date: now), deviceTimeZone: "Asia/Tokyo") == "2026-10-16")
    }

    @Test("topMonth uses the Amsterdam month even when the device is ahead of Amsterdam")
    func topMonthUsesAmsterdamMonth() throws {
        // 2026-10-31 21:30 Amsterdam (CET) == 2026-11-01 05:30 Tokyo.
        let now = utc(2026, 10, 31, 20, 30)
        #expect(try lastComponent(of: APIEndpoint.topMonth(date: now), deviceTimeZone: "Asia/Tokyo") == "202610")
    }

    @Test("topDay uses the Amsterdam date even when the device is behind Amsterdam")
    func topDayBehindAmsterdam() throws {
        // 2026-10-17 00:30 Amsterdam (CEST) == 2026-10-16 15:30 Los Angeles.
        let now = utc(2026, 10, 16, 22, 30)
        #expect(try lastComponent(of: APIEndpoint.topDay(date: now), deviceTimeZone: "America/Los_Angeles") == "2026-10-17")
    }
}
