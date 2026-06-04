import Foundation

/// A run of consecutive feed items that share one calendar day (reckoned in
/// dumpert's home timezone), or the catch-all bucket for items whose timestamp
/// could not be parsed.
struct DaySection: Identifiable {
    enum Kind: Hashable {
        case today
        case yesterday
        /// An older dated day, keyed on its start-of-day instant.
        case day(Date)
        /// Items the API returned without a parseable date.
        case undated
    }

    let kind: Kind
    let items: [MediaItem]

    var id: Kind { kind }
}

/// Groups the Nieuw feed into day sections.
///
/// dumpert.nl reckons "vandaag"/"gister" in its home timezone (Europe/Amsterdam),
/// so the buckets are computed there rather than in `Calendar.current` — otherwise
/// an Apple TV configured for another region would split the day at the wrong
/// instant and disagree with the website near midnight. The date maths is kept
/// pure (no localization, `now` and `calendar` injectable) so it can be unit
/// tested deterministically; the view maps each ``DaySection/Kind`` to a label.
enum DayGrouping {
    /// Gregorian calendar pinned to dumpert's home timezone. Falls back to the
    /// device calendar only if the identifier somehow fails to resolve.
    static let amsterdamCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        if let zone = TimeZone(identifier: "Europe/Amsterdam") {
            calendar.timeZone = zone
        }
        return calendar
    }()

    static func sections(
        for items: [MediaItem],
        now: Date = Date(),
        calendar: Calendar = amsterdamCalendar
    ) -> [DaySection] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)

        // Preserve the incoming (newest-first) order within each day by appending
        // in iteration order; only the day keys themselves get sorted afterwards.
        var itemsByDay: [Date: [MediaItem]] = [:]
        var undated: [MediaItem] = []
        for item in items {
            guard let date = item.date else {
                undated.append(item)
                continue
            }
            let day = calendar.startOfDay(for: date)
            itemsByDay[day, default: []].append(item)
        }

        var sections: [DaySection] = itemsByDay.keys.sorted(by: >).map { day in
            let kind: DaySection.Kind
            if day == today {
                kind = .today
            } else if day == yesterday {
                kind = .yesterday
            } else {
                kind = .day(day)
            }
            return DaySection(kind: kind, items: itemsByDay[day] ?? [])
        }

        // Undated items get their own clearly-labelled bucket at the very bottom
        // instead of being silently dated to `.distantPast` and intermingled with
        // genuinely old entries.
        if !undated.isEmpty {
            sections.append(DaySection(kind: .undated, items: undated))
        }

        return sections
    }
}
