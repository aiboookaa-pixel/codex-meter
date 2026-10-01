import Foundation
import AppKit

enum CodexAppServerClientError: LocalizedError {
    case executableNotFound
    case serverUnavailable(String)
    case malformedResponse
    case requestTimedOut

    var errorDescription: String? {
        switch self {
        case .executableNotFound: return "未找到 Codex 可执行文件"
        case .serverUnavailable(let message): return message
        case .malformedResponse: return "App Server 返回了无法识别的数据"
        case .requestTimedOut: return "App Server 响应超时"
        }
    }

    var shouldInvalidateConnection: Bool {
        switch self {
        case .serverUnavailable, .requestTimedOut: return true
        case .executableNotFound, .malformedResponse: return false
        }
    }
}

final class CodexAppServerClient {
    private struct PendingRequest {
        let continuation: CheckedContinuation<Data, Error>
        let timeoutWorkItem: DispatchWorkItem
    }

    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errorOutput: FileHandle?
    private var buffer = Data()
    private var nextRequestID = 1
    private var continuations: [Int: PendingRequest] = [:]
    private let lock = NSLock()
    private let executableURL: URL?
    private let requestTimeout: TimeInterval
    var onRateLimitsUpdated: ((RateLimitSnapshot) -> Void)?

    init(executableURL: URL? = nil, requestTimeout: TimeInterval = 15) {
        self.executableURL = executableURL
        self.requestTimeout = requestTimeout
    }

    deinit { stop() }

    static func executable(in application: URL) -> URL? {
        let resources = application.appendingPathComponent("Contents/Resources")
        let known = ["codex-cli/CodexCLI.app/Contents/MacOS/codex", "codex"]
        for path in known {
            let url = resources.appendingPathComponent(path)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        // Search only the selected/official application bundle, never the whole disk.
        if let entries = FileManager.default.enumerator(at: resources, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in entries where url.lastPathComponent == "codex" {
                if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                   FileManager.default.isExecutableFile(atPath: url.path) { return url }
            }
        }
        return nil
    }

    static func selectedApplication(defaults: UserDefaults = .standard) -> URL? {
        guard let data = defaults.data(forKey: "codexMeter.clientApplicationBookmark") else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let refreshed = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(refreshed, forKey: "codexMeter.clientApplicationBookmark")
        }
        return url
    }

    static func findApplication() -> URL? {
        let homeApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        let candidates = [selectedApplication(), NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex"),
                          URL(fileURLWithPath: "/Applications/ChatGPT.app"), URL(fileURLWithPath: "/Applications/Codex.app"),
                          homeApps.appendingPathComponent("ChatGPT.app"), homeApps.appendingPathComponent("Codex.app")].compactMap { $0 }
        return candidates.first { executable(in: $0) != nil }
    }

    static func findExecutable(candidatePaths: [String]? = nil) -> URL? {
        if candidatePaths == nil, let app = findApplication(), let executable = executable(in: app) { return executable }
        let candidates = candidatePaths ?? [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex"
        ]
        return candidates.map(URL.init(fileURLWithPath:)).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    func connect() async throws {
        if process?.isRunning == true { return }
        if process != nil { invalidateConnection() }
        guard let executable = executableURL ?? Self.findExecutable() else { throw CodexAppServerClientError.executableNotFound }
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        let input = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        self.process = process
        self.input = input.fileHandleForWriting
        self.output = output.fileHandleForReading
        self.errorOutput = error.fileHandleForReading
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in self?.consume(handle.availableData) }
        // App Server may emit diagnostics for its entire lifetime. Always drain
        // stderr so the pipe cannot fill up and block protocol responses.
        error.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        process.terminationHandler = { [weak self, weak process] _ in
            guard let self, let process, self.process === process else { return }
            self.clearTransport(terminate: false, error: CodexAppServerClientError.serverUnavailable("App Server 已退出"))
        }
        do { try process.run() } catch {
            clearTransport(terminate: false, error: CodexAppServerClientError.serverUnavailable(error.localizedDescription))
            throw CodexAppServerClientError.serverUnavailable(error.localizedDescription)
        }
        _ = try await request(method: "initialize", params: ["clientInfo": ["name": "codex-meter", "version": "1.0"], "capabilities": ["experimentalApi": false]])
    }

    func readRateLimits() async throws -> AccountRateLimitsResponse {
        try await connect()
        let data = try await request(method: "account/rateLimits/read", params: nil)
        return try JSONDecoder().decode(AccountRateLimitsResponse.self, from: data)
    }

    func stop() {
        clearTransport(terminate: true, error: CodexAppServerClientError.serverUnavailable("App Server 已关闭"))
    }

    func invalidateConnection() {
        stop()
    }

    private func request(method: String, params: [String: Any]?) async throws -> Data {
        let requestID: Int = lock.withLock {
            defer { nextRequestID += 1 }
            return nextRequestID
        }
        var request: [String: Any] = ["id": requestID, "method": method]
        if let params { request["params"] = params }
        let data = try JSONSerialization.data(withJSONObject: request)
        guard let input else { throw CodexAppServerClientError.serverUnavailable("App Server 输入连接不可用") }
        return try await withCheckedThrowingContinuation { continuation in
            let timeoutWorkItem = DispatchWorkItem { [weak self] in self?.timeOutRequest(requestID) }
            lock.withLock {
                continuations[requestID] = PendingRequest(continuation: continuation, timeoutWorkItem: timeoutWorkItem)
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + requestTimeout, execute: timeoutWorkItem)
            do {
                try input.write(contentsOf: data + Data([0x0A]))
            } catch {
                failRequest(requestID, error: CodexAppServerClientError.serverUnavailable(error.localizedDescription))
            }
        }
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.withLock { buffer.append(data) }
        while let line = nextLine() { handle(line) }
    }

    private func nextLine() -> Data? {
        lock.withLock {
            guard let index = buffer.firstIndex(of: 0x0A) else { return nil }
            let line = buffer.prefix(upTo: index)
            buffer.removeSubrange(...index)
            return Data(line)
        }
    }

    private func handle(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let id = object["id"] as? Int {
            let pending = lock.withLock { continuations.removeValue(forKey: id) }
            pending?.timeoutWorkItem.cancel()
            if let error = object["error"] as? [String: Any] {
                pending?.continuation.resume(throwing: CodexAppServerClientError.serverUnavailable(error["message"] as? String ?? "App Server 请求失败"))
            } else if let result = object["result"], let resultData = try? JSONSerialization.data(withJSONObject: result) {
                pending?.continuation.resume(returning: resultData)
            } else {
                pending?.continuation.resume(throwing: CodexAppServerClientError.malformedResponse)
            }
            return
        }
        guard object["method"] as? String == "account/rateLimits/updated",
              let params = object["params"],
              let paramsData = try? JSONSerialization.data(withJSONObject: params),
              let envelope = try? JSONDecoder().decode(RateLimitUpdateEnvelope.self, from: paramsData) else { return }
        onRateLimitsUpdated?(envelope.rateLimits)
    }

    private func failPending(_ error: Error) {
        let waiting = lock.withLock { () -> [PendingRequest] in
            defer { continuations.removeAll() }
            return Array(continuations.values)
        }
        waiting.forEach {
            $0.timeoutWorkItem.cancel()
            $0.continuation.resume(throwing: error)
        }
    }

    private func timeOutRequest(_ requestID: Int) {
        failRequest(requestID, error: CodexAppServerClientError.requestTimedOut)
    }

    private func failRequest(_ requestID: Int, error: Error) {
        let pending = lock.withLock { continuations.removeValue(forKey: requestID) }
        pending?.timeoutWorkItem.cancel()
        pending?.continuation.resume(throwing: error)
    }

    private func clearTransport(terminate: Bool, error: Error) {
        let oldProcess = process
        process = nil
        input = nil
        output?.readabilityHandler = nil
        errorOutput?.readabilityHandler = nil
        output = nil
        errorOutput = nil
        lock.withLock { buffer.removeAll(keepingCapacity: true) }
        oldProcess?.terminationHandler = nil
        if terminate, oldProcess?.isRunning == true { oldProcess?.terminate() }
        failPending(error)
    }
}

private struct RateLimitUpdateEnvelope: Codable {
    let rateLimits: RateLimitSnapshot
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T { lock(); defer { unlock() }; return body() }
}
