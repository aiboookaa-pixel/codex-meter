import SwiftUI

@main
struct CodexMeterApp: App {
    @StateObject private var usageService: UsageService
    @StateObject private var scriptableSync: ScriptableSyncService

    init() {
        let sync = ScriptableSyncService()
        let service = UsageService(scriptableSync: sync)
        _scriptableSync = StateObject(wrappedValue: sync)
        _usageService = StateObject(wrappedValue: service)
        LaunchAtLoginService.applySavedPreference()
        service.start()
    }

    var body: some Scene {
        MenuBarExtra {
            UsagePopoverView(service: usageService)
        } label: {
            MenuBarLabelView(snapshot: usageService.snapshot, status: usageService.connectionStatus)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(usageService: usageService, scriptableSync: scriptableSync)
        }

        // `SettingsLink` is only available on macOS 14.  This dedicated native
        // window gives the menu-bar button a reliable settings entry point on macOS 13.
        Window("Codex Meter 设置", id: "settings") {
            SettingsView(usageService: usageService, scriptableSync: scriptableSync)
        }
        .defaultSize(width: 460, height: 560)
        .windowResizability(.contentSize)
    }
}
