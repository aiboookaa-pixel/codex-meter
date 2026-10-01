import Foundation
import ServiceManagement

@available(macOS 13.0, *)
enum LaunchAtLoginService {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func applySavedPreference() {
        guard UserDefaults.standard.bool(forKey: SettingsKeys.launchAtLogin), !isEnabled else { return }
        do { try setEnabled(true) }
        catch { NSLog("Codex Meter could not enable Login Item: %@", error.localizedDescription) }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }
}
