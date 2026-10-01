import SwiftUI

struct MenuBarLabelView: View {
    let snapshot: UsageSnapshot?
    let status: ConnectionStatus
    @AppStorage(SettingsKeys.menuBarDisplay) private var displayMode = "both"
    @AppStorage(SettingsKeys.displayUsedPercent) private var displayUsedPercent = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.isPositive ? "c.circle.fill" : "c.circle")
            Text(title)
        }
    }

    private var title: String {
        guard let snapshot else { return "Codex …" }
        let values = [snapshot.fiveHours, snapshot.weekly].compactMap { window -> (String, Int)? in
            guard let window else { return nil }
            return (window.kind == .fiveHours ? "C" : "W", displayUsedPercent ? window.usedPercent : window.remainingPercent)
        }
        guard !values.isEmpty else { return "Codex …" }
        switch displayMode {
        case "codex": return "Codex \(values[0].1)%"
        case "numbers": return values.map { "\($0.1)%" }.joined(separator: " / ")
        case "icon": return ""
        default: return values.map { "\($0.0) \($0.1)%" }.joined(separator: " · ")
        }
    }
}
