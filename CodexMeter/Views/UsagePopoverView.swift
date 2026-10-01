import AppKit
import SwiftUI

struct UsagePopoverView: View {
  @ObservedObject var service: UsageService
  @Environment(\.openWindow) private var openWindow
  private var isCached: Bool {
    service.snapshot?.isCached == true || service.connectionStatus != .connected
  }

  var body: some View {
    VStack(spacing: 10) {
      HStack {
        HStack(spacing: 9) {
          Image(systemName: "c.circle.fill")
            .font(.system(size: 25, weight: .semibold))
          Text("Codex Usage").font(.system(size: 24, weight: .bold))
        }
        Spacer()
        Menu {
          Button {
            openWindow(id: "settings")
          } label: {
            Label("设置", systemImage: "gearshape")
          }
          Button {
            Task { await service.reconnect() }
          } label: {
            Label("重新连接", systemImage: "bolt.horizontal.circle")
          }
          Divider()
          Button {
            restartApplication()
          } label: {
            Label("重新启动 Codex Meter", systemImage: "arrow.clockwise.circle")
          }
          Button {
            NSApplication.shared.terminate(nil)
          } label: {
            Label("退出 Codex Meter", systemImage: "power")
          }
        } label: {
          Image(systemName: "ellipsis.circle").font(.title3)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("更多操作")
      }
      UsageCardView(kind: .fiveHours, window: service.snapshot?.fiveHours, isCached: isCached)
      UsageCardView(kind: .weekly, window: service.snapshot?.weekly, isCached: isCached)
      if let count = service.snapshot?.fullResetAvailableCount {
        VStack(alignment: .leading, spacing: 5) {
          HStack {
            Label("可用 Full Reset", systemImage: "cylinder.split.1x2")
            Spacer()
            Text("\(count) 次").fontWeight(.semibold)
          }
          if isCached {
            Text("缓存信息，次数和到期状态可能已变化").font(.caption).foregroundStyle(.secondary)
          }
          if service.snapshot?.fullResetCredits != nil {
            let available = service.snapshot?.sortedAvailableResetCredits ?? []
            ForEach(Array(available.enumerated()), id: \.offset) { index, credit in
              VStack(alignment: .leading, spacing: 2) {
                HStack {
                  Text(
                    "赠送 \(index + 1) · \(credit.grantedDate.formatted(date: .numeric, time: .omitted)) 发放"
                  )
                  Spacer()
                  Text(credit.expiryText())
                    .foregroundStyle(credit.isExpiringSoon() ? Color.orange : Color.secondary)
                }
                if let expiry = credit.expiryDate {
                  Text("到期：\(expiry.formatted(date: .numeric, time: .shortened))")
                } else {
                  Text("到期：未设置到期日期")
                }
              }
              .font(.caption)
              .foregroundStyle(.secondary)
            }
            if available.isEmpty && count > 0 {
              Text("赠送日期详情当前不可用").font(.caption).foregroundStyle(.secondary)
            }
          } else {
            Text("赠送日期详情当前不可用").font(.caption).foregroundStyle(.secondary)
          }
          Text("下次发放／恢复日期：当前不可用")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
          .background.opacity(0.62), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
      }
      Divider()
      HStack(spacing: 8) {
        Circle().fill(service.connectionStatus.isPositive ? .green : .orange).frame(
          width: 9, height: 9)
        Text(service.connectionStatus.localizedDescription)
        Spacer()
        if let date = service.snapshot?.lastSuccessfulSync {
          Text("最后更新：\(date.formatted(date: .omitted, time: .standard))")
            .foregroundStyle(.secondary)
            .font(.caption)
        }
      }
      if service.connectionStatus == .cached {
        Text("当前显示上次成功数据。网络恢复后会自动重连，也可以点击“重新连接”。")
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      if let detail = service.connectionDetail {
        Text(detail).font(.caption).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      HStack(spacing: 8) {
        Button {
          Task { await service.refresh(forceScriptableExport: true) }
        } label: {
          Label("刷新", systemImage: "arrow.clockwise")
        }
        .keyboardShortcut("r")
        Button {
          Task { await service.reconnect() }
        } label: {
          Label("重新连接", systemImage: "bolt.horizontal.circle")
        }
        Spacer()
        Button {
          service.openCodex()
        } label: {
          Label("打开 ChatGPT", systemImage: "arrow.up.forward.app")
        }
        .disabled(service.codexAppURL == nil)
        .buttonStyle(.borderedProminent)
      }
      .buttonStyle(.bordered)
      .controlSize(.regular)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(14)
    .frame(width: 420)
    .background(.regularMaterial)
  }

  private func restartApplication() {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) {
      _, error in
      guard error == nil else { return }
      NSApplication.shared.terminate(nil)
    }
  }
}
