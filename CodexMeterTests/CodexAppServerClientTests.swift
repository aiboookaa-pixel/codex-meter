import Foundation
import XCTest
@testable import CodexMeter

final class CodexAppServerClientTests: XCTestCase {
    func testBundleDiscoveryFindsExecutableAfterUnknownDirectoryChange() throws {
        let script = try makeExecutableScript("#!/bin/sh\nexit 0\n")
        let app = script.deletingLastPathComponent().appendingPathComponent("Client.app")
        let nested = app.appendingPathComponent("Contents/Resources/new-layout/bin/codex")
        try FileManager.default.createDirectory(at: nested.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: script, to: nested)
        XCTAssertEqual(CodexAppServerClient.executable(in: app)?.resolvingSymlinksInPath(), nested.resolvingSymlinksInPath())
        XCTAssertNil(CodexAppServerClient.executable(in: app.appendingPathComponent("Missing.app")))
    }

    func testSelectedClientBookmarkRestoresWithoutChangingGlobalSettings() throws {
        let script = try makeExecutableScript("#!/bin/sh\nexit 0\n")
        let name = "CodexMeterBookmarkTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let data = try script.deletingLastPathComponent().bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: "codexMeter.clientApplicationBookmark")
        let restored = try XCTUnwrap(CodexAppServerClient.selectedApplication(defaults: defaults))
        XCTAssertEqual(restored.standardizedFileURL.path, script.deletingLastPathComponent().standardizedFileURL.path)
        defaults.set(Data([0, 1, 2]), forKey: "codexMeter.clientApplicationBookmark")
        XCTAssertNil(CodexAppServerClient.selectedApplication(defaults: defaults))
    }

    func testDiscoverySkipsMissingOldLocationAndFindsNestedExecutable() throws {
        let executable = try makeExecutableScript("#!/bin/sh\nexit 0\n")
        XCTAssertEqual(CodexAppServerClient.findExecutable(candidatePaths: [
            executable.deletingLastPathComponent().appendingPathComponent("missing-old-codex").path,
            executable.path
        ]), executable)
        XCTAssertNil(CodexAppServerClient.findExecutable(candidatePaths: ["/missing-codex"]))
    }

    func testSilentServerRequestTimesOutInsteadOfWaitingForever() async throws {
        let executable = try makeExecutableScript(
            """
            #!/bin/sh
            while IFS= read -r line; do
              :
            done
            """
        )
        let client = CodexAppServerClient(executableURL: executable, requestTimeout: 0.1)

        do {
            _ = try await client.readRateLimits()
            XCTFail("Expected the silent App Server to time out")
        } catch let error as CodexAppServerClientError {
            guard case .requestTimedOut = error else {
                return XCTFail("Expected requestTimedOut, received \(error)")
            }
        }
    }

    func testTransportErrorsRequireFreshAppServerConnection() {
        XCTAssertTrue(CodexAppServerClientError.requestTimedOut.shouldInvalidateConnection)
        XCTAssertTrue(CodexAppServerClientError.serverUnavailable("closed").shouldInvalidateConnection)
        XCTAssertFalse(CodexAppServerClientError.malformedResponse.shouldInvalidateConnection)
        XCTAssertFalse(CodexAppServerClientError.executableNotFound.shouldInvalidateConnection)
    }

    private func makeExecutableScript(_ contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexMeterClientTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("fake-codex")
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return script
    }
}
