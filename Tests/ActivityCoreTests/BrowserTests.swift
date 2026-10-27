import XCTest
@testable import ActivityCore

final class BrowserTests: XCTestCase {
    let base = ActivityDate.parse("2026-10-26T00:00:00Z")!
    var calendar: Calendar {
        var result = Calendar(identifier: .gregorian); result.timeZone = TimeZone(secondsFromGMT: 0)!; return result
    }
    func event(_ offset: Double, _ duration: Double, app: String? = nil, title: String? = nil,
               url: String? = nil, status: String? = nil, incognito: Bool? = nil) -> BrowserEvent {
        BrowserEvent(timestamp: ActivityDate.string(base.addingTimeInterval(offset)), duration: duration,
                     data: .init(app: app, title: title, url: url, status: status, incognito: incognito))
    }
    func aggregate(windows: [BrowserEvent], web: [[BrowserEvent]], afk: [BrowserEvent]? = nil) throws -> BrowserSnapshot {
        try BrowserAggregation.aggregate(settings: ActivitySettings(), profiles: BrowserProfile.defaults,
                                          windows: windows, afk: afk ?? [event(0, 3600, status: "not-afk")],
                                          browsers: web, now: base.addingTimeInterval(3600), calendar: calendar)
    }
    func testTwoOpenProfilesOnlyCountTheForegroundPage() throws {
        let windows = [event(0, 60, app: "Google Chrome", title: "Work - Google Chrome"),
                       event(60, 60, app: "Google Chrome", title: "Personal"),
                       event(120, 60, app: "Xcode", title: "Work")]
        let result = try aggregate(windows: windows, web: [
            [event(0, 180, title: "Work", url: "https://example.com/work?private=1")],
            [event(0, 180, title: "Personal", url: "https://example.org/personal")]])
        XCTAssertEqual(result.total(), 120)
        XCTAssertEqual(result.total(profileID: "first"), 60)
        XCTAssertEqual(result.total(profileID: "second"), 60)
        XCTAssertEqual(result.rows(bySite: true).count, 2)
        let json = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        XCTAssertFalse(json.contains("private=1"))
        XCTAssertFalse(json.contains("https://"))
    }
    func testIdenticalPageInBothProfilesIsAmbiguousNotDoubleCounted() throws {
        let same = event(0, 60, title: "Same page", url: "https://example.com/")
        let result = try aggregate(windows: [event(0, 60, app: "Google Chrome", title: "Same page")], web: [[same], [same]])
        XCTAssertEqual(result.total(), 0)
        XCTAssertEqual(result.ambiguousSeconds, 60)
    }
    func testURLDisambiguatesIdenticalTitles() throws {
        let result = try aggregate(windows: [event(0, 60, app: "Google Chrome", title: "Document", url: "https://example.com/?doc=2")],
                                   web: [[event(0, 60, title: "Document", url: "https://example.com/?doc=1")],
                                         [event(0, 60, title: "Document", url: "https://example.com/?doc=2#section")]])
        XCTAssertEqual(result.total(profileID: "second"), 60)
        XCTAssertEqual(result.total(profileID: "first"), 0)
    }
    func testAFKClippingDuplicatesIncognitoAndInternalPages() throws {
        let page = event(-30, 150, title: "Page", url: "https://example.com/")
        let result = try aggregate(windows: [event(-30, 150, app: "Google Chrome", title: "Page")],
                                   web: [[page, page], []], afk: [event(-30, 60, status: "not-afk"), event(30, 90, status: "afk")])
        XCTAssertEqual(result.total(), 30)
        let ignored = try aggregate(windows: [event(0, 60, app: "Google Chrome", title: "Page")],
                                    web: [[event(0, 60, title: "Page", url: "https://example.com", incognito: true)],
                                          [event(0, 60, title: "Page", url: "chrome://settings")]])
        XCTAssertEqual(ignored.total(), 0)
        XCTAssertEqual(ignored.unmatchedSeconds, 60)
    }
    func testSourceValidationAndOldSettingsMigration() throws {
        var settings = try JSONDecoder().decode(ActivitySettings.self, from: Data(#"{"revision":"00000000-0000-0000-0000-000000000001","serverURL":"http://localhost:5600","windowBucket":"","afkBucket":"","excludeAFK":true}"#.utf8))
        XCTAssertEqual(settings.chromeProfiles, BrowserProfile.defaults)
        var profiles = settings.chromeProfiles
        profiles[0].bucket = "same"; profiles[1].bucket = "same"; settings.chromeProfiles = profiles
        let window = Bucket(id: "window", type: "currentwindow", hostname: "local")
        XCTAssertThrowsError(try ActivityClient.validateBrowserProfiles(settings, available: [], window: window))
        profiles[1].bucket = "other"; settings.chromeProfiles = profiles
        let sources = [Bucket(id: "same", type: "web.tab.current", hostname: "local"), Bucket(id: "other", type: "web.tab.current", hostname: "remote")]
        XCTAssertThrowsError(try ActivityClient.validateBrowserProfiles(settings, available: sources, window: window))
    }
    func testBrowserStoreSeparatesCachesAndRejectsOldResponses() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try SharedStore(directory: folder)
        var settings = try store.settings()
        var snapshot = BrowserSnapshot.preview; snapshot.settingsRevision = settings.revision
        XCTAssertTrue(try store.saveBrowser(snapshot))
        snapshot.fetchedAt = snapshot.fetchedAt.addingTimeInterval(-60)
        XCTAssertFalse(try store.saveBrowser(snapshot))
        XCTAssertNil(try store.snapshot())
        settings.revision = UUID(); try store.saveSettings(settings)
        XCTAssertNil(try store.browserSnapshot())
        XCTAssertFalse(try store.saveBrowser(snapshot))
    }
    func testLiveTwoProfileQuery() async throws {
        guard let endpoint = ProcessInfo.processInfo.environment["AW_TEST_SERVER"] else { throw XCTSkip("Requires isolated seeded test server") }
        var settings = ActivitySettings(); settings.serverURL = endpoint
        settings.windowBucket = "widget-test-browser-window"; settings.afkBucket = "widget-test-browser-afk"
        var profiles = settings.chromeProfiles
        profiles[0].bucket = "widget-test-chromework"; profiles[1].bucket = "widget-test-chromepersonal"
        settings.chromeProfiles = profiles
        let result = try await ActivityClient().fetchBrowser(settings: settings, now: base.addingTimeInterval(3600), calendar: calendar)
        XCTAssertEqual(result.total(profileID: "first"), 30, accuracy: 0.01)
        XCTAssertEqual(result.total(profileID: "second"), 30, accuracy: 0.01)
        XCTAssertEqual(result.ambiguousSeconds, 30, accuracy: 0.01)
    }
}
