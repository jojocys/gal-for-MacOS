import Foundation

enum GameEngine: String, Codable, CaseIterable {
    case kirikiri = "KiriKiri/XP3"
    case renpy = "Ren'Py"
    case unity = "Unity"
    case unknown = "未知"
}

struct EXECandidate: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var path: String
    var score: Int
    var reason: String

    var fileName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

struct GameScanResult: Codable {
    var folderPath: String
    var engine: GameEngine
    var recommendedEXEPath: String?
    var candidates: [EXECandidate]
    var notes: [String]
    var xp3Count: Int
}

struct SavedGameProfile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var folderPath: String
    var exePath: String
    var prefixPath: String
    var engine: GameEngine
    var notes: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var folderURL: URL { URL(fileURLWithPath: folderPath) }
    var exeURL: URL { URL(fileURLWithPath: exePath) }
    var prefixURL: URL { URL(fileURLWithPath: prefixPath) }
    var displaySubtitle: String {
        let exe = exeURL.lastPathComponent
        if exe.isEmpty { return folderURL.lastPathComponent }
        return exe
    }
}

enum ComponentState: String, Codable {
    case ready
    case missing
    case warning
    case blocked
    case unknown

    var title: String {
        switch self {
        case .ready: return "就绪"
        case .missing: return "缺失"
        case .warning: return "建议处理"
        case .blocked: return "被拦截"
        case .unknown: return "未知"
        }
    }
}

struct RuntimeComponentStatus: Codable {
    var title: String
    var state: ComponentState
    var summary: String
    var detail: String
}

struct RuntimeEnvironmentReport: Codable {
    var checkedAt: Date
    var cpuDescription: String
    var wineBinaryPath: String?
    var wineAppPath: String?
    var xQuartzPath: String?
    var components: [RuntimeComponentStatus]

    static var empty: RuntimeEnvironmentReport {
        .init(
            checkedAt: Date(),
            cpuDescription: "未检测",
            wineBinaryPath: nil,
            wineAppPath: nil,
            xQuartzPath: nil,
            components: []
        )
    }
}

struct AppStoreFile: Codable {
    var selectedGameID: UUID?
    var games: [SavedGameProfile]
    var userWineBinaryPath: String?
    var userWineAppPath: String?
    var lastGameFolderPath: String?
}

enum WizardStep: String, CaseIterable {
    case p1 = "P1 选择游戏"
    case p2 = "P2 运行环境"
    case p3 = "P3 启动与导出"
}

