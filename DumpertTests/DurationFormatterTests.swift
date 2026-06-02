import Testing
@testable import Dumpert

@Suite("Duration Formatter Tests")
struct DurationFormatterTests {

    @Test("Formats seconds under a minute")
    func formatsSecondsUnderMinute() {
        #expect(45.formattedDuration == "0:45")
    }

    @Test("Formats exactly one minute")
    func formatsOneMinute() {
        #expect(60.formattedDuration == "1:00")
    }

    @Test("Formats minutes and seconds")
    func formatsMinutesAndSeconds() {
        #expect(125.formattedDuration == "2:05")
    }

    @Test("Formats zero seconds")
    func formatsZero() {
        #expect(0.formattedDuration == "0:00")
    }

    @Test("Formats long durations")
    func formatsLongDuration() {
        #expect(3661.formattedDuration == "61:01")
    }

    @Test("Pads seconds with leading zero")
    func padsSeconds() {
        #expect(63.formattedDuration == "1:03")
    }

    // MARK: - formattedCount (kudos/views abbreviation)

    @Test("formattedCount leaves values under 1000 as-is")
    func countUnderThousand() {
        #expect(0.formattedCount == "0")
        #expect(999.formattedCount == "999")
    }

    @Test("formattedCount abbreviates thousands")
    func countThousands() {
        #expect(1_000.formattedCount == "1.0k")
        #expect(63_759.formattedCount == "63.8k")
    }

    @Test("formattedCount abbreviates millions")
    func countMillions() {
        #expect(1_200_000.formattedCount == "1.2M")
    }

    @Test("formattedCount preserves sign for negative kudos")
    func countNegative() {
        #expect((-1_500).formattedCount == "-1.5k")
        #expect((-42).formattedCount == "-42")
    }
}
