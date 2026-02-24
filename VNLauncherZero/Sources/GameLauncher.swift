import Foundation

enum GameLauncherError: LocalizedError {
    case gameNotConfigured
    case gameFolderMissing
    case exeMissing
    case prefixCreateFailed
    case wineNotFound
    case logCreateFailed

    var errorDescription: String? {
        switch self {
        case .gameNotConfigured: return "请先在 P1 选择游戏文件夹并确认主程序。"
        case .gameFolderMissing: return "游戏目录不存在。"
        case .exeMissing: return "主程序 EXE 不存在。"
        case .prefixCreateFailed: return "无法创建 Wine Prefix 文件夹。"
        case .wineNotFound: return "未找到 Wine。请先在 P2 安装或手动指定 Wine。"
        case .logCreateFailed: return "无法创建日志文件。"
        }
    }
}

enum GameLauncher {
    static func launch(game: GameEntry, logsDir: URL, preferredWineBinaryPath: String) throws -> URL {
        guard let exeURL = game.exeURL else { throw GameLauncherError.gameNotConfigured }
        guard let folderURL = game.folderURL else { throw GameLauncherError.gameFolderMissing }
        let fm = FileManager.default
        guard fm.fileExists(atPath: folderURL.path) else { throw GameLauncherError.gameFolderMissing }
        guard fm.fileExists(atPath: exeURL.path) else { throw GameLauncherError.exeMissing }

        let prefixURL: URL
        if let existingPrefix = game.prefixURL {
            prefixURL = existingPrefix
        } else {
            throw GameLauncherError.gameNotConfigured
        }

        do {
            try fm.createDirectory(at: prefixURL, withIntermediateDirectories: true)
            try fm.createDirectory(at: logsDir, withIntermediateDirectories: true)
        } catch {
            throw GameLauncherError.prefixCreateFailed
        }

        guard let wineBinary = RuntimeManager.resolveWineBinary(preferred: preferredWineBinaryPath) else {
            throw GameLauncherError.wineNotFound
        }

        let logURL = logsDir.appendingPathComponent(logFileName(for: game))
        guard fm.createFile(atPath: logURL.path, contents: nil) || fm.fileExists(atPath: logURL.path) else {
            throw GameLauncherError.logCreateFailed
        }

        let prelude = [
            "[\(Date())] Launch request",
            "GAME=\(game.name)",
            "FOLDER=\(folderURL.path)",
            "EXE=\(exeURL.path)",
            "PREFIX=\(prefixURL.path)",
            "WINE=\(wineBinary)",
            ""
        ].joined(separator: "\n")
        if let data = prelude.data(using: .utf8) {
            try? data.append(to: logURL)
        }

        let fileHandle = try FileHandle(forWritingTo: logURL)
        try fileHandle.seekToEnd()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: wineBinary)
        process.arguments = [exeURL.path]
        process.currentDirectoryURL = folderURL
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefixURL.path
        env["WINEDEBUG"] = "-all"
        env["LANG"] = "ja_JP.UTF-8"
        env["LC_ALL"] = "ja_JP.UTF-8"
        process.environment = env
        process.standardOutput = fileHandle
        process.standardError = fileHandle
        process.terminationHandler = { _ in try? fileHandle.close() }

        try process.run()
        return logURL
    }

    private static func logFileName(for game: GameEntry) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let safe = game.name.replacingOccurrences(of: "/", with: "_")
        return "\(safe)-\(formatter.string(from: Date())).log"
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
