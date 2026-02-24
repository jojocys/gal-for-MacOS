import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var games: [SavedGameProfile] = []
    @Published var selectedGameID: UUID?
    @Published var selectedWizardStep: WizardStep = .p1
    @Published var runtimeReport: RuntimeEnvironmentReport = .empty
    @Published var statusMessage: String = "欢迎使用：先在 P1 选择游戏文件夹。"
    @Published var lastLogPath: String = ""

    @Published var lastChosenGameFolderPath: String = ""
    @Published var scanResult: GameScanResult?
    @Published var customEXEPath: String = ""
    @Published var showAdvanced: Bool = false

    @Published var userWineBinaryPath: String = ""
    @Published var userWineAppPath: String = ""
    @Published var runtimeInstallBusy: Bool = false
    @Published var runtimeInstallMessage: String = ""
    @Published var lastDownloadedInstallerPath: String = ""

    private let fm: FileManager
    let rootDir: URL
    let storeFileURL: URL
    let logsDir: URL
    let prefixesDir: URL
    let exportsDir: URL
    let downloadsDir: URL

    init() {
        let fm = FileManager.default
        self.fm = fm
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".vnlauncher-zero", isDirectory: true)
        rootDir = root
        storeFileURL = root.appendingPathComponent("store.json")
        logsDir = root.appendingPathComponent("logs", isDirectory: true)
        prefixesDir = root.appendingPathComponent("prefixes", isDirectory: true)
        exportsDir = root.appendingPathComponent("exports", isDirectory: true)
        downloadsDir = root.appendingPathComponent("downloads", isDirectory: true)

        ensureDirectories()
        load()
        refreshRuntime()
    }

    var selectedGameIndex: Int? {
        guard let selectedGameID else { return nil }
        return games.firstIndex(where: { $0.id == selectedGameID })
    }

    var selectedGame: SavedGameProfile? {
        guard let idx = selectedGameIndex else { return nil }
        return games[idx]
    }

    var recommendedOrChosenEXEPath: String? {
        let path = customEXEPath.isEmpty ? scanResult?.recommendedEXEPath : customEXEPath
        guard let path, !path.isEmpty else { return nil }
        return path
    }

    func ensureDirectories() {
        try? fm.createDirectory(at: rootDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: logsDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: prefixesDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: exportsDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
    }

    func load() {
        guard fm.fileExists(atPath: storeFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: storeFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let saved = try decoder.decode(AppStoreFile.self, from: data)
            games = saved.games.sorted { $0.updatedAt > $1.updatedAt }
            selectedGameID = saved.selectedGameID ?? games.first?.id
            userWineBinaryPath = saved.userWineBinaryPath ?? ""
            userWineAppPath = saved.userWineAppPath ?? ""
            lastChosenGameFolderPath = saved.lastGameFolderPath ?? ""
        } catch {
            statusMessage = "读取配置失败：\(error.localizedDescription)"
        }
    }

    func save() {
        do {
            let payload = AppStoreFile(
                selectedGameID: selectedGameID,
                games: games,
                userWineBinaryPath: userWineBinaryPath.isEmpty ? nil : userWineBinaryPath,
                userWineAppPath: userWineAppPath.isEmpty ? nil : userWineAppPath,
                lastGameFolderPath: lastChosenGameFolderPath.isEmpty ? nil : lastChosenGameFolderPath
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(payload)
            try data.write(to: storeFileURL, options: .atomic)
        } catch {
            statusMessage = "保存配置失败：\(error.localizedDescription)"
        }
    }

    func refreshRuntime() {
        runtimeReport = RuntimeManager.detect(
            userWineBinaryPath: userWineBinaryPath.isEmpty ? nil : userWineBinaryPath,
            userWineAppPath: userWineAppPath.isEmpty ? nil : userWineAppPath
        )
    }

    func downloadAndOpenWineInstaller() async {
        await downloadAndOpenInstaller(.wine)
    }

    func downloadAndOpenXQuartzInstaller() async {
        await downloadAndOpenInstaller(.xquartz)
    }

    func chooseAndScanGameFolder() {
        let url = PlatformDialogs.chooseGameFolder(startingAt: lastChosenGameFolderPath.isEmpty ? nil : lastChosenGameFolderPath)
        guard let url else { return }
        scanGameFolder(url)
    }

    func scanGameFolder(_ folderURL: URL) {
        lastChosenGameFolderPath = folderURL.path
        let result = GameScanner.scan(folderURL: folderURL)
        scanResult = result
        customEXEPath = ""
        selectedWizardStep = .p1
        statusMessage = result.recommendedEXEPath == nil ? "未找到可启动 EXE，请手动选择。" : "已完成扫描，确认推荐主程序后保存。"
        save()
    }

    func manuallyChooseEXEForScannedFolder() {
        let start = scanResult?.folderPath ?? lastChosenGameFolderPath
        guard let url = PlatformDialogs.chooseExecutable(startingAt: start.isEmpty ? nil : start) else { return }
        customEXEPath = url.path
        statusMessage = "已手动选择 EXE：\(url.lastPathComponent)"
    }

    func saveScannedGameProfile() {
        guard let scanResult, let exePath = recommendedOrChosenEXEPath else {
            statusMessage = "请先在 P1 选择游戏文件夹并确认 EXE。"
            return
        }

        let folderURL = URL(fileURLWithPath: scanResult.folderPath)
        let defaultName = folderURL.lastPathComponent
        let profileName = defaultName.isEmpty ? "新游戏" : defaultName
        let prefixPath = prefixesDir.appendingPathComponent(slug(for: profileName), isDirectory: true).path
        try? fm.createDirectory(atPath: prefixPath, withIntermediateDirectories: true, attributes: nil)

        if let idx = games.firstIndex(where: { $0.folderPath == scanResult.folderPath }) {
            games[idx].name = profileName
            games[idx].exePath = exePath
            games[idx].engine = scanResult.engine
            games[idx].prefixPath = prefixPath
            games[idx].updatedAt = Date()
            selectedGameID = games[idx].id
            statusMessage = "已更新游戏配置：\(profileName)"
        } else {
            let profile = SavedGameProfile(
                name: profileName,
                folderPath: scanResult.folderPath,
                exePath: exePath,
                prefixPath: prefixPath,
                engine: scanResult.engine,
                notes: scanResult.notes.joined(separator: "\n")
            )
            games.insert(profile, at: 0)
            selectedGameID = profile.id
            statusMessage = "已添加游戏：\(profileName)"
        }

        selectedWizardStep = .p2
        save()
    }

    func selectGame(_ id: UUID?) {
        selectedGameID = id
        if let profile = selectedGame {
            scanResult = GameScanResult(
                folderPath: profile.folderPath,
                engine: profile.engine,
                recommendedEXEPath: profile.exePath,
                candidates: [EXECandidate(path: profile.exePath, score: 0, reason: "已保存主程序")],
                notes: profile.notes.isEmpty ? [] : profile.notes.components(separatedBy: "\n"),
                xp3Count: 0
            )
            customEXEPath = profile.exePath
        }
        save()
    }

    func removeSelectedGame() {
        guard let idx = selectedGameIndex else { return }
        let removed = games.remove(at: idx)
        selectedGameID = games.first?.id
        statusMessage = "已删除配置：\(removed.name)"
        save()
    }

    func chooseWineBinary() {
        guard let url = PlatformDialogs.chooseWineBinary(startingAt: userWineBinaryPath.isEmpty ? nil : userWineBinaryPath) else { return }
        userWineBinaryPath = url.path
        refreshRuntime()
        statusMessage = "已设置 Wine 可执行文件路径。"
        save()
    }

    func chooseWineApp() {
        guard let url = PlatformDialogs.chooseAppBundle(startingAt: userWineAppPath.isEmpty ? "/Applications" : userWineAppPath) else { return }
        userWineAppPath = url.path
        if userWineBinaryPath.isEmpty, let resolved = RuntimeManager.resolveWineBinaryPath(inWineApp: url.path) {
            userWineBinaryPath = resolved
        }
        refreshRuntime()
        statusMessage = "已选择 Wine.app。"
        save()
    }

    func chooseCustomPrefixForSelectedGame() {
        guard let selectedGame else {
            statusMessage = "请先保存一个游戏配置。"
            return
        }
        let folder = PlatformDialogs.chooseFolder(
            title: "选择 Prefix",
            message: "请选择这个游戏的 Wine Prefix 文件夹（建议独立目录）",
            startingAt: selectedGame.prefixPath
        )
        guard let folder else { return }
        updateSelectedGame(prefixPath: folder.path)
        statusMessage = "已更新 Prefix 文件夹。"
    }

    func chooseCustomEXEForSelectedGame() {
        guard let selectedGame else {
            statusMessage = "请先保存一个游戏配置。"
            return
        }
        guard let exeURL = PlatformDialogs.chooseExecutable(startingAt: selectedGame.folderPath) else { return }
        updateSelectedGame(exePath: exeURL.path)
        statusMessage = "已更新主程序：\(exeURL.lastPathComponent)"
    }

    func updateSelectedGame(name: String? = nil, exePath: String? = nil, prefixPath: String? = nil, notes: String? = nil) {
        guard let idx = selectedGameIndex else { return }
        if let name { games[idx].name = name }
        if let exePath { games[idx].exePath = exePath }
        if let prefixPath { games[idx].prefixPath = prefixPath }
        if let notes { games[idx].notes = notes }
        games[idx].updatedAt = Date()
        save()
    }

    func startCurrentGame() {
        guard let profile = selectedGame else {
            statusMessage = "请先在 P1 添加并保存一个游戏配置。"
            return
        }
        refreshRuntime()

        do {
            let logURL = try GameLauncher.launch(
                profile: profile,
                runtimeReport: runtimeReport,
                userWineBinaryPath: userWineBinaryPath.isEmpty ? nil : userWineBinaryPath,
                userWineAppPath: userWineAppPath.isEmpty ? nil : userWineAppPath,
                logsDir: logsDir
            )
            lastLogPath = logURL.path
            selectedWizardStep = .p3
            statusMessage = "已尝试启动：\(profile.name)。如果未成功，请点“打开日志”。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func autoFixGuidance() {
        refreshRuntime()
        if runtimeReport.wineBinaryPath == nil {
            selectedWizardStep = .p2
            statusMessage = "请先在 P2 完成 Wine 安装或选择 Wine.app。"
            return
        }
        if runtimeReport.components.contains(where: { $0.title.contains("Gatekeeper") && $0.state == .blocked }) {
            RuntimeManager.openPrivacySecuritySettings()
            statusMessage = "已打开“隐私与安全性”，请允许 Wine 后再回来启动。"
            return
        }
        statusMessage = "未发现可自动引导的阻塞项，可直接尝试启动。"
    }

    func openLastLog() {
        guard !lastLogPath.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: lastLogPath))
    }

    func openLastDownloadedInstaller() {
        guard !lastDownloadedInstallerPath.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: lastDownloadedInstallerPath))
    }

    func revealSelectedGameFolder() {
        guard let profile = selectedGame else { return }
        NSWorkspace.shared.activateFileViewerSelecting([profile.folderURL])
    }

    private func slug(for text: String) -> String {
        let chars = text.lowercased().map { ch -> Character in
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" || ch == "." { return ch }
            return "_"
        }
        let value = String(chars).trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
        return value.isEmpty ? UUID().uuidString.lowercased() : value
    }

    private func downloadAndOpenInstaller(_ target: RuntimeInstallTarget) async {
        if runtimeInstallBusy { return }
        runtimeInstallBusy = true
        selectedWizardStep = .p2
        let label = target == .wine ? "Wine" : "XQuartz"
        runtimeInstallMessage = "正在获取 \(label) 最新安装包信息..."

        defer { runtimeInstallBusy = false }

        do {
            let arch = currentArchitecture()
            let fileURL = try await RuntimeInstaller.downloadLatestInstaller(
                target,
                destinationDir: downloadsDir,
                preferredArchitecture: arch
            )
            lastDownloadedInstallerPath = fileURL.path
            runtimeInstallMessage = "\(label) 安装包已下载：\(fileURL.lastPathComponent)，正在打开..."
            RuntimeInstaller.openInstaller(fileURL)
            statusMessage = "已下载并打开 \(label) 安装包。安装完成后回到 P2 点击“重新检测”。"
        } catch {
            runtimeInstallMessage = error.localizedDescription
            statusMessage = error.localizedDescription
        }
    }

    private func currentArchitecture() -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/uname")
        process.arguments = ["-m"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
    }
}
