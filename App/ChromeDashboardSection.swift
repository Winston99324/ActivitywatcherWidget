import SwiftUI

struct ChromeDashboardSection: View {
    @ObservedObject var model: ActivityModel

    private func profile(_ index: Int) -> Binding<BrowserProfile> {
        Binding(get: { model.settings.chromeProfiles[index] }, set: { value in
            var profiles = model.settings.chromeProfiles
            profiles[index] = value
            model.settings.chromeProfiles = profiles
        })
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Text("View today’s page titles, websites, and browsing time for each Chrome profile.")
                    .foregroundStyle(.secondary)
                ForEach(0..<2, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Profile \(index + 1) display name", text: profile(index).name)
                        Picker("Chrome \(index + 1) source", selection: profile(index).bucket) {
                            Text("Not Connected").tag("")
                            ForEach(model.buckets.filter { $0.type == "web.tab.current" }) { Text($0.id).tag($0.id) }
                            let chosen = model.settings.chromeProfiles[index].bucket
                            if !chosen.isEmpty && !model.buckets.contains(where: { $0.id == chosen }) {
                                Text(chosen + " (unavailable)").tag(chosen)
                            }
                        }
                    }
                }
                HStack {
                    Button("Find Sources") { Task { await model.discover() } }.disabled(model.loadingBuckets)
                    Button("Save & Refresh") { Task { await model.save() } }
                        .buttonStyle(.borderedProminent).disabled(model.refreshing)
                }
                DisclosureGroup("How do I connect two Chrome profiles?") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Install ActivityWatch Web Watcher in each Chrome profile.")
                        Text("2. In each extension’s settings, select Other… for Browser. Use chromework for one profile and chromepersonal for the other (lowercase letters only). Keep the same computer Hostname for both.")
                        Text("3. Save the extension settings and browse a webpage in each profile. Then click Find Sources above and select the matching source for each profile.")
                        Text("4. On the desktop, open Edit Widgets → Chrome Web Activity. After adding it, right-click → Edit Widget to choose Profile 1, Profile 2, or Combined, and Page Titles or Websites.")
                        Link("Install the Official Chrome Extension", destination: URL(string: "https://chromewebstore.google.com/detail/activitywatch-web-watcher/nglaklhklhcoonedhgnpgddginnjdadi")!)
                    }.font(.callout).padding(.top, 8)
                }
                if let error = model.browserError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                if let snapshot = model.browserToday {
                    Divider()
                    Picker("Profile", selection: $model.browserSelection) {
                        Text("Combined").tag("all")
                        ForEach(snapshot.profiles) { Text($0.name).tag($0.id) }
                    }.pickerStyle(.segmented)
                    Toggle("Group by Website", isOn: $model.browserBySite)
                    let profileID: String? = model.browserSelection == "all" ? nil : model.browserSelection
                    HStack(alignment: .firstTextBaseline) {
                        Text(UsageFormat.duration(snapshot.total(profileID: profileID))).font(.title.bold()).monospacedDigit()
                        Text(snapshot.excludesAFK ? "matched active browsing time today" : "matched foreground browsing time today").foregroundStyle(.secondary)
                    }
                    ForEach(snapshot.rows(profileID: profileID, bySite: model.browserBySite).prefix(15)) { page in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(page.title).lineLimit(2)
                                if !model.browserBySite { Text(page.site).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(UsageFormat.duration(page.seconds)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    if snapshot.pages.isEmpty { Text("No matching pages yet. Enable the extension and browse with Chrome in the foreground.").foregroundStyle(.secondary) }
                    Text("Unassigned: \(UsageFormat.duration(snapshot.ambiguousSeconds)) · Unmatched pages: \(UsageFormat.duration(snapshot.unmatchedSeconds)) (all connected profiles)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Only pages matching the foreground Chrome window are counted. If both profiles show the same page, ambiguous periods remain unassigned to avoid double counting. This shows page titles and websites; it does not read page bodies or Google accounts.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(8)
        } label: { Label("Chrome Web Activity · Second Widget", systemImage: "globe") }
    }
}
