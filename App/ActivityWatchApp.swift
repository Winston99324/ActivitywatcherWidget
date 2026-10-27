import AppKit
import SwiftUI
import WidgetKit
import ServiceManagement

@main
struct ActivityWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = ActivityModel()

    var body: some Scene {
        WindowGroup("ActivityWatch Widget", id: "main") {
            DashboardView(model: model)
                .handlesExternalEvents(preferring: ["dashboard"], allowing: ["*"])
                .onOpenURL { _ in
                    NSApp.activate(ignoringOtherApps: true)
                    Task { await model.refresh(forceReload: true) }
                }
        }
        .handlesExternalEvents(matching: ["dashboard"])
        .defaultSize(width: 700, height: 700)
        MenuBarExtra("ActivityWatch Widget", systemImage: "chart.bar.xaxis") {
            MenuContent(model: model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct MenuContent: View {
    @ObservedObject var model: ActivityModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("Today: \(UsageFormat.duration(model.today?.total ?? 0))")
        Button("Open Dashboard") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Refresh Now") { Task { await model.refresh(forceReload: true) } }
            .disabled(model.refreshing)
        Divider()
        Button("Quit ActivityWatch Widget") { NSApp.terminate(nil) }
    }
}

@MainActor
final class ActivityModel: ObservableObject {
    @Published var settings = ActivitySettings()
    @Published var snapshot: ActivitySnapshot?
    @Published var browserSnapshot: BrowserSnapshot?
    @Published var browserError: String?
    @Published var browserSelection = "all"
    @Published var browserBySite = false
    @Published var buckets: [Bucket] = []
    @Published var error: String?
    @Published var refreshing = false
    @Published var loadingBuckets = false
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var loginMessage: String?
    private var store: SharedStore?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var lastReload = Date.distantPast

    var today: ActivitySnapshot? { snapshot?.isToday() == true ? snapshot : nil }
    var browserToday: BrowserSnapshot? { browserSnapshot?.isToday() == true ? browserSnapshot : nil }

    init() {
        do {
            let store = try SharedStore()
            self.store = store
            settings = try store.settings()
            snapshot = try store.snapshot()
            browserSnapshot = try store.browserSnapshot()
        } catch { self.error = error.localizedDescription }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        timer?.tolerance = 10
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in await self?.refresh(forceReload: true) } }
        Task { await refresh(forceReload: true); await discover() }
    }

    func refresh(forceReload: Bool = false) async {
        guard !refreshing, let store else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            // Always use committed settings; edits in the form do not affect polling until saved.
            let committed = try store.settings()
            let fresh = try await ActivityClient().fetch(settings: committed)
            if try store.save(fresh) { snapshot = fresh; error = nil }
            else { snapshot = try store.snapshot() }
        } catch {
            self.error = "Could not update: \(error.localizedDescription)"
        }
        do {
            let committed = try store.settings()
            if committed.chromeProfiles.contains(where: { !$0.bucket.isEmpty }) {
                let fresh = try await ActivityClient().fetchBrowser(settings: committed)
                if try store.saveBrowser(fresh) { browserSnapshot = fresh; browserError = nil }
                else { browserSnapshot = try store.browserSnapshot() }
            } else { browserSnapshot = nil; browserError = nil }
        } catch { browserError = error.localizedDescription }
        if forceReload || Date().timeIntervalSince(lastReload) >= 300 {
            WidgetCenter.shared.reloadTimelines(ofKind: "ActivityWatchToday")
            WidgetCenter.shared.reloadTimelines(ofKind: "ActivityWatchChrome")
            lastReload = Date()
        }
    }

    func discover() async {
        guard !loadingBuckets else { return }
        loadingBuckets = true
        defer { loadingBuckets = false }
        do { buckets = try await ActivityClient().buckets(settings: settings) }
        catch { self.error = "Could not load sources: \(error.localizedDescription)" }
    }

    func save() async {
        guard let store, !refreshing else { return }
        do {
            _ = try settings.validatedURL()
            let selected = settings.chromeProfiles.filter { !$0.bucket.isEmpty }
            guard Set(selected.map(\.bucket)).count == selected.count else {
                throw ActivityError.message("Choose different Chrome sources for the two profiles.")
            }
            settings.revision = UUID()
            try store.saveSettings(settings)
            snapshot = nil
            browserSnapshot = nil
            await refresh(forceReload: true)
        } catch { self.error = error.localizedDescription }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginMessage = SMAppService.mainApp.status == .requiresApproval ?
                "Allow ActivityWatch Widget in System Settings → General → Login Items." : nil
        } catch { loginMessage = error.localizedDescription }
    }
}
