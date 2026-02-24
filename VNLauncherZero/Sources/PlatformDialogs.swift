import AppKit
import Foundation

enum PlatformDialogs {
    static func chooseGameFolder(startingAt path: String?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择游戏文件夹"
        panel.message = "请选择包含 .exe / .xp3 等文件的游戏目录"
        if let path, !path.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: path)
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseExecutable(startingAt path: String?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择 EXE"
        panel.message = "请选择 Windows 游戏主程序（.exe）"
        if let path, !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            panel.directoryURL = FileManager.default.fileExists(atPath: path) ? url.deletingLastPathComponent() : url
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseFolder(title: String, message: String, startingAt path: String?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = title
        panel.message = message
        if let path, !path.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: path)
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseWineBinary(startingAt path: String?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择 Wine"
        panel.message = "请选择 wine64 或 wine 可执行文件"
        if let path, !path.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseAppBundle(startingAt path: String?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择 App"
        panel.message = "请选择 Wine.app / Wine Stable.app"
        if let path, !path.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
        }
        return panel.runModal() == .OK ? panel.url : nil
    }
}

