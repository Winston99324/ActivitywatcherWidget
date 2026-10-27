import SwiftUI
import WidgetKit
import AppIntents

enum ChromeProfileChoice: String, AppEnum {
    case all, first, second
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Chrome Profile"
    static var caseDisplayRepresentations: [ChromeProfileChoice: DisplayRepresentation] = [
        .all: "Combined", .first: "Profile 1", .second: "Profile 2"
    ]
    var profileID: String? { self == .all ? nil : rawValue }
}
enum ChromeGrouping: String, AppEnum {
    case pages, sites
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Display"
    static var caseDisplayRepresentations: [ChromeGrouping: DisplayRepresentation] = [.pages: "Page Titles", .sites: "Websites"]
}
struct ChromeWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Chrome Web Activity"
    static var description = IntentDescription("Choose a Chrome profile and display format.")
    @Parameter(title: "Chrome Profile", default: .all) var profile: ChromeProfileChoice
    @Parameter(title: "Display", default: .pages) var grouping: ChromeGrouping
}
struct ChromeEntry: TimelineEntry {
    var date: Date
    var snapshot: BrowserSnapshot?
    var configuration: ChromeWidgetIntent
    var message: String?
    var current: BrowserSnapshot? { snapshot?.isToday(at: date) == true ? snapshot : nil }
}
struct ChromeProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ChromeEntry {
        ChromeEntry(date: Date(), snapshot: .preview, configuration: ChromeWidgetIntent(), message: nil)
    }
    func snapshot(for configuration: ChromeWidgetIntent, in context: Context) async -> ChromeEntry {
        let saved = context.isPreview ? BrowserSnapshot.preview : (try? SharedStore().browserSnapshot())
        return ChromeEntry(date: Date(), snapshot: saved, configuration: configuration, message: nil)
    }
    func timeline(for configuration: ChromeWidgetIntent, in context: Context) async -> Timeline<ChromeEntry> {
        var snapshot: BrowserSnapshot?
        var message: String?
        do {
            let store = try SharedStore()
            snapshot = try store.browserSnapshot()
            let settings = try store.settings()
            if settings.chromeProfiles.allSatisfy({ $0.bucket.isEmpty }) {
                message = "Open the app to connect your Chrome profiles"
            } else {
                let fresh = try await ActivityClient().fetchBrowser(settings: settings)
                if try store.saveBrowser(fresh) { snapshot = fresh }
                else { snapshot = try store.browserSnapshot() }
            }
        } catch { message = snapshot == nil ? "Open the app to check your Chrome connection" : "Offline · Saved data" }
        let now = Date()
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        var entries = [ChromeEntry(date: now, snapshot: snapshot, configuration: configuration, message: message)]
        if let snapshot {
            let stale = snapshot.fetchedAt.addingTimeInterval(901)
            if stale > now && stale < midnight {
                entries.append(ChromeEntry(date: stale, snapshot: snapshot, configuration: configuration, message: message ?? "Update pending · Click to open"))
            }
        }
        entries.append(ChromeEntry(date: midnight, snapshot: nil, configuration: configuration, message: "New day · Waiting for an update"))
        return Timeline(entries: entries, policy: .after(min(now.addingTimeInterval(300), midnight)))
    }
}

struct ChromeWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: ChromeEntry
    private var profileID: String? { entry.configuration.profile.profileID }
    private var bySite: Bool { entry.configuration.grouping == .sites }
    private var limit: Int { family == .systemLarge ? 5 : family == .systemMedium ? 2 : 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("CHROME", systemImage: "globe").font(.system(size: 10, weight: .bold)).foregroundStyle(.teal)
                Spacer()
                Text("Today").font(.caption2).foregroundStyle(.secondary)
            }
            if let snapshot = entry.current {
                let selected = profileID == nil || snapshot.profiles.contains { $0.id == profileID }
                let name = snapshot.profiles.first(where: { $0.id == profileID })?.name ?? (profileID == nil ? "Both Profiles" : "Profile Not Connected")
                HStack(alignment: .firstTextBaseline) {
                    Text(UsageFormat.duration(snapshot.total(profileID: profileID)))
                        .font(.system(size: family == .systemSmall ? 26 : 30, weight: .semibold, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    if family != .systemSmall { Spacer(); Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                if family == .systemSmall { Text(name).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
                let rows = snapshot.rows(profileID: profileID, bySite: bySite)
                if rows.isEmpty {
                    Text(selected ? "No matching pages yet" : "Connect this profile in the app").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(rows.prefix(limit)) { page in
                    HStack(alignment: .top, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(page.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            if !bySite { Text(page.site).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        Spacer(minLength: 0)
                        Text(UsageFormat.duration(page.seconds)).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if snapshot.ambiguousSeconds > 0 && family == .systemLarge {
                    Text("Unassigned: \(UsageFormat.duration(snapshot.ambiguousSeconds)) (excluded)").font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 3) {
                    if let message = entry.message { Text(message) }
                    else if entry.date.timeIntervalSince(snapshot.fetchedAt) > 900 { Text("Update pending · Click to open") }
                    else { Text("Matched ·"); Text(snapshot.fetchedAt, style: .time) }
                }.font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Spacer(minLength: 0)
                Text(entry.message ?? "Open the app to connect your Chrome profiles").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .containerBackground(for: .widget) { Color(nsColor: .windowBackgroundColor) }
        .widgetURL(URL(string: "activitywatchwidget://dashboard"))
        .privacySensitive()
    }
}

struct ChromeActivityWidget: Widget {
    let kind = "ActivityWatchChrome"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ChromeWidgetIntent.self, provider: ChromeProvider()) { ChromeWidgetView(entry: $0) }
            .configurationDisplayName("Chrome Web Activity")
            .description("Today’s page titles, websites, and browsing time across two Chrome profiles.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
