import Foundation

struct UsageSnapshot: Codable, Equatable {
    var fiveHours: UsageWindow?
    var weekly: UsageWindow?
    var unknownWindows: [UsageWindow]
    var fullResetAvailableCount: Int?
    var lastSuccessfulSync: Date
    var isCached: Bool
    var fullResetCredits: [RateLimitResetCredit]? = nil

    var hasAnyWindow: Bool { fiveHours != nil || weekly != nil || !unknownWindows.isEmpty }
    var sortedAvailableResetCredits: [RateLimitResetCredit] {
        (fullResetCredits ?? []).filter { $0.status == "available" && $0.resetType == "codexRateLimits" }
            .sorted { ($0.expiresAt ?? Int.max, $0.grantedAt) < ($1.expiresAt ?? Int.max, $1.grantedAt) }
    }

    mutating func mergeSparse(_ update: RateLimitSnapshot) {
        let updated = UsageSnapshot.from(rateLimitSnapshot: update, fullResetAvailableCount: fullResetAvailableCount, date: lastSuccessfulSync, isCached: isCached)
        if let window = updated.fiveHours { fiveHours = window }
        if let window = updated.weekly { weekly = window }
        if !updated.unknownWindows.isEmpty { unknownWindows = updated.unknownWindows }
    }

    static func from(rateLimitSnapshot: RateLimitSnapshot, fullResetAvailableCount: Int?, date: Date = .now, isCached: Bool = false) -> UsageSnapshot {
        var fiveHours: UsageWindow?
        var weekly: UsageWindow?
        var unknown: [UsageWindow] = []
        for payload in [rateLimitSnapshot.primary, rateLimitSnapshot.secondary].compactMap({ $0 }) {
            let window = UsageWindow(usedPercent: payload.usedPercent, durationMinutes: payload.windowDurationMins, resetsAt: payload.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) })
            switch window.kind {
            case .fiveHours: fiveHours = window
            case .weekly: weekly = window
            case .unknown: unknown.append(window)
            }
        }
        return UsageSnapshot(fiveHours: fiveHours, weekly: weekly, unknownWindows: unknown, fullResetAvailableCount: fullResetAvailableCount, lastSuccessfulSync: date, isCached: isCached)
    }
}

struct RateLimitWindowPayload: Codable, Equatable {
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: Int?
}

struct RateLimitSnapshot: Codable, Equatable {
    let primary: RateLimitWindowPayload?
    let secondary: RateLimitWindowPayload?
}

struct RateLimitResetCredits: Codable, Equatable {
    let availableCount: Int
    var credits: [RateLimitResetCredit]? = nil
}

struct RateLimitResetCredit: Codable, Equatable {
    let grantedAt: Int
    let expiresAt: Int?
    let status: String
    let resetType: String
    var id: String? = nil

    var grantedDate: Date { Date(timeIntervalSince1970: TimeInterval(grantedAt)) }
    var expiryDate: Date? { expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
    var notificationKey: String { id ?? "\(grantedAt).\(expiresAt ?? 0).\(resetType)" }
    func isExpiringSoon(now: Date = .now) -> Bool {
        guard status == "available", resetType == "codexRateLimits", let expiryDate else { return false }
        return expiryDate > now && expiryDate.timeIntervalSince(now) <= 3 * 86_400
    }
    func expiryText(now: Date = .now) -> String {
        guard let expiryDate else { return "未设置到期日期" }
        guard expiryDate > now else { return "已到期，等待更新" }
        let hours = Int(ceil(expiryDate.timeIntervalSince(now) / 3600))
        if hours >= 24 { return "还有 \(hours / 24) 天 \(hours % 24) 小时到期" }
        return "还有 \(hours) 小时到期"
    }
}

struct AccountRateLimitsResponse: Codable {
    let rateLimits: RateLimitSnapshot
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?
    let rateLimitResetCredits: RateLimitResetCredits?
}
