import AppKit
import Foundation

enum RuntimeManager {
    struct DetectedPaths {
        var wineBinary: String?
        var wineApp: String?
        var xQuartz: String?
        var rosettaInstalled: Bool
        var isAppleSilicon: Bool
        var wineQuarantined: Bool
    }

    static func detect(userWineBinaryPath: String?, userWineAppPath: String?) -> RuntimeEnvironmentReport {
        let paths = detectPaths(userWineBinaryPath: userWineBinaryPath, userWineAppPath: userWineAppPath)
        let cpu = paths.isAppleSilicon ? "Apple Silicon (M系列)" : "Intel / 其他"

        var components: [RuntimeComponentStatus] = []
        components.append(
            RuntimeComponentStatus(
                title: "Wine 引擎",
                state: paths.wineBinary == nil ? .missing : (paths.wineQuarantined ? .blocked : .ready),
                summary: paths.wineBinary == nil ? "未检测到 wine64 / wine" : "已检测到 Wine 可执行文件",
                detail: paths.wineBinary ?? "可在“运行环境”步骤里选择 Wine 可执行文件或 Wine.app"
            )
        )

        if paths.isAppleSilicon {
            components.append(
                RuntimeComponentStatus(
                    title: "Rosetta 2（Apple Silicon 建议）",
                    state: paths.rosettaInstalled ? .ready : .warning,
                    summary: paths.rosettaInstalled ? "已检测到 Rosetta 相关组件" : "建议安装 Rosetta 2 以提升兼容性",
                    detail: paths.rosettaInstalled ? "已就绪" : "可在运行环境步骤点击“打开 Rosetta 安装引导”"
                )
            )
        }

        components.append(
            RuntimeComponentStatus(
                title: "XQuartz（部分 Wine 场景需要）",
                state: paths.xQuartz == nil ? .warning : .ready,
                summary: paths.xQuartz == nil ? "未检测到 XQuartz（部分环境可能需要）" : "已检测到 XQuartz",
                detail: paths.xQuartz ?? "若启动失败且日志出现显示相关错误，可安装 XQuartz"
            )
        )

        components.append(
            RuntimeComponentStatus(
                title: "macOS 安全拦截（Gatekeeper）",
                state: paths.wineQuarantined ? .blocked : .ready,
                summary: paths.wineQuarantined ? "检测到 Wine.app 可能仍带隔离标记" : "未检测到明显拦截标记（首次运行仍可能提示）",
                detail: paths.wineQuarantined ? "可点击“打开隐私与安全性”后允许，或右键 Wine.app 选择“打开”" : "如出现“未打开 Wine Stable”，在系统设置里点“仍要打开”即可"
            )
        )

        return RuntimeEnvironmentReport(
            checkedAt: Date(),
            cpuDescription: cpu,
            wineBinaryPath: paths.wineBinary,
            wineAppPath: paths.wineApp,
            xQuartzPath: paths.xQuartz,
            components: components
        )
    }

    static func detectPaths(userWineBinaryPath: String?, userWineAppPath: String?) -> DetectedPaths {
        let isAppleSilicon = ProcessInfo.processInfo.machineArchitecture == "arm64"
        let rosettaInstalled = isAppleSilicon ? detectRosettaInstalled() : true
        let xQuartz = commonXQuartzPaths().first(where: { FileManager.default.fileExists(atPath: $0) })

        let userWineBinary = normalizedExecutable(path: userWineBinaryPath)
        let userWineApp = normalizedApp(path: userWineAppPath)
        let bundledFromUserApp = userWineApp.flatMap(resolveWineBinaryPath(inWineApp:))

        let commonWineApp = commonWineAppPaths().first(where: { FileManager.default.fileExists(atPath: $0) })
        let bundledFromCommonApp = commonWineApp.flatMap(resolveWineBinaryPath(inWineApp:))
        let pathWine = commandPathForWine()

        let wineBinary = userWineBinary ?? bundledFromUserApp ?? pathWine ?? bundledFromCommonApp
        let wineApp = userWineApp ?? commonWineApp
        let wineQuarantined = wineApp.map(hasQuarantineAttribute(appPath:)) ?? false

        return DetectedPaths(
            wineBinary: wineBinary,
            wineApp: wineApp,
            xQuartz: xQuartz,
            rosettaInstalled: rosettaInstalled,
            isAppleSilicon: isAppleSilicon,
            wineQuarantined: wineQuarantined
        )
    }

    static func openWineDownloadPage() {
        if let url = URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openXQuartzDownloadPage() {
        if let url = URL(string: "https://www.xquartz.org/") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openRosettaGuide() {
        if let url = URL(string: "https://support.apple.com/zh-cn/102527") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openPrivacySecuritySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }

    static func revealWineAppInFinder(_ path: String?) {
        guard let path, !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func resolveWineBinaryPath(inWineApp appPath: String) -> String? {
        let candidates = [
            appPath + "/Contents/Resources/wine/bin/wine64",
            appPath + "/Contents/Resources/wine/bin/wine",
            appPath + "/Contents/MacOS/wine64",
            appPath + "/Contents/MacOS/wine"
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    private static func commonWineAppPaths() -> [String] {
        [
            "/Applications/Wine Stable.app",
            "/Applications/Wine Devel.app",
            "/Applications/Wine.app"
        ]
    }

    private static func commonXQuartzPaths() -> [String] {
        [
            "/Applications/Utilities/XQuartz.app",
            "/Applications/XQuartz.app"
        ]
    }

    private static func normalizedExecutable(path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    private static func normalizedApp(path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private static func commandPathForWine() -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v wine64 || command -v wine"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private static func detectRosettaInstalled() -> Bool {
        let candidates = [
            "/Library/Apple/usr/share/rosetta/rosetta",
            "/Library/Apple/usr/libexec/oah/libRosettaRuntime"
        ]
        if candidates.contains(where: { FileManager.default.fileExists(atPath: $0) }) {
            return true
        }
        return false
    }

    private static func hasQuarantineAttribute(appPath: String) -> Bool {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-p", "com.apple.quarantine", appPath]
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}

private extension ProcessInfo {
    var machineArchitecture: String {
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

