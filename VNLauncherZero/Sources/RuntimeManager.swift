import AppKit
import Foundation

enum RuntimeManager {
    static func detect(preferredWineBinaryPath: String, preferredWineAppPath: String) -> RuntimeCheckReport {
        let wineBinary = resolveWineBinary(preferred: preferredWineBinaryPath) ?? ""
        let wineApp = resolveWineApp(preferred: preferredWineAppPath) ?? ""
        let rosettaInstalled = detectRosettaInstalled()
        let xquartzApp = resolveXQuartzApp() ?? ""
        let xquartzInstalled = !xquartzApp.isEmpty
        let gatekeeperBlocked = detectQuarantine(on: !wineApp.isEmpty ? wineApp : inferAppPath(fromWineBinary: wineBinary) ?? "")

        var items: [RuntimeCheckItem] = []

        if wineBinary.isEmpty {
            items.append(RuntimeCheckItem(
                title: "Wine 引擎",
                detail: "未检测到 Wine。请使用内置 Wine 版本打包的 App，或手动指定 Wine。",
                state: .missing
            ))
        } else {
            let state: RuntimeCheckItem.State = gatekeeperBlocked ? .blocked : .ok
            let sourceLabel = isBundledWinePath(wineBinary) ? "（内置 Wine）" : "（系统/手动 Wine）"
            items.append(RuntimeCheckItem(
                title: "Wine 引擎",
                detail: "已检测到 Wine 执行文件 \(sourceLabel)\n\(wineBinary)",
                state: state
            ))
        }

        items.append(RuntimeCheckItem(
            title: "Rosetta 2 (Apple Silicon 建议)",
            detail: rosettaInstalled ? "已检测到 Rosetta 相关组件" : "未检测到 Rosetta。部分 Wine/游戏需要它。",
            state: rosettaInstalled ? .ok : .warning
        ))

        items.append(RuntimeCheckItem(
            title: "XQuartz (部分 Wine 场景需要)",
            detail: xquartzInstalled ? "已检测到 XQuartz\n\(xquartzApp)" : "未检测到 XQuartz。部分图形环境可能需要。",
            state: xquartzInstalled ? .ok : .warning
        ))

        items.append(RuntimeCheckItem(
            title: "macOS 安全拦截 (Gatekeeper)",
            detail: gatekeeperBlocked ? "检测到 Wine.app 可能带隔离标记。先打开系统设置 -> 隐私与安全性 -> 允许。" : "未发现明显拦截标记（首次运行仍可能提示）。",
            state: gatekeeperBlocked ? .blocked : .ok
        ))

        return RuntimeCheckReport(
            items: items,
            resolvedWineBinaryPath: wineBinary,
            detectedWineAppPath: wineApp,
            rosettaInstalled: rosettaInstalled,
            xquartzInstalled: xquartzInstalled,
            gatekeeperBlocked: gatekeeperBlocked
        )
    }

    static func openWineDownloadPage() {
        if let url = URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openXQuartzDownloadPage() {
        if let url = URL(string: "https://github.com/XQuartz/XQuartz/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openRosettaGuide() {
        if let url = URL(string: "https://support.apple.com/zh-cn/102527") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openPrivacySecuritySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    static func resolveWineBinary(preferred: String) -> String? {
        let fm = FileManager.default
        if let bundled = resolveBundledWineBinary(), fm.isExecutableFile(atPath: bundled) {
            return bundled
        }

        if !preferred.isEmpty, fm.isExecutableFile(atPath: preferred) {
            return preferred
        }

        let candidates = [
            "/opt/homebrew/bin/wine64",
            "/opt/homebrew/bin/wine",
            "/usr/local/bin/wine64",
            "/usr/local/bin/wine",
            "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine64",
            "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine"
        ]
        if let path = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) { return path }

        if let shellPath = shell("command -v wine64 || command -v wine"), !shellPath.isEmpty { return shellPath }
        return nil
    }

    static func resolveWineApp(preferred: String) -> String? {
        let fm = FileManager.default
        if let bundled = resolveBundledWineApp(), fm.fileExists(atPath: bundled) {
            return bundled
        }

        if !preferred.isEmpty, fm.fileExists(atPath: preferred) { return preferred }

        let common = [
            "/Applications/Wine Stable.app",
            "/Applications/Wine.app",
            NSHomeDirectory() + "/Applications/Wine Stable.app",
            NSHomeDirectory() + "/Applications/Wine.app"
        ]
        if let path = common.first(where: { fm.fileExists(atPath: $0) }) { return path }
        return nil
    }

    static func resolveXQuartzApp() -> String? {
        let paths = [
            "/Applications/Utilities/XQuartz.app",
            "/Applications/XQuartz.app"
        ]
        let fm = FileManager.default
        return paths.first(where: { fm.fileExists(atPath: $0) })
    }

    static func resolveEmbeddedXQuartzInstaller() -> String? {
        let fm = FileManager.default
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Installers/XQuartz.pkg").path
        if let bundled, fm.fileExists(atPath: bundled) { return bundled }

        // Development fallback when running from Xcode before packaging:
        // search Downloads/Desktop and mounted DMG volumes.
        let simpleCandidates = [
            NSHomeDirectory() + "/Downloads/XQuartz.pkg",
            NSHomeDirectory() + "/Desktop/XQuartz.pkg",
            NSHomeDirectory() + "/Downloads/XQuartz-2.8.5.pkg",
            NSHomeDirectory() + "/Desktop/XQuartz-2.8.5.pkg"
        ]
        if let path = simpleCandidates.first(where: { fm.fileExists(atPath: $0) }) {
            return path
        }

        // Mounted DMG commonly appears under /Volumes/XQuartz*/...
        let volumesURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        if let volumes = try? fm.contentsOfDirectory(at: volumesURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for volume in volumes where volume.lastPathComponent.lowercased().contains("xquartz") {
                if let files = try? fm.contentsOfDirectory(at: volume, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                    if let pkg = files.first(where: { $0.lastPathComponent.lowercased().hasPrefix("xquartz") && $0.pathExtension.lowercased() == "pkg" }) {
                        return pkg.path
                    }
                }
            }
        }

        return nil
    }

    static func resolveBundledWineBinary() -> String? {
        let fm = FileManager.default
        for appPath in bundledWineAppCandidates() {
            let candidates = [
                appPath + "/Contents/Resources/wine/bin/wine64",
                appPath + "/Contents/Resources/wine/bin/wine"
            ]
            if let bin = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) {
                return bin
            }
        }
        return nil
    }

    static func resolveBundledWineApp() -> String? {
        let fm = FileManager.default
        return bundledWineAppCandidates().first(where: { fm.fileExists(atPath: $0) })
    }

    private static func detectRosettaInstalled() -> Bool {
        if let output = shell("/usr/bin/pgrep -q oahd; echo $?"), output.trimmingCharacters(in: .whitespacesAndNewlines) == "0" {
            return true
        }
        if let receipt = shell("/usr/sbin/pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1; echo $?") {
            return receipt.trimmingCharacters(in: .whitespacesAndNewlines) == "0"
        }
        return false
    }

    private static func detectQuarantine(on path: String) -> Bool {
        guard !path.isEmpty else { return false }
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return false }
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        if let result = shell("/usr/bin/xattr -p com.apple.quarantine '\(escaped)' >/dev/null 2>&1; echo $?") {
            return result.trimmingCharacters(in: .whitespacesAndNewlines) == "0"
        }
        return false
    }

    private static func inferAppPath(fromWineBinary path: String) -> String? {
        guard !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        let comps = url.pathComponents
        if let idx = comps.firstIndex(of: "Contents"), idx > 0 {
            let appPath = comps.prefix(idx).joined(separator: "/")
            return appPath.hasPrefix("/") ? appPath : "/" + appPath
        }
        return nil
    }

    private static func bundledWineAppCandidates() -> [String] {
        guard let resources = Bundle.main.resourceURL?.path else { return [] }
        return [
            resources + "/EmbeddedWine/Wine Stable.app",
            resources + "/EmbeddedWine/Wine.app"
        ]
    }

    private static func isBundledWinePath(_ path: String) -> Bool {
        guard let resources = Bundle.main.resourceURL?.path else { return false }
        return path.hasPrefix(resources + "/EmbeddedWine/")
    }

    private static func shell(_ command: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
