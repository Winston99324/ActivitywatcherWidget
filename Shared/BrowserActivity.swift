import Foundation

struct BrowserProfile: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var bucket: String
    static let defaults = [BrowserProfile(id: "first", name: "Chrome 1", bucket: ""),
                           BrowserProfile(id: "second", name: "Chrome 2", bucket: "")]
}

struct WebPageUsage: Codable, Identifiable, Equatable {
    var profileID: String
    var title: String
    var site: String
    var seconds: Double
    var id: String { "\(profileID)\u{1f}\(site)\u{1f}\(title)" }
}

struct BrowserSnapshot: Codable {
    var settingsRevision: UUID
    var dayStart: Date
    var timeZoneID: String
    var fetchedAt: Date
    var profiles: [BrowserProfile]
    var pages: [WebPageUsage]
    var ambiguousSeconds: Double
    var unmatchedSeconds: Double
    var excludesAFK: Bool

    func isToday(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        timeZoneID == calendar.timeZone.identifier && dayStart == calendar.startOfDay(for: date)
    }
    func rows(profileID: String? = nil, bySite: Bool = false) -> [WebPageUsage] {
        var groups: [String: WebPageUsage] = [:]
        for page in pages where profileID == nil || page.profileID == profileID {
            let title = bySite ? page.site : page.title
            let key = page.site + "\u{1f}" + title
            var row = groups[key] ?? WebPageUsage(profileID: profileID ?? "all", title: title, site: page.site, seconds: 0)
            row.seconds += page.seconds
            groups[key] = row
        }
        return groups.values.sorted { $0.seconds == $1.seconds ? $0.id < $1.id : $0.seconds > $1.seconds }
    }
    func total(profileID: String? = nil) -> Double {
        pages.filter { profileID == nil || $0.profileID == profileID }.reduce(0) { $0 + $1.seconds }
    }
    static var preview: BrowserSnapshot {
        BrowserSnapshot(settingsRevision: UUID(), dayStart: Calendar.current.startOfDay(for: Date()),
                        timeZoneID: TimeZone.current.identifier, fetchedAt: Date(), profiles: BrowserProfile.defaults,
                        pages: [.init(profileID: "first", title: "SwiftUI — Apple Developer", site: "developer.apple.com", seconds: 2100),
                                .init(profileID: "first", title: "ActivityWatch · GitHub", site: "github.com", seconds: 1680),
                                .init(profileID: "second", title: "Learn photography — YouTube", site: "youtube.com", seconds: 960)],
                        ambiguousSeconds: 0, unmatchedSeconds: 0, excludesAFK: true)
    }
}

// Raw URLs exist only during matching. Only domain/title/duration reach the shared cache.
struct BrowserEvent: Decodable {
    var timestamp: String
    var duration: Double
    var data: Fields
    struct Fields: Decodable {
        var app: String?
        var title: String?
        var url: String?
        var status: String?
        var incognito: Bool?
    }
}

enum BrowserAggregation {
    struct Interval {
        var start: Date
        var end: Date
        var event: BrowserEvent
    }
    static func intervals(_ events: [BrowserEvent], start: Date, end: Date) throws -> [Interval] {
        try events.compactMap { event in
            guard event.duration.isFinite, event.duration >= 0, let date = ActivityDate.parse(event.timestamp) else {
                throw ActivityError.message("Browser activity contains an invalid timestamp or duration.")
            }
            let lower = max(start, date), upper = min(end, date.addingTimeInterval(event.duration))
            return upper > lower ? Interval(start: lower, end: upper, event: event) : nil
        }
    }
    static func isChrome(_ app: String?) -> Bool {
        ["Google Chrome", "Google Chrome Beta", "Google Chrome Dev", "Google Chrome Canary", "chrome", "chrome.exe", "com.google.Chrome"].contains(app ?? "")
    }
    static func site(_ value: String?) -> String? {
        guard let value, let parts = URLComponents(string: value),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""), let host = parts.host, !host.isEmpty else { return nil }
        return host.lowercased()
    }
    static func match(_ web: BrowserEvent.Fields, window: BrowserEvent.Fields) -> Bool {
        // When available, a window-watcher URL is more reliable than titles. Keep query
        // parameters for the comparison only, so distinct documents are not conflated.
        if let windowURL = window.url, site(windowURL) != nil, let webURL = web.url {
            func normalized(_ value: String) -> String? {
                guard var parts = URLComponents(string: value) else { return nil }
                parts.fragment = nil
                return parts.string
            }
            return normalized(windowURL) == normalized(webURL)
        }
        guard let title = web.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
              let windowTitle = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        if windowTitle == title { return true }
        // Watcher/Chrome versions differ in whether the browser/profile suffix is included.
        let suffix = windowTitle.dropFirst(min(title.count, windowTitle.count))
        return windowTitle.hasPrefix(title) && suffix.hasPrefix(" - ") && suffix.contains("Google Chrome")
    }

    static func aggregate(settings: ActivitySettings, profiles: [BrowserProfile], windows: [BrowserEvent],
                          afk: [BrowserEvent], browsers: [[BrowserEvent]], now: Date,
                          calendar: Calendar = .current) throws -> BrowserSnapshot {
        guard profiles.count == browsers.count else { throw ActivityError.message("Browser source response count does not match.") }
        let start = calendar.startOfDay(for: now)
        let sourceEvents = [windows, afk] + browsers
        guard sourceEvents.allSatisfy({ $0.count <= 50_000 }) else {
            throw ActivityError.message("Too many browser events for a widget refresh. No partial total was saved.")
        }
        let streams = try sourceEvents.map { try intervals($0, start: start, end: now) }
        // Sweep interval endpoints. A second is assigned at most once across all profiles.
        // Active sets also handle duplicate/overlapping watcher events without double counting.
        struct Boundary { var date: Date; var stream: Int; var index: Int; var entering: Bool }
        var boundaries: [Boundary] = []
        for (stream, intervals) in streams.enumerated() {
            for (index, interval) in intervals.enumerated() {
                boundaries.append(.init(date: interval.start, stream: stream, index: index, entering: true))
                boundaries.append(.init(date: interval.end, stream: stream, index: index, entering: false))
            }
        }
        boundaries.sort { $0.date < $1.date }
        var active = Array(repeating: Set<Int>(), count: streams.count)
        var result: [String: WebPageUsage] = [:]
        var ambiguous = 0.0, unmatched = 0.0, position = 0
        while position < boundaries.count {
            let date = boundaries[position].date
            while position < boundaries.count && boundaries[position].date == date {
                let boundary = boundaries[position]
                if boundary.entering { active[boundary.stream].insert(boundary.index) }
                else { active[boundary.stream].remove(boundary.index) }
                position += 1
            }
            guard position < boundaries.count else { break }
            let seconds = boundaries[position].date.timeIntervalSince(date)
            guard seconds > 0 else { continue }
            if settings.excludeAFK && !active[1].contains(where: { streams[1][$0].event.data.status == "not-afk" }) { continue }
            // Conflicting window events cannot safely establish one foreground window.
            let foreground = active[0].map { streams[0][$0].event.data }
            guard foreground.contains(where: { isChrome($0.app) }) else { continue }
            guard foreground.allSatisfy({ isChrome($0.app) }),
                  let window = foreground.first,
                  foreground.allSatisfy({ $0.title == window.title && $0.url == window.url }) else {
                ambiguous += seconds; continue
            }
            var candidates: [String: WebPageUsage] = [:]
            for (profileIndex, profile) in profiles.enumerated() {
                for index in active[profileIndex + 2] {
                    let fields = streams[profileIndex + 2][index].event.data
                    guard fields.incognito != true, let domain = site(fields.url), match(fields, window: window) else { continue }
                    let title = fields.title.flatMap { $0.isEmpty ? nil : $0 } ?? domain
                    let row = WebPageUsage(profileID: profile.id, title: title, site: domain, seconds: 0)
                    candidates[row.id] = row
                }
            }
            if candidates.count == 1, var row = candidates.values.first {
                row.seconds = (result[row.id]?.seconds ?? 0) + seconds
                result[row.id] = row
            } else if candidates.isEmpty { unmatched += seconds }
            else { ambiguous += seconds }
        }
        return BrowserSnapshot(settingsRevision: settings.revision, dayStart: start,
                               timeZoneID: calendar.timeZone.identifier, fetchedAt: now, profiles: profiles,
                               pages: result.values.sorted { $0.id < $1.id }, ambiguousSeconds: ambiguous,
                               unmatchedSeconds: unmatched, excludesAFK: settings.excludeAFK)
    }
}

extension ActivityClient {
    static func validateBrowserProfiles(_ settings: ActivitySettings, available: [Bucket], window: Bucket) throws -> [BrowserProfile] {
        let profiles = settings.chromeProfiles.filter { !$0.bucket.isEmpty }
        guard !profiles.isEmpty else { throw ActivityError.message("Configure the two Chrome sources in the app first.") }
        guard Set(profiles.map(\.bucket)).count == profiles.count, Set(profiles.map(\.id)).count == profiles.count else {
            throw ActivityError.message("Choose a different browser source for each Chrome profile. The same source cannot identify two accounts.")
        }
        for profile in profiles {
            guard available.contains(where: { $0.id == profile.bucket && $0.type == "web.tab.current" && $0.hostname == window.hostname }) else {
                throw ActivityError.message("\(profile.name): choose a browser source from the same computer as the window watcher.")
            }
        }
        return profiles
    }
    static func browserQuery(window: String, afk: String?, profiles: [BrowserProfile]) throws -> [String] {
        func literal(_ string: String) throws -> String { String(decoding: try JSONEncoder().encode(string), as: UTF8.self) }
        var query = ["windows = query_bucket(\(try literal(window)));"]
        query.append(try afk.map { "active = query_bucket(\(try literal($0)));" } ?? "active = [];")
        for (index, profile) in profiles.enumerated() {
            query.append("browser\(index) = query_bucket(\(try literal(profile.bucket)));")
        }
        query.append("RETURN = [windows, active, \(profiles.indices.map { "browser\($0)" }.joined(separator: ", "))];")
        return query
    }
    func fetchBrowser(settings: ActivitySettings, now: Date = Date(), calendar: Calendar = .current) async throws -> BrowserSnapshot {
        let base = try settings.validatedURL()
        struct Info: Decodable { var hostname: String }
        async let allBuckets = buckets(settings: settings)
        async let server: Info = request(base, path: "info")
        let (available, info) = try await (allBuckets, server)
        let window = try Self.selectWindow(buckets: available, explicit: settings.windowBucket, hostname: info.hostname)
        let profiles = try Self.validateBrowserProfiles(settings, available: available, window: window)
        let afk = try settings.excludeAFK ? Self.selectAFK(buckets: available, explicit: settings.afkBucket, window: window) : nil
        let body = QueryBody(timeperiods: ["\(ActivityDate.string(calendar.startOfDay(for: now)))/\(ActivityDate.string(now))"],
                             query: try Self.browserQuery(window: window.id, afk: afk?.id, profiles: profiles))
        let results: [[[BrowserEvent]]] = try await request(base, path: "query/", body: JSONEncoder().encode(body))
        guard results.count == 1, results[0].count == profiles.count + 2 else {
            throw ActivityError.message("Unexpected Chrome query response.")
        }
        return try BrowserAggregation.aggregate(settings: settings, profiles: profiles, windows: results[0][0],
                                                afk: results[0][1], browsers: Array(results[0].dropFirst(2)), now: now, calendar: calendar)
    }
}
