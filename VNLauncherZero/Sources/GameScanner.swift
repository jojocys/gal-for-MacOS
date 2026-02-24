import Foundation

enum GameScanner {
    static func scanGameFolder(_ folderURL: URL) -> ScanResult {
        let fm = FileManager.default
        let folderName = folderURL.lastPathComponent.lowercased()

        let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        )

        var xp3Count = 0
        var exeURLs: [URL] = []

        while let item = enumerator?.nextObject() as? URL {
            let rel = item.path.replacingOccurrences(of: folderURL.path, with: "")
            let depth = rel.split(separator: "/").count
            if depth > 4 {
                enumerator?.skipDescendants()
                continue
            }

            guard let values = try? item.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey]) else { continue }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else { continue }

            let ext = item.pathExtension.lowercased()
            if ext == "xp3" { xp3Count += 1 }
            if ext == "exe" { exeURLs.append(item) }
        }

        let engineHint: String = xp3Count > 0 ? "KiriKiri/XP3" : "未识别"

        let candidates = exeURLs.map { exe in
            scoreCandidate(exeURL: exe, folderName: folderName)
        }
        .sorted {
            if $0.score == $1.score { return $0.exeURL.lastPathComponent < $1.exeURL.lastPathComponent }
            return $0.score > $1.score
        }

        return ScanResult(folderURL: folderURL, engineHint: engineHint, xp3Count: xp3Count, exeCandidates: candidates)
    }

    private static func scoreCandidate(exeURL: URL, folderName: String) -> ScanCandidate {
        let name = exeURL.deletingPathExtension().lastPathComponent.lowercased()
        let file = exeURL.lastPathComponent.lowercased()
        var score = 100
        var reasons: [String] = []

        if name == folderName { score += 60; reasons.append("与文件夹同名") }
        if name.replacingOccurrences(of: " ", with: "") == folderName.replacingOccurrences(of: " ", with: "") {
            score += 30
            reasons.append("与文件夹名接近")
        }

        let penalties: [(String, Int, String)] = [
            ("crack", -90, "疑似破解片头"),
            ("intro", -70, "疑似片头程序"),
            ("tro", -70, "疑似片头程序"),
            ("setup", -100, "安装程序"),
            ("install", -100, "安装程序"),
            ("unins", -100, "卸载程序"),
            ("config", -60, "配置程序"),
            ("launcher", -35, "通用启动器"),
            ("dx", -30, "组件工具"),
            ("patch", -60, "补丁程序")
        ]
        for (needle, delta, desc) in penalties where name.contains(needle) || file.contains(needle) {
            score += delta
            reasons.append(desc)
        }

        let depth = exeURL.pathComponents.count
        score -= min(depth, 20)
        if name.count <= 20 { score += 10 }

        if reasons.isEmpty { reasons.append("常规候选") }
        return ScanCandidate(exeURL: exeURL, score: score, reason: reasons.joined(separator: " / "))
    }
}
