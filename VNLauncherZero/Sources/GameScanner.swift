import Foundation

enum GameScanner {
    static func scan(folderURL: URL) -> GameScanResult {
        let fm = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        var exeCandidates: [EXECandidate] = []
        var xp3Count = 0
        var hasRenpy = false
        var hasUnity = false
        var notes: [String] = []

        let folderName = folderURL.lastPathComponent.lowercased()
        let folderTokens = tokenize(folderName)

        while let item = enumerator?.nextObject() as? URL {
            guard let values = try? item.resourceValues(forKeys: resourceKeys) else { continue }
            if values.isDirectory == true {
                if item.pathComponents.count - folderURL.pathComponents.count > 2 {
                    enumerator?.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true else { continue }

            let ext = item.pathExtension.lowercased()
            let fileName = item.lastPathComponent
            let lowerName = fileName.lowercased()

            if ext == "xp3" { xp3Count += 1 }
            if lowerName == "renpy.exe" || lowerName.hasSuffix(".rpy") { hasRenpy = true }
            if lowerName == "unityplayer.dll" || lowerName == "unitycrashhandler64.exe" { hasUnity = true }

            guard ext == "exe" else { continue }
            let scoreInfo = scoreExecutable(fileName: lowerName, folderTokens: folderTokens, folderName: folderName)
            let candidate = EXECandidate(path: item.path, score: scoreInfo.score, reason: scoreInfo.reason)
            exeCandidates.append(candidate)
        }

        exeCandidates.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName) == .orderedAscending
        }

        let engine: GameEngine = {
            if xp3Count >= 3 { return .kirikiri }
            if hasRenpy { return .renpy }
            if hasUnity { return .unity }
            return .unknown
        }()

        if engine == .kirikiri {
            notes.append("检测到多个 .xp3 资源包，疑似 KiriKiri/XP3。")
            notes.append("已自动降低 cracktro/setup/config 等可疑启动器优先级。")
        }
        if let first = exeCandidates.first {
            notes.append("推荐主程序：\(URL(fileURLWithPath: first.path).lastPathComponent)")
        } else {
            notes.append("未找到 .exe 文件，请确认游戏目录完整。")
        }

        return GameScanResult(
            folderPath: folderURL.path,
            engine: engine,
            recommendedEXEPath: exeCandidates.first?.path,
            candidates: exeCandidates,
            notes: notes,
            xp3Count: xp3Count
        )
    }

    private static func tokenize(_ text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func scoreExecutable(fileName: String, folderTokens: [String], folderName: String) -> (score: Int, reason: String) {
        var score = 0
        var reasons: [String] = []

        let bare = (fileName as NSString).deletingPathExtension
        let tokens = tokenize(bare)

        if bare == folderName {
            score += 120
            reasons.append("与目录名完全匹配")
        }

        let overlaps = Set(tokens).intersection(folderTokens).count
        if overlaps > 0 {
            let delta = overlaps * 25
            score += delta
            reasons.append("与目录名相似 +\(delta)")
        }

        let strongPositive = ["game", "start", "play"]
        for key in strongPositive where bare.contains(key) {
            score += 10
            reasons.append("常见主程序命名")
        }

        let negativeKeywords: [(String, Int, String)] = [
            ("crack", -140, "疑似破解辅助程序"),
            ("tro", -80, "疑似片头/破解程序"),
            ("cracktro", -200, "疑似破解展示程序"),
            ("keygen", -200, "序列号生成器"),
            ("patch", -120, "补丁程序"),
            ("setup", -120, "安装器"),
            ("install", -120, "安装器"),
            ("unins", -160, "卸载程序"),
            ("uninstall", -160, "卸载程序"),
            ("config", -80, "配置工具"),
            ("launcher", -40, "启动器（不一定是主程序）"),
            ("dxsetup", -200, "运行库安装器")
        ]

        for (key, delta, note) in negativeKeywords where bare.contains(key) {
            score += delta
            reasons.append(note)
        }

        if bare.hasSuffix("_config") {
            score -= 100
            reasons.append("配置工具")
        }

        if reasons.isEmpty {
            reasons.append("普通 EXE 候选")
        }
        return (score, reasons.joined(separator: "，"))
    }
}

