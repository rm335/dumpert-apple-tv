import Foundation

extension Date {
    private nonisolated(unsafe) static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var relativeString: String {
        Date.relativeFormatter.localizedString(for: self, relativeTo: Date())
    }
}
