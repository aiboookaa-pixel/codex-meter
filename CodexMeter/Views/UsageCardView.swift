import SwiftUI
import Combine

struct UsageCardView: View {
    let kind: UsageWindowKind
    let window: UsageWindow?
    let isCached: Bool
    @State private var now = Date.now
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(kind.title, systemImage: kind == .fiveHours ? "clock" : "calendar")
                    .font(.headline)
                Spacer()
                if isCached { Text("缓存数据").font(.caption).foregroundStyle(.secondary) }
            }
            if let window {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(window.remainingPercent)%")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(kind == .fiveHours ? .green : .blue)
                    Text("剩余").font(.title3.weight(.semibold))
                    Spacer()
                    Text("已使用 \(window.usedPercent)%").foregroundStyle(.secondary)
                }
                ProgressView(value: Double(window.usedPercent), total: 100)
                    .tint(kind == .fiveHours ? .green : .blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text("重置：\(window.remainingText(now: now))")
                    Text("时间：\(window.absoluteResetText())").foregroundStyle(.secondary)
                }
                .font(.callout)
            } else {
                Text("当前不可用")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 65, alignment: .leading)
            }
        }
        .padding(12)
        .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onReceive(ticker) { now = $0 }
    }
}
