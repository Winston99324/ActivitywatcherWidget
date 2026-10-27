import Foundation

struct ActivitySettings: Codable, Equatable {
    var revision = UUID()
    var serverURL = "http://localhost:5600"
    var windowBucket = ""
    var afkBucket = ""
    var excludeAFK = true
    // Optional so existing version-1 settings still decode without resetting preferences.
    var browserProfiles: [BrowserProfile]?
    var chromeProfiles: [BrowserProfile] {
        get { BrowserProfile.defaults.map { item in browserProfiles?.first(where: { $0.id == item.id }) ?? item } }
        set { browserProfiles = newValue }
    }

    func validatedURL() throws -> URL {
        guard let parts = URLComponents(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "http", let host = parts.host,
              ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased()),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/", let url = parts.url,
              parts.port == nil || (1...65535).contains(parts.port!) else {
            throw ActivityError.message("Use a local HTTP address, such as http://localhost:5600.")
        }
        return url
    }
}

struct Bucket: Decodable, Identifiable {
    var id: String
    var type: String
    var hostname: String
    var client: String?
}

struct AppUsage: Codable, Identifiable, Equatable {
    var app: String
    var seconds: Double
    var id: String { app }
}

struct ActivitySnapshot: Codable {
    var settingsRevision: UUID
    var dayStart: Date
    var timeZoneID: String
    var fetchedAt: Date
    var lastWindowEvent: Date?
    var apps: [AppUsage]
    var windowBucket: String
    var excludesAFK: Bool
    var total: Double { apps.reduce(0) { $0 + $1.seconds } }

    func isToday(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        timeZoneID == calendar.timeZone.identifier && dayStart == calendar.startOfDay(for: date)
    }

    func isStale(at date: Date = Date()) -> Bool {
        date.timeIntervalSince(fetchedAt) > 15 * 60
    }

    static var preview: ActivitySnapshot {
        ActivitySnapshot(settingsRevision: UUID(), dayStart: Calendar.current.startOfDay(for: Date()),
                         timeZoneID: TimeZone.current.identifier, fetchedAt: Date(), lastWindowEvent: Date(),
                         apps: [.init(app: "Xcode", seconds: 6840), .init(app: "Safari", seconds: 3540),
                                .init(app: "Notes", seconds: 2100), .init(app: "Terminal", seconds: 1380)],
                         windowBucket: "Preview", excludesAFK: true)
    }
}

enum ActivityError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

enum UsageFormat {
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0m" }
        if seconds < 60 { return "<1m" }
        let minutes = Int(min(seconds / 60, Double(Int.max / 2)))
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }
}

enum ActivityDate {
    static func parse(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
    static func string(_ value: Date) -> String { ISO8601DateFormatter().string(from: value) }
}
