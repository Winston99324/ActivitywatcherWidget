import SwiftUI
import WidgetKit

struct ActivityEntry: TimelineEntry {
    let date: Date
    let snapshot: ActivitySnapshot?
    let message: String?
    var current: ActivitySnapshot? { snapshot?.isToday(at: date) == true ? snapshot : nil }
}

struct ActivityProvider: TimelineProvider {
    func placeholder(in context: Context) -> ActivityEntry {
        ActivityEntry(date: Date(), snapshot: .preview, message: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (ActivityEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        let cached = (try? SharedStore().snapshot()) ?? nil
        completion(ActivityEntry(date: Date(), snapshot: cached, message: cached == nil ? "Open the app to set up" : nil))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ActivityEntry>) -> Void) {
        Task {
            var snapshot: ActivitySnapshot?
            var message: String?
            do {
                let store = try SharedStore()
                snapshot = try store.snapshot()
                let settings = try store.settings()
                let fresh = try await ActivityClient().fetch(settings: settings)
                if try store.save(fresh) { snapshot = fresh }
                else { snapshot = try store.snapshot() }
            } catch {
                message = snapshot == nil ? "Open app · check connection" : "Offline · saved data"
            }
            let now = Date()
            let calendar = Calendar.current
            let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            var entries = [ActivityEntry(date: now, snapshot: snapshot, message: message)]
            if let snapshot {
                let staleAt = snapshot.fetchedAt.addingTimeInterval(15 * 60 + 1)
                if staleAt > now && staleAt < midnight {
                    entries.append(ActivityEntry(date: staleAt, snapshot: snapshot, message: message ?? "Saved data · tap to refresh"))
                }
            }
            // Never label yesterday’s total as today while waiting for a new system refresh.
            entries.append(ActivityEntry(date: midnight, snapshot: nil, message: "New day · awaiting update"))
            completion(Timeline(entries: entries, policy: .after(min(now.addingTimeInterval(300), midnight))))
        }
    }
}

struct ActivityWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: ActivityEntry
    private var limit: Int { family == .systemSmall ? 2 : family == .systemMedium ? 4 : 7 }

    private func usageRows(_ snapshot: ActivitySnapshot) -> some View {
        ForEach(Array(snapshot.apps.prefix(limit).enumerated()), id: \.element.id) { index, usage in
            VStack(spacing: 3) {
                HStack(spacing: 6) {
                    Circle().fill(index == 0 ? Color.teal : Color.secondary.opacity(0.4)).frame(width: 5, height: 5)
                    Text(usage.app).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(UsageFormat.duration(usage.seconds)).monospacedDigit().foregroundStyle(.secondary)
                }.font(.system(size: family == .systemSmall ? 11 : 12))
                if family == .systemLarge {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.12))
                            Capsule().fill(Color.teal.opacity(0.8))
                                .frame(width: geometry.size.width * min(1, usage.seconds / max(snapshot.total, 1)))
                        }
                    }.frame(height: 4)
                }
            }
        }
    }

    private func total(_ snapshot: ActivitySnapshot) -> some View {
        Text(UsageFormat.duration(snapshot.total))
            .font(.system(size: family == .systemSmall ? 27 : 32, weight: .semibold, design: .rounded))
            .monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 8) {
            HStack {
                Label("TODAY", systemImage: "chart.bar.xaxis")
                    .font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                Spacer()
                if family != .systemSmall {
                    Text(entry.current?.excludesAFK == false ? "FOREGROUND" : "ACTIVE TIME")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            if let snapshot = entry.current {
                if family == .systemMedium && !snapshot.apps.isEmpty {
                    HStack(alignment: .center, spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            total(snapshot)
                            Text("\(snapshot.apps.count) apps").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        VStack(spacing: 7) { usageRows(snapshot) }
                            .frame(maxWidth: .infinity)
                    }.frame(maxHeight: .infinity)
                } else {
                    total(snapshot)
                    if snapshot.apps.isEmpty {
                        Text("No activity recorded yet").font(.caption).foregroundStyle(.secondary)
                    } else {
                        usageRows(snapshot)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    if let message = entry.message { Text(message) }
                    else if snapshot.isStale(at: entry.date) { Text("Saved data · tap to refresh") }
                    else {
                        Text("Updated")
                        Text(snapshot.fetchedAt, style: .time)
                    }
                }.font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Spacer(minLength: 0)
                Image(systemName: "chart.bar.xaxis").font(.title).foregroundStyle(.teal)
                Text(entry.message ?? "Open ActivityWatch Widget to begin")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .containerBackground(for: .widget) { Color(nsColor: .windowBackgroundColor) }
        .widgetURL(URL(string: "activitywatchwidget://dashboard"))
        .privacySensitive()
    }
}

struct ActivityWatchTodayWidget: Widget {
    let kind = "ActivityWatchToday"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ActivityProvider()) { ActivityWidgetView(entry: $0) }
            .configurationDisplayName("ActivityWatch Today")
            .description("Today’s application time, directly from your local ActivityWatch server.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct ActivityWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        ActivityWatchTodayWidget()
        ChromeActivityWidget()
    }
}
