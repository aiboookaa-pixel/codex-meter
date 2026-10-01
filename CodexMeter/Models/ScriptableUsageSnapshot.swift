import Foundation

struct ScriptableUsageWindow: Codable, Equatable {
    let usedPercent: Int
    let remainingPercent: Int
    let resetAt: Date?

    init(_ window: UsageWindow) {
        usedPercent = window.usedPercent
        remainingPercent = window.remainingPercent
        resetAt = window.resetsAt
    }

    private enum CodingKeys: String, CodingKey {
        case usedPercent
        case remainingPercent
        case resetAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(usedPercent, forKey: .usedPercent)
        try container.encode(remainingPercent, forKey: .remainingPercent)
        if let resetAt {
            try container.encode(resetAt, forKey: .resetAt)
        } else {
            try container.encodeNil(forKey: .resetAt)
        }
    }
}

struct ScriptableUsageSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let fiveHour: ScriptableUsageWindow?
    let weekly: ScriptableUsageWindow?
    let sourceLastSuccessfulSync: Date
    let exportedAt: Date
    let sourceStatus: String

    init(snapshot: UsageSnapshot, sourceStatus: ConnectionStatus, exportedAt: Date = .now) {
        schemaVersion = 1
        fiveHour = snapshot.fiveHours.map(ScriptableUsageWindow.init)
        weekly = snapshot.weekly.map(ScriptableUsageWindow.init)
        sourceLastSuccessfulSync = snapshot.lastSuccessfulSync
        self.exportedAt = exportedAt
        self.sourceStatus = sourceStatus.scriptableValue
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case fiveHour
        case weekly
        case sourceLastSuccessfulSync
        case exportedAt
        case sourceStatus
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        if let fiveHour {
            try container.encode(fiveHour, forKey: .fiveHour)
        } else {
            try container.encodeNil(forKey: .fiveHour)
        }
        if let weekly {
            try container.encode(weekly, forKey: .weekly)
        } else {
            try container.encodeNil(forKey: .weekly)
        }
        try container.encode(sourceLastSuccessfulSync, forKey: .sourceLastSuccessfulSync)
        try container.encode(exportedAt, forKey: .exportedAt)
        try container.encode(sourceStatus, forKey: .sourceStatus)
    }
}

enum ScriptableJSONCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

struct ScriptableExportFingerprint: Equatable {
    let fiveHour: ScriptableUsageWindow?
    let weekly: ScriptableUsageWindow?
    let sourceStatus: String
    let sourceLastSuccessfulSync: Date

    init(snapshot: UsageSnapshot, sourceStatus: ConnectionStatus) {
        fiveHour = snapshot.fiveHours.map(ScriptableUsageWindow.init)
        weekly = snapshot.weekly.map(ScriptableUsageWindow.init)
        self.sourceStatus = sourceStatus.scriptableValue
        sourceLastSuccessfulSync = snapshot.lastSuccessfulSync
    }
}

enum ScriptableExportDecision {
    static func shouldExport(
        previous: ScriptableExportFingerprint?,
        current: ScriptableExportFingerprint,
        force: Bool
    ) -> Bool {
        force || previous != current
    }
}
