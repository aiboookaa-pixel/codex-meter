import XCTest
import SwiftUI
@testable import CodexMeter

final class UsageServiceRecoveryTests: XCTestCase {
    @MainActor
    func testPopoverFitsOneScreenWithTwoGiftedResetCredits() throws {
        let name = "CodexMeterLayoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let cache = CacheService(defaults: defaults)
        let now = Int(Date.now.timeIntervalSince1970)
        var snapshot = UsageSnapshot.from(rateLimitSnapshot: RateLimitSnapshot(
            primary: RateLimitWindowPayload(usedPercent: 28, windowDurationMins: 300, resetsAt: now + 6000),
            secondary: RateLimitWindowPayload(usedPercent: 19, windowDurationMins: 10080, resetsAt: now + 300000)
        ), fullResetAvailableCount: 2)
        snapshot.fullResetCredits = [
            RateLimitResetCredit(grantedAt: now - 600000, expiresAt: now + 2000000, status: "available", resetType: "codexRateLimits"),
            RateLimitResetCredit(grantedAt: now - 100000, expiresAt: now + 2500000, status: "available", resetType: "codexRateLimits")
        ]
        cache.save(snapshot: snapshot)
        let service = UsageService(cache: cache)
        let host = NSHostingView(rootView: UsagePopoverView(service: service))
        let size = host.fittingSize
        XCTAssertEqual(size.width, 420, accuracy: 1)
        XCTAssertLessThanOrEqual(size.height, 620, "All cards and action buttons must fit without scrolling")
        XCTAssertGreaterThan(size.height, 300)
        print("Popover cached layout size: \(size)")
    }

    func testRefreshGatePreventsOverlappingRequestsAndCanBeReleased() {
        var gate = RefreshGate()

        XCTAssertTrue(gate.begin())
        XCTAssertFalse(gate.begin())

        gate.end()
        XCTAssertTrue(gate.begin())
    }
}
