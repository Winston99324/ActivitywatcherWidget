import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: ActivityModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("ActivityWatch", systemImage: "chart.bar.xaxis").font(.title2.bold())
                        Text("YOUR DAY, AT A GLANCE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { Task { await model.refresh(forceReload: true) } } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }.disabled(model.refreshing)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(UsageFormat.duration(model.today?.total ?? 0))
                        .font(.system(size: 48, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(model.today?.excludesAFK == false ? "foreground time today" : "active time today")
                        .foregroundStyle(.secondary)
                }
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).textSelection(.enabled)
                }
                if let snapshot = model.today {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(snapshot.apps.prefix(12)) { usage in
                            HStack {
                                Text(usage.app).lineLimit(1)
                                Spacer()
                                Text(UsageFormat.duration(usage.seconds)).monospacedDigit().foregroundStyle(.secondary)
                            }
                            ProgressView(value: usage.seconds, total: max(snapshot.total, 1)).tint(.teal)
                        }
                        if snapshot.apps.isEmpty { Text("No recorded activity today. Check that ActivityWatch’s watchers are running.").foregroundStyle(.secondary) }
                        Text("Fetched \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened)) · \(snapshot.isStale() ? "Cached data" : "Local data")")
                            .font(.caption).foregroundStyle(.secondary)
                        if let last = snapshot.lastWindowEvent {
                            Text("Latest window record: \(last.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else { Text("Start ActivityWatch, then refresh to load today’s activity.").foregroundStyle(.secondary) }

                GroupBox("Connection & sources") {
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("Local server", text: $model.settings.serverURL)
                        HStack {
                            Button(model.loadingBuckets ? "Loading…" : "Find Sources") { Task { await model.discover() } }
                                .disabled(model.loadingBuckets)
                            Text("Select a source if more than one computer is recorded.").font(.caption).foregroundStyle(.secondary)
                        }
                        Picker("Window source", selection: $model.settings.windowBucket) {
                            Text("Automatic (server’s computer)").tag("")
                            ForEach(model.buckets.filter { $0.type == "currentwindow" }) { Text($0.id).tag($0.id) }
                            if !model.settings.windowBucket.isEmpty && !model.buckets.contains(where: { $0.id == model.settings.windowBucket }) {
                                Text(model.settings.windowBucket + " (unavailable)").tag(model.settings.windowBucket)
                            }
                        }
                        Toggle("Exclude idle time", isOn: $model.settings.excludeAFK)
                        if model.settings.excludeAFK {
                            Picker("AFK source", selection: $model.settings.afkBucket) {
                                Text("Automatic (same computer)").tag("")
                                ForEach(model.buckets.filter { $0.type == "afkstatus" }) { Text($0.id).tag($0.id) }
                                if !model.settings.afkBucket.isEmpty && !model.buckets.contains(where: { $0.id == model.settings.afkBucket }) {
                                    Text(model.settings.afkBucket + " (unavailable)").tag(model.settings.afkBucket)
                                }
                            }
                        }
                        Button("Save & Refresh") { Task { await model.save() } }
                            .buttonStyle(.borderedProminent).disabled(model.refreshing)
                    }.padding(8)
                }
                ChromeDashboardSection(model: model)
                Toggle("Open at login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                if let message = model.loginMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                Text("Close this window to keep the menu bar updater running. Add the native widget from desktop → Edit Widgets → ActivityWatch Widget. You can place it on your second display. macOS controls widget refresh timing.")
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(28)
        }.frame(minWidth: 580, minHeight: 540)
    }
}
