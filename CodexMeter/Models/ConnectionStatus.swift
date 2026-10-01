import Foundation

enum ConnectionStatus: Equatable {
    case connected
    case refreshing
    case offline
    case cached
    case codexNotFound
    case appServerUnavailable
    case dataUnavailable
    case error(String)

    var localizedDescription: String {
        switch self {
        case .connected: return "Codex 已连接"
        case .refreshing: return "正在刷新"
        case .offline: return "Codex 离线"
        case .cached: return "正在显示缓存"
        case .codexNotFound: return "未找到 Codex"
        case .appServerUnavailable: return "App Server 不可用"
        case .dataUnavailable: return "当前额度不可用"
        case .error: return "连接出现问题"
        }
    }

    var isPositive: Bool { self == .connected }

    var scriptableValue: String {
        switch self {
        case .connected: return "connected"
        case .refreshing: return "refreshing"
        case .offline: return "offline"
        case .cached: return "cached"
        case .codexNotFound: return "codexNotFound"
        case .appServerUnavailable: return "appServerUnavailable"
        case .dataUnavailable: return "dataUnavailable"
        case .error: return "error"
        }
    }
}
