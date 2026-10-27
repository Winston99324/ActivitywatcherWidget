import Foundation

// This client only reads metadata, queries, and one latest-event timestamp. It never writes ActivityWatch data.
struct ActivityClient {
    let session: URLSession
    init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 5
            config.timeoutIntervalForResource = 8
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config)
        }
    }

    func request<T: Decodable>(_ base: URL, path: String, body: Data? = nil,
                                       query: [URLQueryItem] = []) async throws -> T {
        var parts = URLComponents(url: base.appendingPathComponent("api/0").appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)!
        if !query.isEmpty { parts.queryItems = query }
        var request = URLRequest(url: parts.url!)
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ActivityError.message("ActivityWatch returned an invalid response.")
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw ActivityError.message("ActivityWatch denied access. This version supports the default local API without API-key authentication.")
            }
            throw ActivityError.message("ActivityWatch returned HTTP \(http.statusCode). Check the server and selected buckets.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func buckets(settings: ActivitySettings) async throws -> [Bucket] {
        let result: [String: Bucket] = try await request(settings.validatedURL(), path: "buckets/")
        return result.values.sorted { $0.id < $1.id }
    }

    static func selectWindow(buckets: [Bucket], explicit: String, hostname: String) throws -> Bucket {
        let candidates = buckets.filter { $0.type == "currentwindow" }
        if !explicit.isEmpty {
            guard let bucket = candidates.first(where: { $0.id == explicit }) else {
                throw ActivityError.message("The selected window bucket is missing. Choose a window source in the app.")
            }
            return bucket
        }
        let local = candidates.filter { $0.hostname == hostname }
        let choices = local.isEmpty ? candidates : local
        guard choices.count == 1, let bucket = choices.first else {
            throw ActivityError.message(choices.isEmpty ? "No window watcher found. Start ActivityWatch and its window watcher." :
                                        "Multiple window sources found. Select this Mac’s window bucket in the app.")
        }
        return bucket
    }

    static func selectAFK(buckets: [Bucket], explicit: String, window: Bucket) throws -> Bucket {
        let candidates = buckets.filter { $0.type == "afkstatus" && $0.hostname == window.hostname }
        if !explicit.isEmpty, let bucket = candidates.first(where: { $0.id == explicit }) { return bucket }
        if explicit.isEmpty, candidates.count == 1, let bucket = candidates.first { return bucket }
        throw ActivityError.message("Choose an AFK bucket from the same computer, or turn off ‘Exclude idle time’ to show foreground time.")
    }

    static func query(window: String, afk: String?) throws -> [String] {
        // JSON string encoding prevents bucket identifiers from becoming query-language code.
        func literal(_ value: String) throws -> String {
            String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        }
        var statements = ["events = query_bucket(\(try literal(window)));"]
        if let afk {
            statements += ["active = filter_keyvals(query_bucket(\(try literal(afk))), \"status\", [\"not-afk\"]);",
                           "events = filter_period_intersect(events, active);"]
        }
        statements.append("RETURN = sort_by_duration(merge_events_by_keys(events, [\"app\"]));")
        return statements
    }

    struct Event: Decodable {
        var timestamp: String
        var duration: Double
        var data: EventData
    }
    struct EventData: Decodable { var app: String? }
    struct QueryBody: Encodable { var timeperiods: [String]; var query: [String] }
    private struct ServerInfo: Decodable { var hostname: String }

    static func usages(_ events: [Event]) throws -> [AppUsage] {
        var totals: [String: Double] = [:]
        for event in events {
            guard event.duration.isFinite, event.duration >= 0 else {
                throw ActivityError.message("ActivityWatch returned an invalid event duration.")
            }
            guard event.duration > 0 else { continue }
            let name = event.data.app.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown app"
            totals[name, default: 0] += event.duration
        }
        return totals.map { AppUsage(app: $0.key, seconds: $0.value) }.sorted {
            $0.seconds == $1.seconds ? $0.app < $1.app : $0.seconds > $1.seconds
        }
    }

    func fetch(settings: ActivitySettings, now: Date = Date(), calendar: Calendar = .current) async throws -> ActivitySnapshot {
        let base = try settings.validatedURL()
        async let allBuckets = buckets(settings: settings)
        async let info: ServerInfo = request(base, path: "info")
        let (available, server) = try await (allBuckets, info)
        let window = try Self.selectWindow(buckets: available, explicit: settings.windowBucket, hostname: server.hostname)
        let afk = try settings.excludeAFK ? Self.selectAFK(buckets: available, explicit: settings.afkBucket, window: window) : nil
        let start = calendar.startOfDay(for: now)
        let body = QueryBody(timeperiods: ["\(ActivityDate.string(start))/\(ActivityDate.string(now))"],
                             query: try Self.query(window: window.id, afk: afk?.id))
        async let queryResult: [[Event]] = request(base, path: "query/", body: JSONEncoder().encode(body))
        // Only the timestamp/duration/app fields are decoded; titles and URLs are never persisted.
        async let latestResult: [Event]? = try? request(base, path: "buckets/\(window.id)/events",
                                                       query: [URLQueryItem(name: "limit", value: "1")])
        let (result, latest) = try await (queryResult, latestResult)
        guard result.count == 1 else { throw ActivityError.message("ActivityWatch returned an unexpected query result.") }
        let lastSeen = latest?.first.flatMap { event in
            ActivityDate.parse(event.timestamp)?.addingTimeInterval(max(0, event.duration))
        }
        return ActivitySnapshot(settingsRevision: settings.revision, dayStart: start,
                                timeZoneID: calendar.timeZone.identifier, fetchedAt: now,
                                lastWindowEvent: lastSeen, apps: try Self.usages(result[0]),
                                windowBucket: window.id, excludesAFK: settings.excludeAFK)
    }
}
