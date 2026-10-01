import Foundation

struct CacheRecord: Codable, Equatable {
    let snapshot: UsageSnapshot
}

final class CacheService {
    private let defaults: UserDefaults
    private let cacheKey = "codexMeter.usageSnapshot.v1"
    private let notificationKey = "codexMeter.notificationDedupe.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSnapshot() -> UsageSnapshot? {
        guard let data = defaults.data(forKey: cacheKey),
              let record = try? JSONDecoder().decode(CacheRecord.self, from: data) else { return nil }
        var snapshot = record.snapshot
        snapshot.isCached = true
        return snapshot
    }

    func save(snapshot: UsageSnapshot) {
        var liveSnapshot = snapshot
        liveSnapshot.isCached = false
        guard let data = try? JSONEncoder().encode(CacheRecord(snapshot: liveSnapshot)) else { return }
        defaults.set(data, forKey: cacheKey)
    }

    func loadNotificationDedupe() -> NotificationDedupeState {
        guard let data = defaults.data(forKey: notificationKey),
              let value = try? JSONDecoder().decode(NotificationDedupeState.self, from: data) else { return NotificationDedupeState() }
        return value
    }

    func save(notificationDedupe: NotificationDedupeState) {
        guard let data = try? JSONEncoder().encode(notificationDedupe) else { return }
        defaults.set(data, forKey: notificationKey)
    }

    func hasDeliveredResetExpiry(_ key: String) -> Bool {
        (defaults.stringArray(forKey: "codexMeter.resetExpiryNotifications.v1") ?? []).contains(key)
    }

    func markResetExpiryDelivered(_ key: String) {
        var keys = Set(defaults.stringArray(forKey: "codexMeter.resetExpiryNotifications.v1") ?? [])
        keys.insert(key)
        defaults.set(Array(keys), forKey: "codexMeter.resetExpiryNotifications.v1")
    }
}
