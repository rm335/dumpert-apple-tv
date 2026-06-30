import Foundation
import os

enum APIEndpoint {
    case topWeek(date: Date)
    case topMonth(date: Date)
    case topDay(date: Date)
    case hotshiz
    case latest(page: Int)
    case search(query: String, page: Int, order: SortOrder?)
    case info(id: String)
    case classics(page: Int)
    case dumpertTV(page: Int)
    case related(id: String)

    private static let baseURL = "https://post.dumpert.nl/api/v1.0"

    // top5/week and top5/maand want YYYYWW / YYYYMM with NO separator — a dash
    // (e.g. "2026-27") makes the API return content from a year ago. Only
    // top5/dag uses dashes (yyyy-MM-dd), hence the separate formatter below.
    private nonisolated(unsafe) static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMM"
        return f
    }()

    private nonisolated(unsafe) static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func weekString(from date: Date) -> String {
        let year = Calendar.current.component(.yearForWeekOfYear, from: date)
        let week = Calendar.current.component(.weekOfYear, from: date)
        return String(format: "%04d%02d", year, week)
    }

    var url: URL {
        get throws {
            let path: String
            switch self {
            case .topWeek(let date):
                path = "/top5/week/\(Self.weekString(from: date))"
            case .topMonth(let date):
                path = "/top5/maand/\(Self.monthFormatter.string(from: date))"
            case .topDay(let date):
                path = "/top5/dag/\(Self.dayFormatter.string(from: date))"
            case .hotshiz:
                path = "/hotshiz"
            case .latest(let page):
                path = "/latest/\(page)"
            case .search(let query, let page, let order):
                // .urlPathAllowed permits '/', so a query like "AC/DC" would split
                // into extra path segments. Exclude it so the slash is percent-
                // encoded and stays inside the single /search/<query>/ segment.
                let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
                let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
                path = "/search/\(encoded)/\(page)"
                if let order {
                    guard var components = URLComponents(string: Self.baseURL + path) else {
                        try Self.fail(Self.baseURL + path)
                    }
                    components.queryItems = [URLQueryItem(name: "order", value: order.rawValue)]
                    guard let url = components.url else {
                        try Self.fail(Self.baseURL + path)
                    }
                    return url
                }
            case .info(let id):
                path = "/info/\(id)"
            case .classics(let page):
                path = "/classics/\(page)"
            case .dumpertTV(let page):
                path = "/dumperttv/\(page)"
            case .related(let id):
                path = "/related/\(id)"
            }
            guard let url = URL(string: Self.baseURL + path) else {
                try Self.fail(Self.baseURL + path)
            }
            return url
        }
    }

    /// Logs the offending candidate and throws — used instead of force-unwrapping
    /// a URL built from an unexpected (e.g. deep-linked) id, so a malformed id is
    /// a handled networking error rather than a crash.
    private static func fail(_ candidate: String) throws -> Never {
        Logger.network.error("Invalid API URL: \(candidate, privacy: .public)")
        throw APIError.invalidURL
    }
}
