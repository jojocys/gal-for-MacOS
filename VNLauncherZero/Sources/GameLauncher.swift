import Foundation

enum LaunchError: LocalizedError {
    case noWine
    case noEXE
    case exeMissing
    case cannotCreatePrefix
    case cannotCreateLog
    case processLaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case .noWine:
            return "未检测到 Wine，可先去 P2 运行环境步骤完成安装/选择。"
        case .noEXE:
            return "当前没有可启动的 EXE。请先在 P1 选择游戏文件夹并确认推荐主程序。"
        case .exeMissing:
            return "推荐的 EXE 文件不存在，可能目录被移动或删除。"
        case .cannotCreatePrefix:
            return "无法创建游戏运行环境（Wine Prefix）目录。"
        case .cannotCreateLog:
            return "无法创建日志文件。"
        case .processLaunchFailed(let msg):
            return "启动进程失败：\(msg)"
        }
    }
}

enum GameLauncher {
    static func launch(
        profile: SavedGameProfile,
        runtimeReport: RuntimeEnvironmentReport,
        userWineBinaryPath: String?,
        userWineAppPath: String?,
        logsDir: URL
    ) throws -> URL {
        let fm = FileManager.default
        guard !profile.exePath.isEmpty else { throw LaunchError.noEXE }
        guard fm.fileExists(atPath: profile.exePath) else { throw LaunchError.exeMissing }

        let paths = RuntimeManager.detectPaths(userWineBinaryPath: userWineBinaryPath, userWineAppPath: userWineAppPath)
        guard let wineBinary = paths.wineBinary ?? runtimeReport.wineBinaryPath else { throw LaunchError.noWine }

        do {
            try fm.createDirectory(at: profile.prefixURL, withIntermediateDirectories: true)
        } catch {
            throw LaunchError.cannotCreatePrefix
        }
        try fm.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let logURL = logsDir.appendingPathComponent(logFileName(for: profile))
        guard fm.createFile(atPath: logURL.path, contents: nil) || fm.fileExists(atPath: logURL.path) else {
            throw LaunchError.cannotCreateLog
        }

        appendLogHeader(logURL: logURL, profile: profile, wineBinary: wineBinary)

        do {
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()

            let process = Process()
            process.executableURL = URL(fileURLWithPath: wineBinary)
            process.arguments = [profile.exePath]
            process.currentDirectoryURL = profile.exeURL.deletingLastPathComponent()

            var env = ProcessInfo.processInfo.environment
            env["WINEPREFIX"] = profile.prefixPath
            env["WINEDEBUG"] = "-all"
            env["LANG"] = "ja_JP.UTF-8"
            env["LC_ALL"] = "ja_JP.UTF-8"
            process.environment = env
            process.standardOutput = handle
            process.standardError = handle
            process.terminationHandler = { _ in
                try? handle.close()
            }

            try process.run()
        } catch {
            throw LaunchError.processLaunchFailed(error.localizedDescription)
        }

        return logURL
    }

    private static func appendLogHeader(logURL: URL, profile: SavedGameProfile, wineBinary: String) {
        let lines = [
            "[\(Date())] Starting VN",
            "NAME=\(profile.name)",
            "ENGINE=\(profile.engine.rawValue)",
            "FOLDER=\(profile.folderPath)",
            "EXE=\(profile.exePath)",
            "PREFIX=\(profile.prefixPath)",
            "WINE=\(wineBinary)",
            ""
        ].joined(separator: "\n")
        if let data = lines.data(using: .utf8) {
            try? data.append(to: logURL)
        }
    }

    private static func logFileName(for profile: SavedGameProfile) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let safeName = profile.name.replacingOccurrences(of: "/", with: "_")
        return "\(safeName)-\(formatter.string(from: Date())).log"
    }
}

private extension Data {
    func append(to url: URL) throws {
        if let handle = try? FileHandle(forWritingTo: url) {
            try handle.seekToEnd()
            try handle.write(contentsOf: self)
            try handle.close()
        } else {
            try write(to: url, options: .atomic)
        }
    }
}

