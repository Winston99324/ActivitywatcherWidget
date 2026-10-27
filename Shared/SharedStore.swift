import Foundation
import Darwin

// Atomic files plus a process-shared advisory lock protect app/widget concurrent writers.
struct SharedStore {
    let directory: URL

    init(directory: URL? = nil) throws {
        if let directory { self.directory = directory }
        else {
            guard let group = Bundle.main.object(forInfoDictionaryKey: "ActivityAppGroup") as? String,
                  !group.hasPrefix("."), !group.contains("$("),
                  let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
                throw ActivityError.message("Shared storage is unavailable. Sign both targets with the same team and App Group, then rebuild.")
            }
            self.directory = container.appendingPathComponent("ActivityWatchWidget", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private func locked<T>(_ work: () throws -> T) throws -> T {
        let fd = open(directory.appendingPathComponent("store.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw ActivityError.message("Cannot open shared storage lock.") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw ActivityError.message("Cannot lock shared storage.") }
        defer { flock(fd, LOCK_UN) }
        return try work()
    }

    private func read<T: Decodable>(_ name: String) throws -> T? {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
    private func write<T: Encodable>(_ value: T, name: String) throws {
        try JSONEncoder().encode(value).write(to: directory.appendingPathComponent(name), options: .atomic)
    }
    func settings() throws -> ActivitySettings {
        try locked {
            if let saved: ActivitySettings = try read("settings.json") { return saved }
            let initial = ActivitySettings()
            try write(initial, name: "settings.json")
            return initial
        }
    }
    func saveSettings(_ settings: ActivitySettings) throws {
        try locked { try write(settings, name: "settings.json") }
    }
    func snapshot() throws -> ActivitySnapshot? {
        try locked {
            let config: ActivitySettings? = try read("settings.json")
            // A damaged cache is disposable; it must not prevent a new network fetch.
            let cached: ActivitySnapshot? = try? read("snapshot.json")
            return cached?.settingsRevision == config?.revision ? cached : nil
        }
    }
    @discardableResult func save(_ snapshot: ActivitySnapshot) throws -> Bool {
        try locked {
            let config: ActivitySettings? = try read("settings.json")
            guard snapshot.settingsRevision == config?.revision else { return false }
            if let current: ActivitySnapshot = try? read("snapshot.json"),
               current.settingsRevision == snapshot.settingsRevision, current.fetchedAt > snapshot.fetchedAt { return false }
            try write(snapshot, name: "snapshot.json")
            return true
        }
    }

    func browserSnapshot() throws -> BrowserSnapshot? {
        try locked {
            let config: ActivitySettings? = try read("settings.json")
            let cached: BrowserSnapshot? = try? read("browser-snapshot.json")
            return cached?.settingsRevision == config?.revision ? cached : nil
        }
    }
    @discardableResult func saveBrowser(_ snapshot: BrowserSnapshot) throws -> Bool {
        try locked {
            let config: ActivitySettings? = try read("settings.json")
            guard snapshot.settingsRevision == config?.revision else { return false }
            if let current: BrowserSnapshot = try? read("browser-snapshot.json"),
               current.settingsRevision == snapshot.settingsRevision, current.fetchedAt > snapshot.fetchedAt { return false }
            try write(snapshot, name: "browser-snapshot.json")
            return true
        }
    }
}
