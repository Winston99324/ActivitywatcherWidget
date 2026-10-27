import XCTest
@testable import ActivityCore

final class ActivityCoreTests: XCTestCase {
    func testOnlyLoopbackURLsAreAccepted() throws {
        for url in ["http://localhost:5600", "http://127.0.0.1:5601", "http://[::1]:5600"] {
            var settings = ActivitySettings(); settings.serverURL = url
            XCTAssertNoThrow(try settings.validatedURL())
        }
        for url in ["https://localhost:5600", "http://example.com", "http://localhost.evil.test", "http://a@localhost", "http://localhost/api", "http://localhost?x=1"] {
            var settings = ActivitySettings(); settings.serverURL = url
            XCTAssertThrowsError(try settings.validatedURL())
        }
    }

    func testBucketsAreNotCombinedAcrossComputers() throws {
        let one = Bucket(id: "window-one", type: "currentwindow", hostname: "one")
        let two = Bucket(id: "window-two", type: "currentwindow", hostname: "two")
        XCTAssertEqual(try ActivityClient.selectWindow(buckets: [one, two], explicit: "", hostname: "two").id, two.id)
        XCTAssertThrowsError(try ActivityClient.selectWindow(buckets: [one, two], explicit: "", hostname: "unknown"))
        XCTAssertThrowsError(try ActivityClient.selectWindow(buckets: [one], explicit: "removed", hostname: "one"))
        let afk = Bucket(id: "afk-two", type: "afkstatus", hostname: "two")
        XCTAssertThrowsError(try ActivityClient.selectAFK(buckets: [afk], explicit: afk.id, window: one))
        XCTAssertEqual(try ActivityClient.selectAFK(buckets: [afk], explicit: "", window: two).id, afk.id)
    }

    func testQueryEscapesBucketNamesAndIncludesAFKIntersection() throws {
        let query = try ActivityClient.query(window: "a\"; RETURN = 1;", afk: "afk")
        XCTAssertTrue(query[0].contains("a\\\"; RETURN = 1;"))
        XCTAssertTrue(query.contains { $0.contains("filter_period_intersect") })
        XCTAssertFalse(try ActivityClient.query(window: "normal", afk: nil).contains { $0.contains("filter_period_intersect") })
    }

    func testAggregatesAndIgnoresSensitiveFields() throws {
        let json = #"[{"timestamp":"2026-10-26T10:00:00Z","duration":60,"data":{"app":"Safari","title":"private","url":"secret"}},{"timestamp":"2026-10-26T10:01:00.123Z","duration":30.5,"data":{"app":"Safari"}},{"timestamp":"2026-10-26T10:02:00Z","duration":0,"data":{"app":"Xcode"}}]"#
        let events = try JSONDecoder().decode([ActivityClient.Event].self, from: Data(json.utf8))
        XCTAssertEqual(try ActivityClient.usages(events), [.init(app: "Safari", seconds: 90.5)])
        XCTAssertNotNil(ActivityDate.parse(events[0].timestamp))
        XCTAssertNotNil(ActivityDate.parse(events[1].timestamp))
        XCTAssertThrowsError(try ActivityClient.usages([.init(timestamp: "", duration: -1, data: .init(app: "bad"))]))
    }

    func testDayRolloverTimeZoneAndDST() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = ActivityDate.parse("2026-11-01T20:00:00Z")!
        let start = calendar.startOfDay(for: date)
        let next = calendar.date(byAdding: .day, value: 1, to: start)!
        XCTAssertEqual(next.timeIntervalSince(start), 25 * 3600)
        var snapshot = ActivitySnapshot.preview
        snapshot.dayStart = start; snapshot.timeZoneID = calendar.timeZone.identifier
        XCTAssertTrue(snapshot.isToday(at: date, calendar: calendar))
        XCTAssertFalse(snapshot.isToday(at: next, calendar: calendar))
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertFalse(snapshot.isToday(at: date, calendar: calendar))
    }

    func testStoreRejectsOldResponsesAndConfigurationRaces() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SharedStore(directory: directory)
        let settings = try store.settings()
        var snapshot = ActivitySnapshot.preview; snapshot.settingsRevision = settings.revision
        XCTAssertTrue(try store.save(snapshot))
        snapshot.fetchedAt = snapshot.fetchedAt.addingTimeInterval(-60)
        XCTAssertFalse(try store.save(snapshot))
        var changed = settings; changed.revision = UUID()
        try store.saveSettings(changed)
        XCTAssertNil(try store.snapshot())
        XCTAssertFalse(try store.save(snapshot))
        snapshot.settingsRevision = changed.revision
        XCTAssertTrue(try store.save(snapshot))
        let persisted = try Data(contentsOf: directory.appendingPathComponent("snapshot.json"))
        XCTAssertFalse(String(decoding: persisted, as: UTF8.self).contains("title"))
        try Data("corrupt cache".utf8).write(to: directory.appendingPathComponent("snapshot.json"))
        XCTAssertNil(try store.snapshot())
        XCTAssertTrue(try store.save(snapshot))
    }

    func testHTTPIntegrationWithMockTransport() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = ActivityClient(session: session)
        let now = ActivityDate.parse("2026-10-26T12:00:00Z")!
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let snapshot = try await client.fetch(settings: ActivitySettings(), now: now, calendar: calendar)
        XCTAssertEqual(snapshot.total, 180)
        XCTAssertEqual(snapshot.windowBucket, "window-fixture")
        XCTAssertTrue(snapshot.excludesAFK)
        XCTAssertEqual(snapshot.lastWindowEvent, ActivityDate.parse("2026-10-26T11:59:00Z"))
    }

    func testLiveIsolatedServerWhenConfigured() async throws {
        guard let endpoint = ProcessInfo.processInfo.environment["AW_TEST_SERVER"] else {
            throw XCTSkip("Set AW_TEST_SERVER to the isolated fixture server to run the live integration test.")
        }
        var settings = ActivitySettings(); settings.serverURL = endpoint
        settings.windowBucket = "widget-test-window"; settings.afkBucket = "widget-test-afk"
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ActivityDate.parse("2026-10-26T01:00:00Z")!
        let active = try await ActivityClient().fetch(settings: settings, now: now, calendar: calendar)
        XCTAssertEqual(active.total, 150, accuracy: 0.01)
        XCTAssertEqual(active.apps.first?.app, "Safari")
        settings.excludeAFK = false
        let foreground = try await ActivityClient().fetch(settings: settings, now: now, calendar: calendar)
        XCTAssertEqual(foreground.total, 210, accuracy: 0.01)
    }
}

final class FixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        let body: String
        if path.hasSuffix("/info") { body = #"{"hostname":"fixture"}"# }
        else if path.hasSuffix("/buckets") || path.hasSuffix("/buckets/") {
            body = #"{"window-fixture":{"id":"window-fixture","type":"currentwindow","hostname":"fixture"},"afk-fixture":{"id":"afk-fixture","type":"afkstatus","hostname":"fixture"}}"#
        } else if path.contains("/query") {
            XCTAssertEqual(request.httpMethod, "POST")
            body = #"[[{"timestamp":"2026-10-26T10:00:00Z","duration":180,"data":{"app":"Safari"}}]]"#
        } else {
            body = #"[{"timestamp":"2026-10-26T11:58:00Z","duration":60,"data":{"app":"Safari"}}]"#
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                                           headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
