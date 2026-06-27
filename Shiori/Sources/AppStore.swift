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
    @Published var updateState = UpdateState()
    // Switch：用户自备的 prod.keys 与固件目录（绝不随 App 分发）。
    @Published var preferredKeysPath: String = ""
    @Published var preferredFirmwarePath: String = ""

    private let fm = FileManager.default

    let appDataDir: URL
    let logsDir: URL
    let prefixesDir: URL
    let storeURL: URL

    var preferredWineBinaryPath: String = "" { didSet { save() } }
    var preferredWineAppPath: String = "" { didSet { save() } }

    init() {
        let home = fm.homeDirectoryForCurrentUser
        let legacyAppDataDir = home.appendingPathComponent(".vnlauncher", isDirectory: true)
        appDataDir = home.appendingPathComponent(".shiori", isDirectory: true)
        logsDir = appDataDir.appendingPathComponent("logs", isDirectory: true)
        prefixesDir = appDataDir.appendingPathComponent("prefixes", isDirectory: true)
        storeURL = appDataDir.appendingPathComponent("games.json")
        migrateLegacyDataIfNeeded(from: legacyAppDataDir)
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
            "“结束进程”会终止 Wine Steam 与其子进程，正在运行的 Steam 游戏会被强制退出。",
            "入口优先使用专用 Prefix：~/.shiori/steam-prefix（首次启动会兼容迁移旧 ~/.vnlauncher 数据）。",
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
            preferredKeysPath = file.preferredKeysPath ?? ""
            preferredFirmwarePath = file.preferredFirmwarePath ?? ""
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
                preferredWineAppPath: preferredWineAppPath,
                preferredKeysPath: preferredKeysPath,
                preferredFirmwarePath: preferredFirmwarePath
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

    // Switch：与 chooseEXEManually / choosePrefixFolder 同构的手动选择（ROM 之于 EXE，模拟器之于 Wine）。
    func chooseSwitchROM() {
        let start = selectedGame?.romPath
        guard let rom = PlatformPickers.chooseFile(startingAt: start, prompt: "选择 ROM", message: "请选择 Switch 游戏 ROM（.nsp / .xci）") else { return }
        updateSelected { game in
            game.platform = .switchEmu
            game.romPath = rom.path
            if game.gameFolderPath.isEmpty { game.gameFolderPath = rom.deletingLastPathComponent().path }
            if game.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || game.name == "新游戏" {
                game.name = rom.deletingPathExtension().lastPathComponent
            }
            if game.engineHint == "未识别" { game.engineHint = "Nintendo Switch" }
        }
        statusMessage = "已选择 ROM：\(rom.lastPathComponent)"
    }

    func chooseEmulatorApp() {
        let start = selectedGame?.emulatorAppPath
        guard let app = PlatformPickers.chooseApp(startingAt: start, prompt: "选择模拟器", message: "请选择 Switch 模拟器 App（Ryujinx / yuzu 系等均可）") else { return }
        updateSelected { game in
            game.emulatorAppPath = app.path
            game.platform = .switchEmu
        }
        statusMessage = "已设置模拟器：\(app.lastPathComponent)"
    }

    // —— Switch keys / firmware：仅"导入用户自备文件"，绝不分发版权文件 ——
    func chooseSwitchKeys() {
        guard let f = PlatformPickers.chooseFile(startingAt: preferredKeysPath, prompt: "选择 prod.keys", message: "请选择你从自己持有的 Switch 主机导出的 prod.keys") else { return }
        preferredKeysPath = f.path
        save()
        statusMessage = "已导入 prod.keys（你自备）"
    }

    func chooseSwitchFirmware() {
        guard let f = PlatformPickers.chooseFolder(startingAt: preferredFirmwarePath, prompt: "选择固件文件夹", message: "请选择包含 Switch 固件（一组 .nca）的文件夹") else { return }
        preferredFirmwarePath = f.path
        save()
        statusMessage = "已设置固件目录（你自备）"
    }

    var switchKeysReady: Bool {
        !preferredKeysPath.isEmpty && fm.fileExists(atPath: preferredKeysPath)
    }

    var switchFirmwareReady: Bool {
        !preferredFirmwarePath.isEmpty && fm.fileExists(atPath: preferredFirmwarePath)
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
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = context.prefixPath
        env["WINEDEBUG"] = "-all"
        process.environment = env

        do {
            try process.run()
            statusMessage = "已启动 Wine Steam（\(context.sourceLabel)）。"
        } catch {
            statusMessage = "启动 Wine Steam 失败：\(error.localizedDescription)"
        }
    }

    func stopWineSteamProcesses() {
        refreshRuntimeStatus()
        let wineBinary = runtimeReport.resolvedWineBinaryPath.isEmpty
            ? (RuntimeManager.resolveWineBinary(preferred: preferredWineBinaryPath) ?? "")
            : runtimeReport.resolvedWineBinaryPath
        let contexts = resolveWineSteamCleanupContexts()
        var commandHits = 0
        var signaledPIDs = Set<Int32>()

        for context in contexts {
            if
                !wineBinary.isEmpty,
                let wineserver = resolveWineserverPath(fromWineBinary: wineBinary),
                !context.prefixPath.isEmpty
            {
                if runSyncCommand(wineserver, arguments: ["-k"], extraEnvironment: ["WINEPREFIX": context.prefixPath]) == 0 {
                    commandHits += 1
                }
            }

            let prefixPIDs = wineProcessIDs(openingFilesUnder: context.prefixPath)
            if !prefixPIDs.isEmpty {
                signaledPIDs.formUnion(prefixPIDs)
                _ = signalProcessIDs(prefixPIDs, signal: "TERM")
            }
        }

        Thread.sleep(forTimeInterval: 0.5)

        var remainingPIDs = Set<Int32>()
        for context in contexts {
            remainingPIDs.formUnion(wineProcessIDs(openingFilesUnder: context.prefixPath))
        }
        _ = signalProcessIDs(remainingPIDs, signal: "KILL")
        signaledPIDs.formUnion(remainingPIDs)

        Thread.sleep(forTimeInterval: 0.2)

        var finalRemainingPIDs = Set<Int32>()
        for context in contexts {
            finalRemainingPIDs.formUnion(wineProcessIDs(openingFilesUnder: context.prefixPath))
        }

        if !finalRemainingPIDs.isEmpty {
            statusMessage = "已请求关闭 Wine Steam，但仍有 \(finalRemainingPIDs.count) 个 Wine 残留进程。"
            return
        }

        let totalHits = commandHits + signaledPIDs.count
        statusMessage = totalHits == 0
            ? "未发现正在运行的 Wine Steam 进程。"
            : "已关闭 Wine Steam 相关进程（命中 \(totalHits) 项）。"
    }

    func applyRecommendedCandidate(_ candidate: ScanCandidate) {
        updateSelected { game in
            switch game.platform {
            case .windows:
                game.exePath = candidate.exeURL.path
                game.gameFolderPath = candidate.exeURL.deletingLastPathComponent().path
                if game.name == "新游戏" || game.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    game.name = candidate.exeURL.deletingPathExtension().lastPathComponent
                }
                if game.prefixDir.isEmpty {
                    game.prefixDir = defaultPrefixDir(for: game.name)
                }
            case .switchEmu:
                game.romPath = candidate.exeURL.path
            }
            if let currentScan = scanResult {
                game.engineHint = currentScan.engineHint
            }
        }
        let label = selectedGame?.platform == .switchEmu ? "ROM" : "主程序"
        statusMessage = "已选择\(label)：\(candidate.exeURL.lastPathComponent)"
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
            let log = try GameLauncher.launch(
                game: game,
                logsDir: logsDir,
                preferredWineBinaryPath: preferredWineBinaryPath,
                switchKeysPath: preferredKeysPath,
                switchFirmwarePath: preferredFirmwarePath,
                switchDataDir: appDataDir.appendingPathComponent("switch-data", isDirectory: true)
            )
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

    /// 检查更新：拉取仓库 version.json 与自身版本比对。userInitiated 时把结果写到状态栏。
    func checkForUpdates(userInitiated: Bool = false) async {
        if userInitiated {
            updateState.phase = .checking
            updateState.message = "正在检查更新…"
            statusMessage = "正在检查更新…"
        }
        let result = await UpdateChecker.fetch()
        updateState = result
        if userInitiated, !result.message.isEmpty {
            statusMessage = result.message
        }
    }

    func openReleasesPage() {
        let target = updateState.downloadURL.isEmpty
            ? (AppInfo.releasesPageURL?.absoluteString ?? "")
            : updateState.downloadURL
        guard let url = URL(string: target) else { return }
        NSWorkspace.shared.open(url)
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
            "# Shiori：Wine 已内置，无需单独安装 Wine",
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
            game.platform = result.platform
            game.engineHint = result.engineHint
            if game.name == "新游戏" || game.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                game.name = result.folderURL.lastPathComponent
            }
            switch result.platform {
            case .windows:
                if let recommended = result.recommendedEXE {
                    game.exePath = recommended.path
                }
                if game.prefixDir.isEmpty {
                    game.prefixDir = defaultPrefixDir(for: game.name)
                }
            case .switchEmu:
                if let rom = result.romURL { game.romPath = rom.path }
                if let emu = result.emulatorAppURL { game.emulatorAppPath = emu.path }
                if let script = result.launchScriptURL { game.launchScriptPath = script.path }
            }
        }

        if result.platform == .switchEmu {
            let emu = result.emulatorName ?? "模拟器"
            if result.launchScriptURL != nil {
                statusMessage = "已识别为 Switch 游戏（将用现成一键脚本启动 · \(emu)）"
            } else if result.romURL != nil {
                statusMessage = "已识别为 Switch 游戏（ROM 就绪 · 模拟器：\(emu)）"
            } else {
                statusMessage = "已识别为 Switch 游戏，但未找到 ROM/模拟器（可手动选择）"
            }
        } else if let blocker = result.antiCheats.first(where: { $0.severity == .blocking }) {
            statusMessage = "⚠️ 检测到 \(blocker.name)：内核级反作弊，macOS 无法运行此游戏。"
        } else if let limited = result.antiCheats.first {
            statusMessage = "⚠️ 检测到 \(limited.name)：macOS 上几乎无法运行。"
        } else if let recommended = result.recommendedEXE {
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

    private func migrateLegacyDataIfNeeded(from legacyDir: URL) {
        let hasCurrentRoot = fm.fileExists(atPath: appDataDir.path)
        if !hasCurrentRoot, fm.fileExists(atPath: legacyDir.path) {
            try? fm.copyItem(at: legacyDir, to: appDataDir)
        }

        try? fm.createDirectory(at: appDataDir, withIntermediateDirectories: true)

        copyLegacyFile(named: "gal-for-macos-games.json", to: storeURL, legacyDir: legacyDir)
        copyLegacyDirectory(named: "zero-prefixes", to: prefixesDir, legacyDir: legacyDir)
        copyLegacyDirectory(
            named: "steam-prefix",
            to: appDataDir.appendingPathComponent("steam-prefix", isDirectory: true),
            legacyDir: legacyDir
        )
        copyLegacyDirectory(
            named: "downloads",
            to: appDataDir.appendingPathComponent("downloads", isDirectory: true),
            legacyDir: legacyDir
        )
    }

    private func copyLegacyFile(named legacyName: String, to destination: URL, legacyDir: URL) {
        guard !fm.fileExists(atPath: destination.path) else { return }
        let candidates = [
            appDataDir.appendingPathComponent(legacyName),
            legacyDir.appendingPathComponent(legacyName)
        ]
        guard let source = candidates.first(where: { fm.fileExists(atPath: $0.path) }) else { return }
        try? fm.copyItem(at: source, to: destination)
    }

    private func copyLegacyDirectory(named legacyName: String, to destination: URL, legacyDir: URL) {
        guard !fm.fileExists(atPath: destination.path) else { return }
        let candidates = [
            appDataDir.appendingPathComponent(legacyName, isDirectory: true),
            legacyDir.appendingPathComponent(legacyName, isDirectory: true)
        ]
        guard let source = candidates.first(where: { fm.fileExists(atPath: $0.path) }) else { return }
        if source.path.hasPrefix(appDataDir.path + "/") {
            try? fm.moveItem(at: source, to: destination)
        } else {
            try? fm.copyItem(at: source, to: destination)
        }
    }

    private func resolveWineSteamEntryContext() -> WineSteamEntryContext? {
        resolveWineSteamCleanupContexts().first(where: { fm.fileExists(atPath: $0.steamExePath) })
    }

    private func resolveWineSteamCleanupContexts() -> [WineSteamEntryContext] {
        let home = fm.homeDirectoryForCurrentUser
        var candidates: [(steamExe: URL, prefix: URL, source: String)] = [
            (
                appDataDir
                    .appendingPathComponent("steam-prefix", isDirectory: true)
                    .appendingPathComponent("drive_c", isDirectory: true)
                    .appendingPathComponent("Program Files (x86)", isDirectory: true)
                    .appendingPathComponent("Steam", isDirectory: true)
                    .appendingPathComponent("Steam.exe"),
                appDataDir.appendingPathComponent("steam-prefix", isDirectory: true),
                "专用 Steam Prefix（.shiori）"
            ),
            (
                home
                    .appendingPathComponent(".vnlauncher", isDirectory: true)
                    .appendingPathComponent("steam-prefix", isDirectory: true)
                    .appendingPathComponent("drive_c", isDirectory: true)
                    .appendingPathComponent("Program Files (x86)", isDirectory: true)
                    .appendingPathComponent("Steam", isDirectory: true)
                    .appendingPathComponent("Steam.exe"),
                home
                    .appendingPathComponent(".vnlauncher", isDirectory: true)
                    .appendingPathComponent("steam-prefix", isDirectory: true),
                "兼容 Steam Prefix（.vnlauncher）"
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

        if
            let selected = selectedGame,
            !selected.prefixDir.isEmpty
        {
            let prefix = URL(fileURLWithPath: selected.prefixDir, isDirectory: true)
            candidates.append((
                prefix
                    .appendingPathComponent("drive_c", isDirectory: true)
                    .appendingPathComponent("Program Files (x86)", isDirectory: true)
                    .appendingPathComponent("Steam", isDirectory: true)
                    .appendingPathComponent("Steam.exe"),
                prefix,
                "当前游戏 Prefix"
            ))
        }

        var seenPrefixes = Set<String>()
        var contexts: [WineSteamEntryContext] = []
        for candidate in candidates {
            let prefixPath = candidate.prefix.standardizedFileURL.path
            guard fm.fileExists(atPath: prefixPath) || fm.fileExists(atPath: candidate.steamExe.path) else {
                continue
            }
            guard seenPrefixes.insert(prefixPath).inserted else {
                continue
            }
            contexts.append(WineSteamEntryContext(
                steamExePath: candidate.steamExe.standardizedFileURL.path,
                prefixPath: prefixPath,
                sourceLabel: candidate.source
            ))
        }

        return contexts
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
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = defaultPrefix.path
        env["WINEDEBUG"] = "-all"
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
                .appendingPathComponent(".vnlauncher", isDirectory: true)
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
        request.setValue("Shiori/1.0", forHTTPHeaderField: "User-Agent")

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
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

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

    private func runCommandOutput(_ executable: String, arguments: [String], extraEnvironment: [String: String]? = nil) -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        if let extraEnvironment {
            var env = ProcessInfo.processInfo.environment
            env.merge(extraEnvironment) { _, new in new }
            process.environment = env
        }

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private func wineProcessIDs(openingFilesUnder prefixPath: String) -> Set<Int32> {
        let normalizedPrefix = URL(fileURLWithPath: prefixPath, isDirectory: true).standardizedFileURL.path
        guard !normalizedPrefix.isEmpty else { return [] }

        let wineProcessPattern = [
            "wine",
            "wineserver",
            "winedevice",
            "wineboot\\.exe",
            "Steam\\.exe",
            "steamwebhelper\\.exe",
            "steamservice\\.exe",
            "steamerrorreporter\\.exe",
            "gameoverlayui\\.exe",
            "services\\.exe",
            "plugplay\\.exe",
            "svchost\\.exe",
            "explorer\\.exe",
            "rpcss\\.exe"
        ].joined(separator: "|")

        let candidatesOutput = runCommandOutput(
            "/usr/bin/pgrep",
            arguments: ["-f", wineProcessPattern]
        )
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let candidatePIDs = candidatesOutput
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0 != ownPID }

        var matches = Set<Int32>()
        for pid in candidatePIDs {
            let filesOutput = runCommandOutput("/usr/sbin/lsof", arguments: ["-nP", "-Fn", "-p", "\(pid)"])
            let prefixToken = "n\(normalizedPrefix)"
            let opensPrefix = filesOutput
                .split(whereSeparator: \.isNewline)
                .contains { line in
                    line == prefixToken || line.hasPrefix(prefixToken + "/")
                }
            if opensPrefix {
                matches.insert(pid)
            }
        }

        return matches
    }

    @discardableResult
    private func signalProcessIDs(_ pids: Set<Int32>, signal: String) -> Int {
        var hits = 0
        for pid in pids.sorted() {
            if runSyncCommand("/bin/kill", arguments: ["-\(signal)", "\(pid)"], extraEnvironment: nil) == 0 {
                hits += 1
            }
        }
        return hits
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
