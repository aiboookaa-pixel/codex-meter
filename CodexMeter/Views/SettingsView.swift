import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var usageService: UsageService
    @ObservedObject var scriptableSync: ScriptableSyncService
    @AppStorage(SettingsKeys.menuBarDisplay) private var displayMode = "both"
    @AppStorage(SettingsKeys.displayUsedPercent) private var displayUsedPercent = false
    @AppStorage(SettingsKeys.notificationsEnabled) private var notificationsEnabled = true
    @AppStorage(SettingsKeys.notify80) private var notify80 = true
    @AppStorage(SettingsKeys.notify95) private var notify95 = true
    @AppStorage(SettingsKeys.notifyResetExpiry) private var notifyResetExpiry = true
    @AppStorage(SettingsKeys.launchAtLogin) private var launchAtLogin = false
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section("客户端连接") {
                Text(usageService.codexAppURL?.path ?? "未找到客户端")
                    .font(.caption).lineLimit(2).foregroundStyle(.secondary)
                HStack {
                    Button("选择客户端…") { usageService.chooseClientApplication() }
                    Button("自动识别") { usageService.useAutomaticClientDiscovery() }
                }
                if let message = usageService.clientSelectionError {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            }
            Section("菜单栏显示") {
                Picker("显示形式", selection: $displayMode) {
                    Text("C 72% · W 81%").tag("both")
                    Text("Codex 72%").tag("codex")
                    Text("72% / 81%").tag("numbers")
                    Text("仅图标").tag("icon")
                }
                Toggle("显示已使用百分比", isOn: $displayUsedPercent)
            }
            Section("通知") {
                Toggle("启用通知", isOn: $notificationsEnabled)
                Toggle("使用达到 80% 时提醒", isOn: $notify80).disabled(!notificationsEnabled)
                Toggle("使用达到 95% 时提醒", isOn: $notify95).disabled(!notificationsEnabled)
                Toggle("赠送重置到期前 3 天提醒", isOn: $notifyResetExpiry).disabled(!notificationsEnabled)
            }
            Section("登录时启动") {
                Toggle("开机后自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in setLaunchAtLogin(enabled) }
                if let launchAtLoginError { Text(launchAtLoginError).font(.caption).foregroundStyle(.red) }
            }
            Section("iPhone / Scriptable") {
                Toggle("同步到 iPhone", isOn: Binding(
                    get: { scriptableSync.isEnabled },
                    set: { setScriptableSyncEnabled($0) }
                ))

                LabeledContent("Scriptable iCloud 文件夹") {
                    HStack(spacing: 8) {
                        Text(scriptableSync.selectedDirectoryURL?.path(percentEncoded: false) ?? "未选择")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(scriptableSync.selectedDirectoryURL == nil ? .secondary : .primary)
                        Button("选择文件夹") { chooseScriptableDirectory() }
                    }
                }

                LabeledContent("同步状态") {
                    Label(scriptableSync.status.localizedDescription, systemImage: scriptableStatusSymbol)
                        .foregroundStyle(scriptableStatusColor)
                }
                if case let .failed(message) = scriptableSync.status {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }

                LabeledContent("最近导出") {
                    if let date = scriptableSync.lastSuccessfulExport {
                        Text(date.formatted(date: .omitted, time: .standard))
                    } else {
                        Text("尚未导出").foregroundStyle(.secondary)
                    }
                }

                Button("立即同步") { usageService.syncToScriptable() }
                    .disabled(!scriptableSync.isEnabled || scriptableSync.selectedDirectoryURL == nil || usageService.snapshot == nil)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do { try LaunchAtLoginService.setEnabled(enabled); launchAtLoginError = nil }
        catch { launchAtLogin = LaunchAtLoginService.isEnabled; launchAtLoginError = "无法更新登录时启动：\(error.localizedDescription)" }
    }

    private func setScriptableSyncEnabled(_ enabled: Bool) {
        scriptableSync.setEnabled(enabled)
        guard enabled else { return }
        if scriptableSync.selectedDirectoryURL == nil {
            chooseScriptableDirectory()
        } else {
            usageService.syncToScriptable()
        }
    }

    private func chooseScriptableDirectory() {
        scriptableSync.chooseDirectory { selected in
            if selected { usageService.syncToScriptable() }
        }
    }

    private var scriptableStatusSymbol: String {
        switch scriptableSync.status {
        case .normal: return "checkmark.circle.fill"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .failed: return "exclamationmark.triangle.fill"
        case .disabled, .unconfigured: return "exclamationmark.circle"
        }
    }

    private var scriptableStatusColor: Color {
        switch scriptableSync.status {
        case .normal: return .green
        case .failed: return .red
        case .syncing: return .blue
        case .disabled, .unconfigured: return .orange
        }
    }
}
