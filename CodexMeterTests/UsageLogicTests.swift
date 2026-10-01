import XCTest
@testable import CodexMeter

final class UsageLogicTests: XCTestCase {
    func testExpiredCountdownWaitsForRealUpdate() {
        let date = Date(timeIntervalSince1970: 1000)
        let window = UsageWindow(usedPercent: 80, durationMinutes: 300, resetsAt: date)
        XCTAssertEqual(window.remainingText(now: date), "等待更新")
        XCTAssertEqual(window.remainingText(now: date.addingTimeInterval(60)), "等待更新")
        XCTAssertEqual(window.remainingText(now: date.addingTimeInterval(-30)), "1分钟后")
    }

    func testResetCreditsSortByExpiryAndWarnOnlyBeforeExpiry() {
        let early = RateLimitResetCredit(grantedAt: 50, expiresAt: 2000, status: "available", resetType: "codexRateLimits")
        let late = RateLimitResetCredit(grantedAt: 40, expiresAt: 4000, status: "available", resetType: "codexRateLimits")
        let noExpiry = RateLimitResetCredit(grantedAt: 30, expiresAt: nil, status: "available", resetType: "codexRateLimits")
        let used = RateLimitResetCredit(grantedAt: 20, expiresAt: 1000, status: "redeemed", resetType: "codexRateLimits")
        var snapshot = UsageSnapshot.from(rateLimitSnapshot: RateLimitSnapshot(primary: nil, secondary: nil), fullResetAvailableCount: 3)
        snapshot.fullResetCredits = [noExpiry, late, used, early]
        XCTAssertEqual(snapshot.sortedAvailableResetCredits, [early, late, noExpiry])
        XCTAssertTrue(early.isExpiringSoon(now: Date(timeIntervalSince1970: 1000)))
        XCTAssertFalse(early.isExpiringSoon(now: Date(timeIntervalSince1970: 2000)))
        XCTAssertFalse(early.isExpiringSoon(now: Date(timeIntervalSince1970: -300000)))
        XCTAssertFalse(noExpiry.isExpiringSoon())
        XCTAssertFalse(used.isExpiringSoon(now: Date(timeIntervalSince1970: 900)))
        XCTAssertEqual(early.expiryText(now: Date(timeIntervalSince1970: 2000)), "已到期，等待更新")
    }

    func testResetExpiryNotificationDedupePersistsAcrossCacheInstances() throws {
        let name = "CodexMeterExpiryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let cache = CacheService(defaults: defaults)
        XCTAssertFalse(cache.hasDeliveredResetExpiry("credit-a"))
        cache.markResetExpiryDelivered("credit-a")
        XCTAssertTrue(CacheService(defaults: defaults).hasDeliveredResetExpiry("credit-a"))
        XCTAssertFalse(cache.hasDeliveredResetExpiry("credit-b"))
    }

    func testGiftedResetCreditDatesAndLegacyResponses() throws {
        let data = Data(#"{"availableCount":2,"credits":[{"id":"ignored","grantedAt":1790108178,"expiresAt":1792700178,"status":"available","resetType":"codexRateLimits"}]}"#.utf8)
        let credits = try JSONDecoder().decode(RateLimitResetCredits.self, from: data)
        XCTAssertEqual(credits.availableCount, 2)
        XCTAssertEqual(credits.credits?.first?.grantedDate, Date(timeIntervalSince1970: 1790108178))
        XCTAssertEqual(credits.credits?.first?.expiryDate, Date(timeIntervalSince1970: 1792700178))
        let legacy = try JSONDecoder().decode(RateLimitResetCredits.self, from: Data(#"{"availableCount":1}"#.utf8))
        XCTAssertNil(legacy.credits)
        let noExpiry = try JSONDecoder().decode(RateLimitResetCredit.self, from: Data(#"{"grantedAt":1000,"expiresAt":null,"status":"available","resetType":"codexRateLimits"}"#.utf8))
        XCTAssertNil(noExpiry.expiryDate)
    }

    func testGiftedResetDatesSurviveCacheAndSparseUpdates() throws {
        var snapshot = UsageSnapshot.from(rateLimitSnapshot: RateLimitSnapshot(primary: nil, secondary: nil), fullResetAvailableCount: 1)
        snapshot.fullResetCredits = [RateLimitResetCredit(grantedAt: 1000, expiresAt: 2000, status: "available", resetType: "codexRateLimits")]
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(UsageSnapshot.self, from: data), snapshot)
        snapshot.mergeSparse(RateLimitSnapshot(primary: RateLimitWindowPayload(usedPercent: 5, windowDurationMins: 300, resetsAt: 3000), secondary: nil))
        XCTAssertEqual(snapshot.fullResetCredits?.first?.grantedAt, 1000)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "fullResetCredits")
        let oldData = try JSONSerialization.data(withJSONObject: legacy)
        XCTAssertNil(try JSONDecoder().decode(UsageSnapshot.self, from: oldData).fullResetCredits)
    }

    func testClassifiesKnownWindowsWithTolerance() {
        XCTAssertEqual(UsageWindowKind.classify(durationMinutes: 300), .fiveHours)
        XCTAssertEqual(UsageWindowKind.classify(durationMinutes: 10_080), .weekly)
        XCTAssertEqual(UsageWindowKind.classify(durationMinutes: 359), .fiveHours)
        XCTAssertEqual(UsageWindowKind.classify(durationMinutes: 11_000), .weekly)
    }

    func testUnknownDurationIsNeverMisclassified() {
        XCTAssertEqual(UsageWindowKind.classify(durationMinutes: 60), .unknown)
        XCTAssertEqual(UsageWindowKind.classify(durationMinutes: nil), .unknown)
    }

    func testRemainingPercentIsDerivedAndClamped() {
        XCTAssertEqual(UsageWindow(usedPercent: 24, durationMinutes: 300, resetsAt: nil).remainingPercent, 76)
        XCTAssertEqual(UsageWindow(usedPercent: 120, durationMinutes: 300, resetsAt: nil).remainingPercent, 0)
        XCTAssertEqual(UsageWindow(usedPercent: -4, durationMinutes: 300, resetsAt: nil).remainingPercent, 100)
    }

    func testCountdownUsesLocalTimeDifference() {
        let now = Date(timeIntervalSince1970: 1_000)
        let window = UsageWindow(usedPercent: 1, durationMinutes: 300, resetsAt: Date(timeIntervalSince1970: 6_490))
        XCTAssertEqual(window.remainingText(now: now), "1小时31分钟后")
    }

    func testNotificationDedupeAllowsEachThresholdOncePerResetPeriod() {
        var dedupe = NotificationDedupeState()
        let firstReset = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(dedupe.shouldDeliver(kind: .fiveHours, resetsAt: firstReset, threshold: 80))
        XCTAssertFalse(dedupe.shouldDeliver(kind: .fiveHours, resetsAt: firstReset, threshold: 80))
        XCTAssertTrue(dedupe.shouldDeliver(kind: .fiveHours, resetsAt: firstReset, threshold: 95))
        XCTAssertTrue(dedupe.shouldDeliver(kind: .fiveHours, resetsAt: Date(timeIntervalSince1970: 2_000), threshold: 80))
        XCTAssertTrue(dedupe.shouldDeliver(kind: .weekly, resetsAt: firstReset, threshold: 80))
    }

    func testCacheRecordRoundTrips() throws {
        let snapshot = UsageSnapshot(
            fiveHours: UsageWindow(usedPercent: 24, durationMinutes: 300, resetsAt: Date(timeIntervalSince1970: 4_000)),
            weekly: nil,
            unknownWindows: [],
            fullResetAvailableCount: 0,
            lastSuccessfulSync: Date(timeIntervalSince1970: 3_000),
            isCached: false
        )
        let data = try JSONEncoder().encode(CacheRecord(snapshot: snapshot))
        XCTAssertEqual(try JSONDecoder().decode(CacheRecord.self, from: data), CacheRecord(snapshot: snapshot))
    }

    func testPayloadMapsOnlyRecognizedWindows() {
        let snapshot = UsageSnapshot.from(rateLimitSnapshot: RateLimitSnapshot(
            primary: RateLimitWindowPayload(usedPercent: 20, windowDurationMins: 300, resetsAt: 3_000),
            secondary: RateLimitWindowPayload(usedPercent: 9, windowDurationMins: 600, resetsAt: 4_000)
        ), fullResetAvailableCount: nil)
        XCTAssertEqual(snapshot.fiveHours?.remainingPercent, 80)
        XCTAssertNil(snapshot.weekly)
        XCTAssertEqual(snapshot.unknownWindows.count, 1)
    }
}
