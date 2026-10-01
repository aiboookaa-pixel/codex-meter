import AppKit
import Foundation

enum ScriptableSyncStatus: Equatable {
    case disabled
    case unconfigured
    case syncing
    case normal
    case failed(String)

    var localizedDescription: String {
        switch self {
        case .disabled: return "未启用"
        case .unconfigured: return "未配置"
        case .syncing: return "正在同步"
        case .normal: return "正常"
        case .failed: return "导出失败"
        }
    }
}

enum ScriptableExportResult: Equatable {
    case exported(URL)
    case skippedDisabled
    case skippedUnconfigured
    case skippedUnchanged
    case failed(String)
}

enum ScriptableSnapshotWriter {
    static func write(
        _ snapshot: ScriptableUsageSnapshot,
        toRoot rootURL: URL,
        fileManager: FileManager = .default,
        replaceExisting: ((URL, URL) throws -> Void)? = nil
    ) throws -> URL {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            throw CocoaError(.fileWriteInvalidFileName)
        }

        let outputDirectory = rootURL.appendingPathComponent("CodexMeter", isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let destination = outputDirectory.appendingPathComponent("usage.json", isDirectory: false)
        let temporary = outputDirectory.appendingPathComponent(".usage.\(UUID().uuidString).tmp", isDirectory: false)
        let data = try ScriptableJSONCoding.encoder().encode(snapshot)
        defer { try? fileManager.removeItem(at: temporary) }

        try data.write(to: temporary, options: [.atomic])
        let persistedData = try Data(contentsOf: temporary)
        _ = try ScriptableJSONCoding.decoder().decode(ScriptableUsageSnapshot.self, from: persistedData)

        if fileManager.fileExists(atPath: destination.path) {
            if let replaceExisting {
                try replaceExisting(destination, temporary)
            } else {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
            }
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
        return destination
    }
}

@MainActor
final class ScriptableSyncService: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var selectedDirectoryURL: URL?
    @Published private(set) var status: ScriptableSyncStatus
    @Published private(set) var lastSuccessfulExport: Date?

    private enum Keys {
        static let enabled = "codexMeter.scriptableSync.enabled"
        static let directoryBookmark = "codexMeter.scriptableSync.directoryBookmark"
        static let lastSuccessfulExport = "codexMeter.scriptableSync.lastSuccessfulExport"
    }

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private var lastFingerprint: ScriptableExportFingerprint?

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
        let restoredEnabled = defaults.bool(forKey: Keys.enabled)
        let restoredLastExport = defaults.object(forKey: Keys.lastSuccessfulExport) as? Date
        var restoredDirectory: URL?
        var bookmarkWasStale = false

        if let bookmark = defaults.data(forKey: Keys.directoryBookmark) {
            restoredDirectory = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &bookmarkWasStale
            )
        }

        isEnabled = restoredEnabled
        selectedDirectoryURL = restoredDirectory
        lastSuccessfulExport = restoredLastExport
        if !restoredEnabled {
            status = .disabled
        } else if restoredDirectory == nil {
            status = .unconfigured
        } else {
            status = .normal
        }

        if bookmarkWasStale, let restoredDirectory {
            try? saveBookmark(for: restoredDirectory)
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Keys.enabled)
        status = enabled ? (selectedDirectoryURL == nil ? .unconfigured : .normal) : .disabled
    }

    func chooseDirectory(completion: ((Bool) -> Void)? = nil) {
        let panel = NSOpenPanel()
        panel.title = "选择 Scriptable iCloud 文件夹"
        panel.message = "请选择 iCloud Drive 中的 Scriptable 根目录。Codex Meter 将在其中维护 CodexMeter/usage.json。"
        panel.prompt = "选择文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        panel.begin { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else {
                completion?(false)
                return
            }
            do {
                try self.configureDirectory(url)
                completion?(true)
            } catch {
                self.status = .failed(error.localizedDescription)
                completion?(false)
            }
        }
    }

    func configureDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw CocoaError(.fileWriteInvalidFileName) }
        try saveBookmark(for: url)
        selectedDirectoryURL = url
        status = isEnabled ? .normal : .disabled
    }

    @discardableResult
    func exportIfNeeded(
        snapshot: UsageSnapshot,
        sourceStatus: ConnectionStatus,
        force: Bool = false
    ) -> ScriptableExportResult {
        guard isEnabled else { return .skippedDisabled }
        guard let selectedDirectoryURL else {
            status = .unconfigured
            return .skippedUnconfigured
        }

        let fingerprint = ScriptableExportFingerprint(snapshot: snapshot, sourceStatus: sourceStatus)
        guard ScriptableExportDecision.shouldExport(previous: lastFingerprint, current: fingerprint, force: force) else {
            return .skippedUnchanged
        }

        status = .syncing
        let didAccessSecurityScope = selectedDirectoryURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope { selectedDirectoryURL.stopAccessingSecurityScopedResource() }
        }

        do {
            let payload = ScriptableUsageSnapshot(snapshot: snapshot, sourceStatus: sourceStatus)
            let outputURL = try ScriptableSnapshotWriter.write(payload, toRoot: selectedDirectoryURL, fileManager: fileManager)
            lastFingerprint = fingerprint
            lastSuccessfulExport = payload.exportedAt
            defaults.set(payload.exportedAt, forKey: Keys.lastSuccessfulExport)
            status = .normal
            return .exported(outputURL)
        } catch {
            status = .failed(error.localizedDescription)
            return .failed(error.localizedDescription)
        }
    }

    private func saveBookmark(for url: URL) throws {
        // This project intentionally remains non-sandboxed. A standard bookmark
        // restores the user's chosen folder without introducing new entitlements.
        let bookmark = try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: [.isDirectoryKey],
            relativeTo: nil
        )
        defaults.set(bookmark, forKey: Keys.directoryBookmark)
    }
}
