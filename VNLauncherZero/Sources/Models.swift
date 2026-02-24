import Foundation

struct GameEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var gameFolderPath: String
    var exePath: String
    var prefixDir: String
    var engineHint: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        gameFolderPath: String = "",
        exePath: String = "",
        prefixDir: String = "",
        engineHint: String = "未识别",
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.gameFolderPath = gameFolderPath
        self.exePath = exePath
        self.prefixDir = prefixDir
        self.engineHint = engineHint
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var folderURL: URL? {
        guard !gameFolderPath.isEmpty else { return nil }
        return URL(fileURLWithPath: gameFolderPath)
    }

    var exeURL: URL? {
        guard !exePath.isEmpty else { return nil }
        return URL(fileURLWithPath: exePath)
    }

    var prefixURL: URL? {
        guard !prefixDir.isEmpty else { return nil }
        return URL(fileURLWithPath: prefixDir)
    }

    var displaySubtitle: String {
        if let exeURL { return exeURL.lastPathComponent }
        if let folderURL { return folderURL.lastPathComponent }
        return "未配置"
    }
}

struct GameStoreFile: Codable {
    var selectedGameID: UUID?
    var games: [GameEntry]
    var preferredWineBinaryPath: String
    var preferredWineAppPath: String
}

struct ScanCandidate: Identifiable, Hashable {
    let id = UUID()
    let exeURL: URL
    let score: Int
    let reason: String
}

struct ScanResult {
    let folderURL: URL
    let engineHint: String
    let xp3Count: Int
    let exeCandidates: [ScanCandidate]

    var recommendedEXE: URL? { exeCandidates.first?.exeURL }
}

struct RuntimeCheckItem: Identifiable {
    enum State {
        case ok
        case warning
        case missing
        case blocked

        var label: String {
            switch self {
            case .ok: return "就绪"
            case .warning: return "需注意"
            case .missing: return "未安装"
            case .blocked: return "被拦截"
            }
        }
    }

    let id = UUID()
    let title: String
    let detail: String
    let state: State
}

struct RuntimeCheckReport {
    var items: [RuntimeCheckItem]
    var resolvedWineBinaryPath: String
    var detectedWineAppPath: String
    var rosettaInstalled: Bool
    var xquartzInstalled: Bool
    var gatekeeperBlocked: Bool
}

struct InstallerDownloadResult {
    let downloadedFileURL: URL
    let sourceURL: URL
}
