import AppKit
import Combine
import Foundation

struct RefreshGate {
    private(set) var isRefreshing = false

    mutating func begin() -> Bool {
        guard !isRefreshing else { return false }
        isRefreshing = true
        return true
    }

    mutating func end() {
        isRefreshing = false
    }
}

@MainActor
final class UsageService: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var connectionStatus: ConnectionStatus = .refreshing
    @Published private(set) var codexAppURL: URL?
    @Published private(set) var connectionDetail: String?
    @Published private(set) var clientSelectionError: String?

    private let client: CodexAppServerClient
    private let cache: CacheService
    private let notifications: NotificationService
    private let scriptableSync: ScriptableSyncService
    private var refreshTimer: Timer?
    private var refreshGate = RefreshGate()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var applicationTerminationObserver: NSObjectProtocol?

    init(
        client: CodexAppServerClient = CodexAppServerClient(),
        cache: CacheService = CacheService(),
        scriptableSync: ScriptableSyncService? = nil
    ) {
        self.client = client
        self.cache = cache
        self.notifications = NotificationService(cache: cache)
        self.scriptableSync = scriptableSync ?? ScriptableSyncService()
        self.snapshot = cache.loadSnapshot()
        self.codexAppURL = Self.findCodexApp()
        if snapshot != nil { connectionStatus = .cached }
        client.onRateLimitsUpdated = { [weak self] update in
            Task { @MainActor [weak self] in self?.applyEvent(update) }
        }
    }

    func start() {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        observeWorkspaceRecoveryEvents()
        observeApplicationTermination()
        exportCurrentSnapshotIfAvailable()
        Task { await refresh() }
    }

    func refresh(forceScriptableExport: Bool = false) async {
        guard refreshGate.begin() else { return }
        defer { refreshGate.end() }
        connectionStatus = .refreshing
        codexAppURL = Self.findCodexApp()
        do {
            let response = try await client.readRateLimits()
            let preferred = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits
            var updated = UsageSnapshot.from(rateLimitSnapshot: preferred, fullResetAvailableCount: response.rateLimitResetCredits?.availableCount)
            updated.fullResetCredits = response.rateLimitResetCredits?.credits
            guard updated.hasAnyWindow else {
                connectionStatus = snapshot == nil ? .dataUnavailable : .cached
                connectionDetail = "客户端没有返回额度窗口。稍后刷新；若持续出现，请确认客户端已登录。"
                exportCurrentSnapshotIfAvailable()
                return
            }
            snapshot = updated
            cache.save(snapshot: updated)
            connectionStatus = .connected
            connectionDetail = nil
            exportCurrentSnapshotIfAvailable(force: forceScriptableExport)
            notifications.evaluate(snapshot: updated,
                                   enabled: UserDefaults.standard.object(forKey: SettingsKeys.notificationsEnabled) as? Bool ?? true,
                                   notify80: UserDefaults.standard.object(forKey: SettingsKeys.notify80) as? Bool ?? true,
                                   notify95: UserDefaults.standard.object(forKey: SettingsKeys.notify95) as? Bool ?? true)
            notifications.evaluateResetExpiry(snapshot: updated,
                enabled: UserDefaults.standard.object(forKey: SettingsKeys.notificationsEnabled) as? Bool ?? true,
                notifyExpiry: UserDefaults.standard.object(forKey: SettingsKeys.notifyResetExpiry) as? Bool ?? true)
        } catch let error as CodexAppServerClientError {
            if error.shouldInvalidateConnection { client.invalidateConnection() }
            switch error {
            case .executableNotFound:
                connectionStatus = .codexNotFound
                connectionDetail = "未找到可运行的 Codex。客户端可能未安装或更新后位置已变化，请在设置中选择 ChatGPT / Codex.app。"
            case .requestTimedOut:
                connectionStatus = snapshot == nil ? .appServerUnavailable : .cached
                connectionDetail = "客户端响应超时。请检查网络及客户端登录状态，然后点击重新连接。"
            case .serverUnavailable:
                connectionStatus = snapshot == nil ? .appServerUnavailable : .cached
                connectionDetail = "本地服务启动或额度请求失败。请打开客户端确认登录和联网正常，再点击重新连接。"
            case .malformedResponse:
                connectionStatus = snapshot == nil ? .dataUnavailable : .cached
                connectionDetail = "额度响应无法识别，客户端接口可能已变化。请重新连接；仍失败时需要更新 Meter。"
            }
            exportCurrentSnapshotIfAvailable()
        } catch {
            connectionStatus = snapshot == nil ? .offline : .cached
            connectionDetail = error is DecodingError
                ? "额度数据格式发生变化，无法解析。请更新 Meter 或重新连接。"
                : "当前无法取得数据。请确认客户端可正常联网和使用，再点击重新连接。"
            exportCurrentSnapshotIfAvailable()
        }
    }

    func syncToScriptable() {
        exportCurrentSnapshotIfAvailable(force: true)
    }

    func reconnect() async {
        client.invalidateConnection()
        for _ in 0..<20 where refreshGate.isRefreshing {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        await refresh(forceScriptableExport: true)
    }

    func openCodex() {
        guard let codexAppURL else { return }
        NSWorkspace.shared.openApplication(at: codexAppURL, configuration: .init()) { _, _ in }
    }

    func chooseClientApplication() {
        let panel = NSOpenPanel()
        panel.title = "选择 ChatGPT / Codex 客户端"
        panel.message = "请选择已安装并登录的官方客户端 .app。"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.pathExtension == "app", CodexAppServerClient.executable(in: url) != nil else {
            clientSelectionError = "所选应用未包含可运行的 Codex，请选择正确的客户端。"
            return
        }
        do {
            let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: "codexMeter.clientApplicationBookmark")
            clientSelectionError = nil
            codexAppURL = url
            Task { await reconnect() }
        } catch { clientSelectionError = "无法保存客户端位置，请重新选择。" }
    }

    func useAutomaticClientDiscovery() {
        UserDefaults.standard.removeObject(forKey: "codexMeter.clientApplicationBookmark")
        clientSelectionError = nil
        Task { await reconnect() }
    }

    private func applyEvent(_ update: RateLimitSnapshot) {
        guard var snapshot else { return }
        snapshot.mergeSparse(update)
        snapshot.lastSuccessfulSync = .now
        snapshot.isCached = false
        self.snapshot = snapshot
        cache.save(snapshot: snapshot)
        connectionStatus = .connected
        connectionDetail = nil
        exportCurrentSnapshotIfAvailable()
    }

    private func exportCurrentSnapshotIfAvailable(force: Bool = false) {
        guard let snapshot else { return }
        _ = scriptableSync.exportIfNeeded(snapshot: snapshot, sourceStatus: connectionStatus, force: force)
    }

    private func observeWorkspaceRecoveryEvents() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in await self?.refresh() }
            }
            workspaceObservers.append(observer)
        }
    }

    private func observeApplicationTermination() {
        guard applicationTerminationObserver == nil else { return }
        let client = self.client
        applicationTerminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            client.stop()
        }
    }

    private static func findCodexApp() -> URL? {
        CodexAppServerClient.findApplication()
    }

    deinit {
        refreshTimer?.invalidate()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        if let applicationTerminationObserver {
            NotificationCenter.default.removeObserver(applicationTerminationObserver)
        }
        client.stop()
    }
}

enum SettingsKeys {
    static let menuBarDisplay = "codexMeter.menuBarDisplay"
    static let displayUsedPercent = "codexMeter.displayUsedPercent"
    static let notificationsEnabled = "codexMeter.notificationsEnabled"
    static let notify80 = "codexMeter.notify80"
    static let notify95 = "codexMeter.notify95"
    static let launchAtLogin = "codexMeter.launchAtLogin"
    static let notifyResetExpiry = "codexMeter.notifyResetExpiry"
}
