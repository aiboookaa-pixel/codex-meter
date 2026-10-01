import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    private let cache: CacheService
    private let center: UNUserNotificationCenter
    private var pendingExpiryKeys: Set<String> = []

    init(cache: CacheService, center: UNUserNotificationCenter = .current()) {
        self.cache = cache
        self.center = center
    }

    func evaluate(snapshot: UsageSnapshot, enabled: Bool, notify80: Bool, notify95: Bool) {
        guard enabled else { return }
        Task {
            let granted = try? await center.requestAuthorization(options: [.alert, .sound])
            guard granted == true else { return }
            var dedupe = cache.loadNotificationDedupe()
            for window in [snapshot.fiveHours, snapshot.weekly].compactMap({ $0 }) {
                for threshold in [80, 95] where (threshold != 80 || notify80) && (threshold != 95 || notify95) {
                    guard window.usedPercent >= threshold,
                          dedupe.shouldDeliver(kind: window.kind, resetsAt: window.resetsAt, threshold: threshold) else { continue }
                    let content = UNMutableNotificationContent()
                    content.title = "Codex Meter"
                    content.body = "\(window.kind.title)已使用 \(window.usedPercent)%"
                    content.sound = .default
                    let request = UNNotificationRequest(identifier: "codex-meter.\(window.kind.rawValue).\(threshold).\(Int(window.resetsAt?.timeIntervalSince1970 ?? 0))", content: content, trigger: nil)
                    try? await center.add(request)
                }
            }
            cache.save(notificationDedupe: dedupe)
        }
    }

    func evaluateResetExpiry(snapshot: UsageSnapshot, enabled: Bool, notifyExpiry: Bool) {
        guard enabled, notifyExpiry, !snapshot.isCached else { return }
        let credits = snapshot.sortedAvailableResetCredits.filter { $0.isExpiringSoon() }
        guard !credits.isEmpty else { return }
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            for credit in credits {
                let key = credit.notificationKey
                guard !cache.hasDeliveredResetExpiry(key), !pendingExpiryKeys.contains(key), credit.isExpiringSoon() else { continue }
                pendingExpiryKeys.insert(key)
                defer { pendingExpiryKeys.remove(key) }
                let content = UNMutableNotificationContent()
                content.title = "赠送 Full Reset 即将到期"
                content.body = "\(credit.expiryText())。请在官方客户端查看和使用。"
                content.sound = .default
                do {
                    try await center.add(UNNotificationRequest(identifier: "codex-meter.reset-expiry.\(key)", content: content, trigger: nil))
                    cache.markResetExpiryDelivered(key)
                } catch { /* Retry on a later successful quota refresh. */ }
            }
        }
    }
}
