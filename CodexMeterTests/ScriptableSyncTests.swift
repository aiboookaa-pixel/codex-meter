import XCTest
@testable import CodexMeter

@MainActor
final class ScriptableSyncTests: XCTestCase {
    private func makeSnapshot(weekly: UsageWindow? = nil) -> UsageSnapshot {
        UsageSnapshot(
            fiveHours: UsageWindow(
                usedPercent: 28,
                durationMinutes: 300,
                resetsAt: Date(timeIntervalSince1970: 1_789_310_160)
            ),
            weekly: weekly,
            unknownWindows: [],
            fullResetAvailableCount: nil,
            lastSuccessfulSync: Date(timeIntervalSince1970: 1_789_304_292),
            isCached: false
        )
    }

    func testContractRoundTripsWithSchemaOneAndISO8601Dates() throws {
        let payload = ScriptableUsageSnapshot(
            snapshot: makeSnapshot(weekly: UsageWindow(
                usedPercent: 19,
                durationMinutes: 10_080,
                resetsAt: Date(timeIntervalSince1970: 1_789_600_800)
            )),
            sourceStatus: .connected,
            exportedAt: Date(timeIntervalSince1970: 1_789_304_293)
        )

        let data = try ScriptableJSONCoding.encoder().encode(payload)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertTrue(try XCTUnwrap((object["fiveHour"] as? [String: Any])?["resetAt"] as? String).contains("T"))
        XCTAssertEqual(try ScriptableJSONCoding.decoder().decode(ScriptableUsageSnapshot.self, from: data), payload)
    }

    func testMissingWindowEncodesAsNullInsteadOfZero() throws {
        let payload = ScriptableUsageSnapshot(snapshot: makeSnapshot(), sourceStatus: .connected)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: ScriptableJSONCoding.encoder().encode(payload)
        ) as? [String: Any])

        XCTAssertTrue(object["weekly"] is NSNull)
        XCTAssertEqual((object["fiveHour"] as? [String: Any])?["remainingPercent"] as? Int, 72)
    }

    func testMissingResetDateEncodesAsNull() throws {
        let snapshot = UsageSnapshot(
            fiveHours: UsageWindow(usedPercent: 28, durationMinutes: 300, resetsAt: nil),
            weekly: nil,
            unknownWindows: [],
            fullResetAvailableCount: nil,
            lastSuccessfulSync: Date(timeIntervalSince1970: 1_789_304_292),
            isCached: false
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: ScriptableJSONCoding.encoder().encode(
                ScriptableUsageSnapshot(snapshot: snapshot, sourceStatus: .connected)
            )
        ) as? [String: Any])
        XCTAssertTrue((object["fiveHour"] as? [String: Any])?["resetAt"] is NSNull)
    }

    func testExportDecisionSkipsIdenticalSnapshotButDetectsDataAndStatusChanges() {
        let snapshot = makeSnapshot()
        let connected = ScriptableExportFingerprint(snapshot: snapshot, sourceStatus: .connected)
        let same = ScriptableExportFingerprint(snapshot: snapshot, sourceStatus: .connected)
        let offline = ScriptableExportFingerprint(snapshot: snapshot, sourceStatus: .offline)
        let changed = ScriptableExportFingerprint(
            snapshot: UsageSnapshot(
                fiveHours: UsageWindow(usedPercent: 29, durationMinutes: 300, resetsAt: snapshot.fiveHours?.resetsAt),
                weekly: nil,
                unknownWindows: [],
                fullResetAvailableCount: nil,
                lastSuccessfulSync: snapshot.lastSuccessfulSync,
                isCached: false
            ),
            sourceStatus: .connected
        )

        XCTAssertFalse(ScriptableExportDecision.shouldExport(previous: connected, current: same, force: false))
        XCTAssertTrue(ScriptableExportDecision.shouldExport(previous: connected, current: changed, force: false))
        XCTAssertTrue(ScriptableExportDecision.shouldExport(previous: connected, current: offline, force: false))
        XCTAssertTrue(ScriptableExportDecision.shouldExport(previous: connected, current: same, force: true))
    }

    func testWriterCreatesValidatedContractAndReplacesPreviousSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = ScriptableUsageSnapshot(snapshot: makeSnapshot(), sourceStatus: .connected)
        let firstURL = try ScriptableSnapshotWriter.write(first, toRoot: root)
        XCTAssertEqual(firstURL.lastPathComponent, "usage.json")

        let second = ScriptableUsageSnapshot(snapshot: makeSnapshot(), sourceStatus: .offline)
        let secondURL = try ScriptableSnapshotWriter.write(second, toRoot: root)
        let decoded = try ScriptableJSONCoding.decoder().decode(
            ScriptableUsageSnapshot.self,
            from: Data(contentsOf: secondURL)
        )
        XCTAssertEqual(decoded.sourceStatus, "offline")
    }

    func testWriterReportsInvalidSelectedDirectoryWithoutCreatingUsageJSON() throws {
        let rootFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("not a directory".utf8).write(to: rootFile)
        defer { try? FileManager.default.removeItem(at: rootFile) }

        XCTAssertThrowsError(try ScriptableSnapshotWriter.write(
            ScriptableUsageSnapshot(snapshot: makeSnapshot(), sourceStatus: .connected),
            toRoot: rootFile
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: rootFile.appendingPathComponent("CodexMeter/usage.json").path))
    }

    func testFailedAtomicReplacementPreservesPreviousUsageJSON() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let connected = ScriptableUsageSnapshot(snapshot: makeSnapshot(), sourceStatus: .connected)
        let destination = try ScriptableSnapshotWriter.write(connected, toRoot: root)

        XCTAssertThrowsError(try ScriptableSnapshotWriter.write(
            ScriptableUsageSnapshot(snapshot: makeSnapshot(), sourceStatus: .offline),
            toRoot: root,
            replaceExisting: { _, _ in throw CocoaError(.fileWriteUnknown) }
        ))
        let preserved = try ScriptableJSONCoding.decoder().decode(
            ScriptableUsageSnapshot.self,
            from: Data(contentsOf: destination)
        )
        XCTAssertEqual(preserved.sourceStatus, "connected")
    }

    func testServiceSkipsDisabledAndUnconfiguredExports() {
        let suiteName = "ScriptableSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = ScriptableSyncService(defaults: defaults)

        XCTAssertEqual(service.exportIfNeeded(snapshot: makeSnapshot(), sourceStatus: .connected), .skippedDisabled)
        service.setEnabled(true)
        XCTAssertEqual(service.exportIfNeeded(snapshot: makeSnapshot(), sourceStatus: .connected), .skippedUnconfigured)
        XCTAssertEqual(service.status, .unconfigured)
    }

    func testServiceRestoresBookmarkAfterRestartAndCanWriteAgain() throws {
        let suiteName = "ScriptableSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let first = ScriptableSyncService(defaults: defaults)
        try first.configureDirectory(root)
        first.setEnabled(true)
        guard case .exported = first.exportIfNeeded(snapshot: makeSnapshot(), sourceStatus: .connected) else {
            return XCTFail("Expected first export")
        }

        let restored = ScriptableSyncService(defaults: defaults)
        XCTAssertTrue(restored.isEnabled)
        XCTAssertEqual(restored.selectedDirectoryURL?.standardizedFileURL, root.standardizedFileURL)
        guard case .exported = restored.exportIfNeeded(snapshot: makeSnapshot(), sourceStatus: .connected, force: true) else {
            return XCTFail("Expected export after bookmark restoration")
        }
        XCTAssertNotNil(restored.lastSuccessfulExport)
    }

    func testServiceContainsExportErrorAndPreservesCoreCaller() throws {
        let suiteName = "ScriptableSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let service = ScriptableSyncService(defaults: defaults)
        try service.configureDirectory(root)
        service.setEnabled(true)
        try FileManager.default.removeItem(at: root)
        try Data("now a file".utf8).write(to: root)

        guard case .failed = service.exportIfNeeded(snapshot: makeSnapshot(), sourceStatus: .offline) else {
            return XCTFail("Expected contained export failure")
        }
        guard case .failed = service.status else {
            return XCTFail("Expected published failure status")
        }
        XCTAssertNil(service.lastSuccessfulExport)
    }

    func testServiceExportsSourceStatusTransitionsAndSkipsUnchangedPolls() throws {
        let suiteName = "ScriptableSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let service = ScriptableSyncService(defaults: defaults)
        try service.configureDirectory(root)
        service.setEnabled(true)
        guard case .exported = service.exportIfNeeded(snapshot: makeSnapshot(), sourceStatus: .connected) else {
            return XCTFail("Expected connected export")
        }
        XCTAssertEqual(service.exportIfNeeded(snapshot: makeSnapshot(), sourceStatus: .connected), .skippedUnchanged)
        guard case .exported = service.exportIfNeeded(snapshot: makeSnapshot(), sourceStatus: .offline) else {
            return XCTFail("Expected offline transition export")
        }
        guard case .exported = service.exportIfNeeded(snapshot: makeSnapshot(), sourceStatus: .connected) else {
            return XCTFail("Expected recovery transition export")
        }
        guard case .exported = service.exportIfNeeded(snapshot: makeSnapshot(), sourceStatus: .connected, force: true) else {
            return XCTFail("Expected forced manual export")
        }
        service.setEnabled(false)
        XCTAssertEqual(service.exportIfNeeded(snapshot: makeSnapshot(), sourceStatus: .offline), .skippedDisabled)
    }
}
