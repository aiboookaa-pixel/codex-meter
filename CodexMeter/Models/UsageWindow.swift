import Foundation

enum UsageWindowKind: String, Codable, CaseIterable, Identifiable {
    case fiveHours
    case weekly
    case unknown

    var id: String { rawValue }
    var title: String {
        switch self {
        case .fiveHours: return "5 小时额度"
        case .weekly: return "每周额度"
        case .unknown: return "其他额度"
        }
    }

    static func classify(durationMinutes: Int?) -> UsageWindowKind {
        guard let durationMinutes else { return .unknown }
        if (240...360).contains(durationMinutes) { return .fiveHours }
        if (8_640...11_520).contains(durationMinutes) { return .weekly }
        return .unknown
    }
}

struct UsageWindow: Codable, Equatable, Identifiable {
    let usedPercent: Int
    let windowDurationMinutes: Int?
    let resetsAt: Date?

    init(usedPercent: Int, durationMinutes: Int?, resetsAt: Date?) {
        self.usedPercent = min(max(usedPercent, 0), 100)
        self.windowDurationMinutes = durationMinutes
        self.resetsAt = resetsAt
    }

    var id: String { "\(kind.rawValue)-\(resetsAt?.timeIntervalSince1970 ?? 0)" }
    var kind: UsageWindowKind { UsageWindowKind.classify(durationMinutes: windowDurationMinutes) }
    var remainingPercent: Int { 100 - usedPercent }

    func remainingText(now: Date = .now) -> String {
        guard let resetsAt else { return "重置时间当前不可用" }
        guard resetsAt > now else { return "等待更新" }
        let seconds = max(0, Int(resetsAt.timeIntervalSince(now)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)天\(hours)小时后" }
        if hours > 0 { return "\(hours)小时\(minutes)分钟后" }
        return "\(max(1, minutes))分钟后"
    }

    func absoluteResetText(locale: Locale = .current, calendar: Calendar = .current) -> String {
        guard let resetsAt else { return "当前不可用" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = .current
        formatter.dateFormat = calendar.isDateInToday(resetsAt) ? "今天 HH:mm" : "M月d日 HH:mm"
        return formatter.string(from: resetsAt)
    }
}

struct NotificationDedupeState: Codable, Equatable {
    private var deliveredKeys: Set<String> = []

    mutating func shouldDeliver(kind: UsageWindowKind, resetsAt: Date?, threshold: Int) -> Bool {
        let resetIdentifier = Int(resetsAt?.timeIntervalSince1970 ?? 0)
        let key = "\(kind.rawValue).\(resetIdentifier).\(threshold)"
        guard !deliveredKeys.contains(key) else { return false }
        deliveredKeys.insert(key)
        return true
    }
}
