import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    private static let steamInstallerURL = URL(string: "https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe")!

    @Published var games: [GameEntry] = []
    @Published var selectedGameID: UUID?
    @Published var statusMessage: String = "欢迎使用：先在 P1 选择游戏文件夹。"
    @Published var lastLogPath: String = ""

    @Published var scanResult: ScanResult?
    @Published var runtimeReport = RuntimeCheckReport(items: [], resolvedWineBinaryPath: "", detectedWineAppPath: "", rosettaInstalled: false, xquartzInstalled: false, gatekeeperBlocked: false)
    @Published var isDownloadingInstaller = false
    @Published var downloadStatusText: String = ""

    private let fm = FileManager.default

    let appDataDir: URL
    let logsDir: URL
    let prefixesDir: URL
    let storeURL: URL

    var preferredWineBinaryPath: String = "" { didSet { save() } }
    var preferredWineAppPath: String = "" { didSet { save() } }

    init() {
        let home = fm.homeDirectoryForCurrentUser
        appDataDir = home.appendingPathComponent(".vnlauncher", isDirectory: true)
        logsDir = appDataDir.appendingPathComponent("logs", isDirectory: true)
        prefixesDir = appDataDir.appendingPathComponent("zero-prefixes", isDirectory: true)
        storeURL = appDataDir.appendingPathComponent("gal-for-macos-games.json")
        ensureDirs()
        load()
        refreshRuntimeStatus()
    }

    var selectedIndex: Int? {
        guard let id = selectedGameID else { return nil }
        return games.firstIndex(where: { $0.id == id })
    }

    var selectedGame: GameEntry? {
        guard let idx = selectedIndex else { return nil }
        return games[idx]
    }

    var wineSteamTips: [String] {
        [
            "“一键关闭”会终止 Wine Steam 与其子进程，正在运行的 Steam 游戏会被强制退出。",
            "入口优先使用专用 Prefix：~/.vnlauncher/steam-prefix（兼容检测 ~/.vnlauncher-zero/steam-prefix）。",
            "如果提示未找到 Windows Steam，请先在该 Prefix 中完成一次安装。"
        ]
    }

    var wineSteamEntryContext: WineSteamEntryContext? {
        resolveWineSteamEntryContext()
    }

    func load() {
        guard fm.fileExists(atPath: storeURL.path) else {
            if games.isEmpty {
                let demo = GameEntry(name: "新游戏", prefixDir: defaultPrefixDir(for: "新游戏"))
                games = [demo]
                selectedGameID = demo.id
            }
            return
        }
        do {
            let data = try Data(contentsOf: storeURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let file = try decoder.decode(GameStoreFile.self, from: data)
            games = file.games.sorted(by: { $0.updatedAt > $1.updatedAt })
            selectedGameID = file.selectedGameID ?? games.first?.id
            preferredWineBinaryPath = file.preferredWineBinaryPath
            preferredWineAppPath = file.preferredWineAppPath
            if games.isEmpty {
                let demo = GameEntry(name: "新游戏", prefixDir: defaultPrefixDir(for: "新游戏"))
                games = [demo]
                selectedGameID = demo.id
            }
            if let game = selectedGame, !game.gameFolderPath.isEmpty {
                scanResult = GameScanner.scanGameFolder(URL(fileURLWithPath: game.gameFolderPath))
            }
        } catch {
            statusMessage = "读取配置失败：\(error.localizedDescription)"
        }
    }

    func save() {
        do {
            ensureDirs()
            let file = GameStoreFile(
                selectedGameID: selectedGameID,
                games: games,
                preferredWineBinaryPath: preferredWineBinaryPath,
                preferredWineAppPath: preferredWineAppPath
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(file)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            statusMessage = "保存配置失败：\(error.localizedDescription)"
        }
    }

    func refreshRuntimeStatus(userInitiated: Bool = false) {
        let report = RuntimeManager.detect(
            preferredWineBinaryPath: preferredWineBinaryPath,
            preferredWineAppPath: preferredWineAppPath
        )
        runtimeReport = report
        if userInitiated {
            let summary: String
            if report.resolvedWineBinaryPath.isEmpty {
                summary = "未检测到 Wine"
            } else {
                summary = "已重新检测运行环境"
            }
            statusMessage = summary
            if !downloadStatusText.isEmpty {
                downloadStatusText = ""
            }
        }
    }

    func selectGame(_ id: UUID?) {
        selectedGameID = id
        if let game = selectedGame, !game.gameFolderPath.isEmpty {
            scanResult = GameScanner.scanGameFolder(URL(fileURLWithPath: game.gameFolderPath))
        } else {
            scanResult = nil
        }
        save()
    }

    func addEmptyGame() {
        let name = nextUntitledName()
        let entry = GameEntry(name: name, prefixDir: defaultPrefixDir(for: name))
        games.insert(entry, at: 0)
        selectedGameID = entry.id
        scanResult = nil
        statusMessage = "已创建空白配置"
        save()
    }

    func removeSelectedGame() {
        guard let idx = selectedIndex else { return }
        let removed = games.remove(at: idx)
        selectedGameID = games.first?.id
        statusMessage = "已删除配置：\(removed.name)"
        if let game = selectedGame, !game.gameFolderPath.isEmpty {
            scanResult = GameScanner.scanGameFolder(URL(fileURLWithPath: game.gameFolderPath))
        } else {
            scanResult = nil
        }
        save()
    }

    func chooseAndScanGameFolder() {
        let start = selectedGame?.gameFolderPath
        guard let folder = PlatformPickers.chooseGameFolder(startingAt: start) else { return }
        applyScanResult(GameScanner.scanGameFolder(folder), persistAsCurrent: true)
    }

    func rescanCurrentFolder() {
        guard let path = selectedGame?.gameFolderPath, !path.isEmpty else {
            statusMessage = "请先选择游戏文件夹"
            return
        }
        applyScanResult(GameScanner.scanGameFolder(URL(fileURLWithPath: path)), persistAsCurrent: true)
    }

    func chooseEXEManually() {
        let start = selectedGame?.exePath
        guard let exe = PlatformPickers.chooseExecutable(startingAt: start) else { return }
        updateSelected { game in
            game.exePath = exe.path
            if game.gameFolderPath.isEmpty { game.gameFolderPath = exe.deletingLastPathComponent().path }
            if game.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || game.name == "新游戏" {
                game.name = exe.deletingPathExtension().lastPathComponent
            }
            if game.prefixDir.isEmpty { game.prefixDir = defaultPrefixDir(for: game.name) }
        }
        statusMessage = "已手动选择 EXE：\(exe.lastPathComponent)"
        if let folder = selectedGame?.gameFolderPath, !folder.isEmpty {
            scanResult = GameScanner.scanGameFolder(URL(fileURLWithPath: folder))
        }
    }

    func choosePrefixFolder() {
        let start = selectedGame?.prefixDir
        guard let folder = PlatformPickers.chooseFolder(startingAt: start, prompt: "选择 Prefix", message: "建议为每个游戏使用独立 Prefix 文件夹") else { return }
        updateSelected { $0.prefixDir = folder.path }
        statusMessage = "已设置 Prefix：\(folder.lastPathComponent)"
    }

    func renameSelectedGame(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updateSelected { game in
            game.name = trimmed.isEmpty ? "未命名游戏" : trimmed
        }
    }

    func setSelectedLaunchLanguage(_ mode: LaunchLanguageMode) {
        updateSelected { game in
            game.launchLanguageMode = mode
        }
    }

    func chooseWineBinary() {
        let start = preferredWineBinaryPath
        guard let file = PlatformPickers.chooseWineBinary(startingAt: start) else { return }
        preferredWineBinaryPath = file.path
        statusMessage = "已设置 Wine 路径（优先使用）"
        refreshRuntimeStatus()
    }

    func chooseWineApp() {
        let start = preferredWineAppPath
        guard let app = PlatformPickers.chooseApp(startingAt: start, prompt: "选择 Wine.app", message: "请选择 Wine Stable.app 或 Wine.app") else { return }
        preferredWineAppPath = app.path
        statusMessage = "已记录 Wine.app 路径"
        refreshRuntimeStatus()
    }

    func openSelectedGameFolder() {
        guard let path = selectedGame?.gameFolderPath, !path.isEmpty else {
            statusMessage = "当前配置还没有游戏文件夹"
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func launchWineSteamEntry() {
        refreshRuntimeStatus()
        let wineBinary = runtimeReport.resolvedWineBinaryPath.isEmpty
            ? (RuntimeManager.resolveWineBinary(preferred: preferredWineBinaryPath) ?? "")
            : runtimeReport.resolvedWineBinaryPath

        guard !wineBinary.isEmpty else {
            statusMessage = "未检测到 Wine。请先在 P2 选择/安装 Wine。"
            return
        }

        guard let context = resolveWineSteamEntryContext() else {
            if launchSteamInstallerIfAvailable(wineBinary: wineBinary) {
                return
            }
            statusMessage = "未找到 Windows Steam（Steam.exe）。请先安装 Wine 版 Steam。"
            return
        }

        do {
            try fm.createDirectory(atPath: context.prefixPath, withIntermediateDirectories: true, attributes: nil)
        } catch {
            statusMessage = "无法创建/访问 Steam Prefix：\(error.localizedDescription)"
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: wineBinary)
        process.arguments = [context.steamExePath, "-no-cef-sandbox", "-foreground"]
        process.currentDirectoryURL = URL(fileURLWithPath: context.steamExePath).deletingLastPathComponent()
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = context.prefixPath
        process.environment = env

        do {
            try process.run()
            statusMessage = "已启动 Wine Steam（\(context.sourceLabel)）。"
        } catch {
            statusMessage = "启动 Wine Steam 失败：\(error.localizedDescription)"
        }
    }

    func stopWineSteamProcesses() {
        let context = resolveWineSteamEntryContext()
        var matchedKinds = 0

        let patterns = [
            "Steam.exe",
            "steamwebhelper.exe",
            "steamservice.exe",
            "steamerrorreporter",
            "gameoverlayui.exe"
        ]

        for pattern in patterns {
            if runSyncCommand("/usr/bin/pkill", arguments: ["-f", pattern], extraEnvironment: nil) == 0 {
                matchedKinds += 1
            }
        }

        refreshRuntimeStatus()
        let wineBinary = runtimeReport.resolvedWineBinaryPath.isEmpty
            ? (RuntimeManager.resolveWineBinary(preferred: preferredWineBinaryPath) ?? "")
            : runtimeReport.resolvedWineBinaryPath

        if
            !wineBinary.isEmpty,
            let wineserver = resolveWineserverPath(fromWineBinary: wineBinary),
            let prefixPath = context?.prefixPath,
            !prefixPath.isEmpty
        {
            _ = runSyncCommand(wineserver, arguments: ["-k"], extraEnvironment: ["WINEPREFIX": prefixPath])
            _ = runSyncCommand(wineserver, arguments: ["-w"], extraEnvironment: ["WINEPREFIX": prefixPath])
        }

        statusMessage = matchedKinds == 0
            ? "未发现正在运行的 Wine Steam 进程。"
            : "已请求关闭 Wine Steam 相关进程（命中 \(matchedKinds) 类进程）。"
    }

    func applyRecommendedCandidate(_ candidate: ScanCandidate) {
        updateSelected { game in
            game.exePath = candidate.exeURL.path
            game.gameFolderPath = candidate.exeURL.deletingLastPathComponent().path
            if game.name == "新游戏" || game.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                game.name = candidate.exeURL.deletingPathExtension().lastPathComponent
            }
            if game.prefixDir.isEmpty {
                game.prefixDir = defaultPrefixDir(for: game.name)
            }
            if let currentScan = scanResult {
                game.engineHint = currentScan.engineHint
            }
        }
        statusMessage = "已选择主程序：\(candidate.exeURL.lastPathComponent)"
    }

    func saveCurrentFromP1() {
        guard selectedGame != nil else { return }
        updateSelected { game in
            if game.prefixDir.isEmpty { game.prefixDir = defaultPrefixDir(for: game.name) }
            if let scanResult { game.engineHint = scanResult.engineHint }
        }
        statusMessage = "已保存到游戏列表（进入 P2）"
    }

    func startGame() {
        guard let game = selectedGame else {
            statusMessage = "请先选择一个游戏配置"
            return
        }
        do {
            let log = try GameLauncher.launch(game: game, logsDir: logsDir, preferredWineBinaryPath: preferredWineBinaryPath)
            lastLogPath = log.path
            statusMessage = "已尝试启动：\(game.name)"
            touchSelected()
        } catch {
            statusMessage = "启动失败：\(error.localizedDescription)"
        }
    }

    func openLastLog() {
        guard !lastLogPath.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: lastLogPath))
    }

    func openRepairGuide() {
        RuntimeManager.openPrivacySecuritySettings()
    }

    func installEmbeddedXQuartz() {
        guard let path = RuntimeManager.resolveEmbeddedXQuartzInstaller() else {
            statusMessage = "未找到内置 XQuartz 安装包。请重新打包，或确认桌面存在 XQuartz.pkg。"
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
        statusMessage = "已打开 XQuartz 安装包"
    }

    func openRosettaGuide() { RuntimeManager.openRosettaGuide() }
    func openPrivacySettings() { RuntimeManager.openPrivacySecuritySettings() }
    func openWineDownloadPage() { RuntimeManager.openWineDownloadPage() }
    func openXQuartzDownloadPage() { RuntimeManager.openXQuartzDownloadPage() }

    func copyTerminalInstallCommands() {
        let commands = [
            "# GAL FOR MacOS：Wine 已内置，无需单独安装 Wine",
            "",
            "# 1) Rosetta 2（Apple Silicon 必需/建议）",
            "/usr/sbin/softwareupdate --install-rosetta --agree-to-license",
            "",
            "# 2) XQuartz（部分 Wine 场景需要，二选一）",
            "# 方式 A：使用 App 内置的一键安装按钮（推荐）",
            "# 方式 B：终端安装",
            "brew install --cask xquartz",
            "",
            "# 如未安装 Homebrew，先执行：",
            "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        ].joined(separator: "\n")

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(commands, forType: .string)
        statusMessage = "已复制终端安装命令（Rosetta / XQuartz；Wine 已内置）"
    }

    func downloadAndOpenWineInstaller() {
        downloadAndOpenInstaller(.wine)
    }

    func downloadAndOpenXQuartzInstaller() {
        downloadAndOpenInstaller(.xquartz)
    }

    func downloadAndOpenWineSteamInstaller() {
        guard !isDownloadingInstaller else { return }
        isDownloadingInstaller = true
        downloadStatusText = "正在下载 Wine Steam 安装器..."

        Task {
            defer {
                Task { @MainActor in self.isDownloadingInstaller = false }
            }

            do {
                let installerURL = try await downloadWineSteamInstaller()
                await MainActor.run {
                    NSWorkspace.shared.open(installerURL)
                    self.downloadStatusText = "Wine Steam 安装器已下载并打开：\(installerURL.lastPathComponent)"
                    self.statusMessage = "已打开 Wine Steam 安装器"
                }
            } catch {
                await MainActor.run {
                    self.downloadStatusText = "Wine Steam 下载失败：\(error.localizedDescription)"
                    self.statusMessage = self.downloadStatusText
                }
            }
        }
    }

    func downloadAndOpenInstaller(_ kind: RuntimeInstaller.InstallerKind) {
        guard !isDownloadingInstaller else { return }
        isDownloadingInstaller = true
        downloadStatusText = "正在准备下载 \(kind.displayName) 安装包..."
        Task {
            defer {
                Task { @MainActor in self.isDownloadingInstaller = false }
            }
            do {
                let result = try await RuntimeInstaller.downloadLatestInstaller(kind: kind)
                await MainActor.run {
                    self.downloadStatusText = "下载完成并已打开安装包：\(result.downloadedFileURL.lastPathComponent)"
                    self.statusMessage = "已打开 \(kind.displayName) 安装包"
                }
            } catch {
                await MainActor.run {
                    self.downloadStatusText = "\(kind.displayName) 下载失败：\(error.localizedDescription)"
                    self.statusMessage = self.downloadStatusText
                }
            }
        }
    }

    private func applyScanResult(_ result: ScanResult, persistAsCurrent: Bool) {
        scanResult = result
        updateSelected { game in
            game.gameFolderPath = result.folderURL.path
            game.engineHint = result.engineHint
            if game.name == "新游戏" || game.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                game.name = result.folderURL.lastPathComponent
            }
            if let recommended = result.recommendedEXE {
                game.exePath = recommended.path
            }
            if game.prefixDir.isEmpty {
                game.prefixDir = defaultPrefixDir(for: game.name)
            }
        }

        if let recommended = result.recommendedEXE {
            statusMessage = "已扫描：推荐主程序 \(recommended.lastPathComponent)"
        } else {
            statusMessage = "已扫描文件夹，但未找到可用 EXE（可手动选择）"
        }

        if !persistAsCurrent { return }
    }

    private func updateSelected(_ mutate: (inout GameEntry) -> Void) {
        guard let idx = selectedIndex else { return }
        mutate(&games[idx])
        games[idx].updatedAt = Date()
        save()
    }

    private func touchSelected() {
        updateSelected { _ in }
    }

    private func ensureDirs() {
        try? fm.createDirectory(at: appDataDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: logsDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: prefixesDir, withIntermediateDirectories: true)
    }

    private func resolveWineSteamEntryContext() -> WineSteamEntryContext? {
        let home = fm.homeDirectoryForCurrentUser
        let candidates: [(steamExe: URL, prefix: URL, source: String)] = [
            (
                appDataDir
                    .appendingPathComponent("steam-prefix", isDirectory: true)
                    .appendingPathComponent("drive_c", isDirectory: true)
                    .appendingPathComponent("Program Files (x86)", isDirectory: true)
                    .appendingPathComponent("Steam", isDirectory: true)
                    .appendingPathComponent("Steam.exe"),
                appDataDir.appendingPathComponent("steam-prefix", isDirectory: true),
                "专用 Steam Prefix（.vnlauncher）"
            ),
            (
                home
                    .appendingPathComponent(".vnlauncher-zero", isDirectory: true)
                    .appendingPathComponent("steam-prefix", isDirectory: true)
                    .appendingPathComponent("drive_c", isDirectory: true)
                    .appendingPathComponent("Program Files (x86)", isDirectory: true)
                    .appendingPathComponent("Steam", isDirectory: true)
                    .appendingPathComponent("Steam.exe"),
                home
                    .appendingPathComponent(".vnlauncher-zero", isDirectory: true)
                    .appendingPathComponent("steam-prefix", isDirectory: true),
                "兼容 Steam Prefix（.vnlauncher-zero）"
            )
        ]

        for candidate in candidates where fm.fileExists(atPath: candidate.steamExe.path) {
            return WineSteamEntryContext(
                steamExePath: candidate.steamExe.path,
                prefixPath: candidate.prefix.path,
                sourceLabel: candidate.source
            )
        }

        if let inferred = inferFromRunningPrefixes() {
            return inferred
        }

        return nil
    }

    private func launchSteamInstallerIfAvailable(wineBinary: String) -> Bool {
        guard let installer = existingSteamInstallerURL() else {
            return false
        }

        let defaultPrefix = appDataDir.appendingPathComponent("steam-prefix", isDirectory: true)
        try? fm.createDirectory(at: defaultPrefix, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: wineBinary)
        process.arguments = [installer.path]
        process.currentDirectoryURL = installer.deletingLastPathComponent()
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = defaultPrefix.path
        process.environment = env

        do {
            try process.run()
            statusMessage = "未检测到 Steam 客户端，已自动启动 Steam 安装器。安装完成后再点一次即可。"
            return true
        } catch {
            statusMessage = "启动 Steam 安装器失败：\(error.localizedDescription)"
            return true
        }
    }

    private func existingSteamInstallerURL() -> URL? {
        let home = fm.homeDirectoryForCurrentUser
        let installerCandidates: [URL] = [
            appDataDir
                .appendingPathComponent("downloads", isDirectory: true)
                .appendingPathComponent("SteamSetup.exe"),
            home
                .appendingPathComponent(".vnlauncher-zero", isDirectory: true)
                .appendingPathComponent("downloads", isDirectory: true)
                .appendingPathComponent("SteamSetup.exe")
        ]

        return installerCandidates.first(where: { fm.fileExists(atPath: $0.path) })
    }

    private func downloadWineSteamInstaller() async throws -> URL {
        let downloadsDir = appDataDir.appendingPathComponent("downloads", isDirectory: true)
        try fm.createDirectory(at: downloadsDir, withIntermediateDirectories: true)

        let targetURL = downloadsDir.appendingPathComponent("SteamSetup.exe")
        let session = URLSession(configuration: .default)
        var request = URLRequest(url: Self.steamInstallerURL)
        request.setValue("GAL-FOR-MacOS/1.0", forHTTPHeaderField: "User-Agent")

        let (tmpURL, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(
                domain: "WineSteamInstaller",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Steam 安装器下载失败（服务器返回异常）。"]
            )
        }

        try? fm.removeItem(at: targetURL)
        try fm.moveItem(at: tmpURL, to: targetURL)
        return targetURL
    }

    private func inferFromRunningPrefixes() -> WineSteamEntryContext? {
        guard let selected = selectedGame else { return nil }
        let possibleSteamExe = URL(fileURLWithPath: selected.prefixDir)
            .appendingPathComponent("drive_c", isDirectory: true)
            .appendingPathComponent("Program Files (x86)", isDirectory: true)
            .appendingPathComponent("Steam", isDirectory: true)
            .appendingPathComponent("Steam.exe")

        guard fm.fileExists(atPath: possibleSteamExe.path), !selected.prefixDir.isEmpty else { return nil }
        return WineSteamEntryContext(
            steamExePath: possibleSteamExe.path,
            prefixPath: selected.prefixDir,
            sourceLabel: "当前游戏 Prefix"
        )
    }

    @discardableResult
    private func runSyncCommand(_ executable: String, arguments: [String], extraEnvironment: [String: String]?) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        if let extraEnvironment {
            var env = ProcessInfo.processInfo.environment
            env.merge(extraEnvironment) { _, new in new }
            process.environment = env
        }

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    private func resolveWineserverPath(fromWineBinary wineBinaryPath: String) -> String? {
        let candidate = URL(fileURLWithPath: wineBinaryPath)
            .deletingLastPathComponent()
            .appendingPathComponent("wineserver")
            .path
        return fm.isExecutableFile(atPath: candidate) ? candidate : nil
    }

    private func defaultPrefixDir(for name: String) -> String {
        let safe = slug(name)
        let path = prefixesDir.appendingPathComponent(safe, isDirectory: true)
        try? fm.createDirectory(at: path, withIntermediateDirectories: true)
        return path.path
    }

    private func slug(_ raw: String) -> String {
        let lower = raw.lowercased()
        let mapped = lower.map { ch -> Character in
            if ch.isLetter || ch.isNumber || ch == "_" || ch == "-" || ch == "." { return ch }
            return "_"
        }
        let joined = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "_-."))
        return joined.isEmpty ? UUID().uuidString.lowercased() : joined
    }

    private func nextUntitledName() -> String {
        let existing = Set(games.map(\.name))
        if !existing.contains("新游戏") { return "新游戏" }
        var i = 2
        while existing.contains("新游戏 \(i)") { i += 1 }
        return "新游戏 \(i)"
    }
}
