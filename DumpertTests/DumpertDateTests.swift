import Testing
import Foundation
@testable import Dumpert

@Suite("Dumpert API date parsing")
struct DumpertDateTests {

    /// Builds a UTC instant from components, independent of the parser under test.
    private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi; c.second = s
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }

    private func expectInstant(_ string: String, _ expected: Date, tolerance: TimeInterval = 0.005) throws {
        let parsed = try #require(DumpertDate.parse(string), "Expected \(string) to parse to a non-nil Date")
        #expect(abs(parsed.timeIntervalSince1970 - expected.timeIntervalSince1970) < tolerance,
                "\(string) parsed to \(parsed) but expected \(expected)")
    }

    // MARK: - Every format observed live in /latest must parse to the right instant

    @Test("Fractional seconds with Z — 3 digits (the bug-report item)")
    func fractional3() throws {
        // "Wanneer hij in zijn moedertaal praat" — vandaag @ 08:50 on dumpert.nl,
        // which the old parser dropped to nil and filed under "Eerder".
        try expectInstant("2026-06-03T06:50:58.833Z", utc(2026, 6, 3, 6, 50, 58).addingTimeInterval(0.833))
    }

    @Test("Fractional seconds with Z — 2 digits")
    func fractional2() throws {
        try expectInstant("2026-06-03T07:43:09.04Z", utc(2026, 6, 3, 7, 43, 9).addingTimeInterval(0.04))
    }

    @Test("Fractional seconds with Z — 4 digits")
    func fractional4() throws {
        try expectInstant("2026-06-02T12:46:01.4991Z", utc(2026, 6, 2, 12, 46, 1).addingTimeInterval(0.4991))
    }

    @Test("Fractional seconds with Z — 6 digits (microseconds)")
    func fractional6() throws {
        try expectInstant("2026-06-02T18:00:33.682998Z", utc(2026, 6, 2, 18, 0, 33).addingTimeInterval(0.682998))
    }

    @Test("Whole seconds with Z (no fractional part)")
    func wholeSecondsZ() throws {
        try expectInstant("2026-06-02T15:14:00Z", utc(2026, 6, 2, 15, 14, 0))
    }

    @Test("Numeric offset with colon converts to UTC")
    func offsetWithColon() throws {
        // 14:19:14 +01:00 == 13:19:14 UTC
        try expectInstant("2026-03-10T14:19:14+01:00", utc(2026, 3, 10, 13, 19, 14))
    }

    @Test("Fractional seconds with numeric offset")
    func fractionalWithOffset() throws {
        // 09:46:32.163661 +02:00 == 07:46:32.163661 UTC
        try expectInstant("2026-03-09T09:46:32.163661+02:00", utc(2026, 3, 9, 7, 46, 32).addingTimeInterval(0.163661))
    }

    // MARK: - Date convenience initialiser

    @Test("Date(dumpertAPIString:) succeeds and fails as expected")
    func dateInitialiser() {
        #expect(Date(dumpertAPIString: "2026-06-03T06:50:58.833Z") != nil)
        #expect(Date(dumpertAPIString: "not a date") == nil)
    }

    // MARK: - Unparseable / missing input returns nil (not a bogus distant date)

    @Test("Nil, empty and garbage strings return nil", arguments: [
        nil, "", "   ", "garbage", "2026-13-99T99:99:99Z"
    ] as [String?])
    func unparseableReturnsNil(_ input: String?) {
        #expect(DumpertDate.parse(input) == nil)
    }
}
