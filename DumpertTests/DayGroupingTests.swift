import Testing
import Foundation
@testable import Dumpert

@Suite("Nieuw feed day grouping")
struct DayGroupingTests {

    private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi; c.second = s
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }

    private func item(_ id: String, date: Date?) -> MediaItem {
        .video(Video(
            id: id, title: id, descriptionText: "", date: date,
            duration: 0, kudosTotal: 0, thumbnailURL: nil, streamURL: nil,
            tags: [], isNSFW: false
        ))
    }

    /// Reference "now": 2026-06-03 09:44 Europe/Amsterdam (== 07:44 UTC, CEST).
    private var now: Date { utc(2026, 6, 3, 7, 44, 0) }

    @Test("Mixed feed buckets into Vandaag / Gisteren / dated / undated, in order")
    func mixedFeed() {
        let items = [
            item("today-a",  date: utc(2026, 6, 3, 7, 43, 9)),   // 09:43 AMS — today
            item("today-b",  date: utc(2026, 6, 3, 6, 50, 58)),  // 08:50 AMS — today (bug item)
            item("yest-a",   date: utc(2026, 6, 2, 20, 5, 2)),   // 22:05 AMS — yesterday
            item("older",    date: utc(2026, 5, 31, 20, 0, 0)),  // 31 May 22:00 AMS
            item("nodate",   date: nil),
        ]

        let sections = DayGrouping.sections(for: items, now: now)

        #expect(sections.map(\.kind) == [
            .today,
            .yesterday,
            .day(DayGrouping.amsterdamCalendar.startOfDay(for: utc(2026, 5, 31, 20, 0, 0))),
            .undated,
        ])
        #expect(sections[0].items.map(\.id) == ["today-a", "today-b"])  // feed order preserved
        #expect(sections[1].items.map(\.id) == ["yest-a"])
        #expect(sections[3].items.map(\.id) == ["nodate"])
    }

    @Test("Today section contains exactly the items from the Amsterdam calendar day")
    func todayCount() {
        let items = [
            item("t1", date: utc(2026, 6, 3, 7, 43, 0)),
            item("t2", date: utc(2026, 6, 3, 6, 50, 0)),
            item("y1", date: utc(2026, 6, 2, 18, 0, 0)),
        ]
        let sections = DayGrouping.sections(for: items, now: now)
        let today = sections.first { $0.kind == .today }
        #expect(today?.items.count == 2)
    }

    @Test("Undated items never mix into a dated section")
    func undatedIsolated() {
        let items = [
            item("dated",   date: utc(2026, 6, 3, 7, 0, 0)),
            item("nodate1", date: nil),
            item("nodate2", date: nil),
        ]
        let sections = DayGrouping.sections(for: items, now: now)
        #expect(sections.count == 2)
        #expect(sections.last?.kind == .undated)
        #expect(sections.last?.items.count == 2)
        // The dated section holds only the dated item.
        #expect(sections.first?.items.map(\.id) == ["dated"])
    }

    @Test("Empty feed produces no sections")
    func emptyFeed() {
        #expect(DayGrouping.sections(for: [], now: now).isEmpty)
    }

    // MARK: - Timezone determinism (the latent bug)

    @Test("An item just after Amsterdam midnight is Vandaag in Amsterdam, Gisteren in US Pacific")
    func timezoneBoundary() {
        // 2026-06-02T23:30:00Z == 01:30 Amsterdam (Jun 3) but 16:30 Pacific (Jun 2).
        let nearMidnight = item("edge", date: utc(2026, 6, 2, 23, 30, 0))

        let amsterdam = DayGrouping.sections(for: [nearMidnight], now: now)
        #expect(amsterdam.first?.kind == .today)

        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let losAngeles = DayGrouping.sections(for: [nearMidnight], now: now, calendar: pacific)
        #expect(losAngeles.first?.kind == .yesterday)
    }
}
