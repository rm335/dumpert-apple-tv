import os

extension Logger {
    private static let subsystem = "nl.dumpert.tvos"

    static let cloudKit = Logger(subsystem: subsystem, category: "CloudKit")
    static let cache = Logger(subsystem: subsystem, category: "Cache")
    static let network = Logger(subsystem: subsystem, category: "Network")
    static let thumbnail = Logger(subsystem: subsystem, category: "Thumbnail")
    static let monitoring = Logger(subsystem: subsystem, category: "Monitoring")
}
