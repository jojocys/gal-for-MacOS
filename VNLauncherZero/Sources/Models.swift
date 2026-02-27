import Foundation

enum LaunchLanguageMode: String, Codable, CaseIterable, Identifiable {
    case auto
    case japanese
    case chineseSimplified

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "自动"
        case .japanese: return "日文"
        case .chineseSimplified: return "简中"
        }
    }
}

struct GameEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var gameFolderPath: String
    var exePath: String
    var prefixDir: String
    var engineHint: String
    var launchLanguageMode: LaunchLanguageMode
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
        launchLanguageMode: LaunchLanguageMode = .auto,
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
        self.launchLanguageMode = launchLanguageMode
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case gameFolderPath
        case exePath
        case prefixDir
        case engineHint
        case launchLanguageMode
        case notes
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名游戏"
        gameFolderPath = try container.decodeIfPresent(String.self, forKey: .gameFolderPath) ?? ""
        exePath = try container.decodeIfPresent(String.self, forKey: .exePath) ?? ""
        prefixDir = try container.decodeIfPresent(String.self, forKey: .prefixDir) ?? ""
        engineHint = try container.decodeIfPresent(String.self, forKey: .engineHint) ?? "未识别"
        launchLanguageMode = try container.decodeIfPresent(LaunchLanguageMode.self, forKey: .launchLanguageMode) ?? .auto
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
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
        case bundled
        case warning
        case missing
        case blocked

        var label: String {
            switch self {
            case .ok: return "就绪"
            case .bundled: return "已内置"
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
