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
        var basenames = Set<String>()
        var romURLs: [URL] = []
        var ncaFound = false
        var emulatorApps: [URL] = []
        var launchScripts: [URL] = []

        while let item = enumerator?.nextObject() as? URL {
            let rel = item.path.replacingOccurrences(of: folderURL.path, with: "")
            let depth = rel.split(separator: "/").count
            if depth > 4 {
                enumerator?.skipDescendants()
                continue
            }

            guard let values = try? item.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey]) else { continue }

            // 文件与目录名都纳入反作弊特征比对（反作弊常以独立文件夹或 .sys 驱动形式存在）。
            basenames.insert(item.lastPathComponent.lowercased())

            if values.isDirectory == true {
                // 检测任意 Switch 模拟器 .app（不限 Ryujinx），并跳过其内部以提速。
                if item.pathExtension.lowercased() == "app" {
                    if isEmulatorApp(item) { emulatorApps.append(item) }
                    enumerator?.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true else { continue }

            let ext = item.pathExtension.lowercased()
            if ext == "xp3" { xp3Count += 1 }
            if ext == "exe" { exeURLs.append(item) }
            if ext == "nsp" || ext == "xci" { romURLs.append(item) }
            if ext == "nca" { ncaFound = true }
            if isLaunchScript(item) { launchScripts.append(item) }
        }

        let engineHint: String = xp3Count > 0 ? "KiriKiri/XP3" : "未识别"

        let candidates = exeURLs.map { exe in
            scoreCandidate(exeURL: exe, folderName: folderName)
        }
        .sorted {
            if $0.score == $1.score { return $0.exeURL.lastPathComponent < $1.exeURL.lastPathComponent }
            return $0.score > $1.score
        }

        let antiCheats = detectAntiCheats(in: basenames)

        // —— Switch 判定：依据游戏文件（.nsp/.xci/.nca），与具体模拟器无关 ——
        if !romURLs.isEmpty || ncaFound {
            let script = pickLaunchScript(launchScripts)
            let parsed = script.flatMap { parseLaunchScript($0) }
            let emulatorURL = parsed?.emulator ?? emulatorApps.first
            let emulatorName = emulatorURL.map { $0.deletingPathExtension().lastPathComponent }

            // ROM 复用与 EXE 完全相同的“候选 + 选用”组件；脚本指定的 ROM 置顶。
            var romList: [URL] = []
            if let pr = parsed?.rom { romList.append(pr) }
            for r in romURLs where !romList.contains(r) { romList.append(r) }
            let romCandidates: [ScanCandidate] = romList.enumerated().map { idx, rom in
                let isNsp = rom.pathExtension.lowercased() == "nsp"
                let reason = (idx == 0 && parsed?.rom != nil)
                    ? "启动脚本指定"
                    : (isNsp ? "Switch ROM（.nsp）" : "Switch ROM（.xci）")
                return ScanCandidate(exeURL: rom, score: 100 - idx, reason: reason)
            }

            return ScanResult(
                folderURL: folderURL,
                engineHint: "Nintendo Switch",
                xp3Count: xp3Count,
                exeCandidates: romCandidates,
                antiCheats: antiCheats,
                platform: .switchEmu,
                romURL: romList.first,
                emulatorAppURL: emulatorURL,
                emulatorName: emulatorName,
                launchScriptURL: script
            )
        }

        return ScanResult(
            folderURL: folderURL,
            engineHint: engineHint,
            xp3Count: xp3Count,
            exeCandidates: candidates,
            antiCheats: antiCheats
        )
    }

    // MARK: - Switch 检测辅助（模拟器无关）

    private static let emulatorNamePatterns = [
        "ryujinx", "ryubing", "kenji", "yuzu", "suyu", "sudachi", "citron", "torzu", "eden", "strato"
    ]

    private static func isEmulatorApp(_ url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        return emulatorNamePatterns.contains { name.contains($0) }
    }

    private static func isLaunchScript(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        let exclude = ["install", "build", "setup", "dotnet", "make", "clone", "convert", "update", "patch", "extract", "uninstall"]
        if exclude.contains(where: { name.contains($0) }) { return false }
        if ext == "command" { return true }
        if ext == "sh" {
            let launch = ["启动", "launch", "start", "play", "run", "boot", "游戏", "game"]
            return launch.contains { name.contains($0) }
        }
        return false
    }

    private static func pickLaunchScript(_ scripts: [URL]) -> URL? {
        guard !scripts.isEmpty else { return nil }
        let launchKw = ["启动", "launch", "start", "play", "run", "游戏", "game"]
        func score(_ u: URL) -> Int {
            let n = u.deletingPathExtension().lastPathComponent.lowercased()
            var s = 0
            if launchKw.contains(where: { n.contains($0) }) { s += 10 }
            if u.pathExtension.lowercased() == "command" { s += 5 }
            return s
        }
        return scripts.sorted { score($0) > score($1) }.first
    }

    /// 解析脚本里的 EMULATOR= / GAME=（兼容用户现成的一键启动脚本）。
    private static func parseLaunchScript(_ url: URL) -> (rom: URL?, emulator: URL?)? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        func value(_ key: String) -> String? {
            for line in text.split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix(key + "=") {
                    let raw = String(t.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
                    let v = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    return v.isEmpty ? nil : v
                }
            }
            return nil
        }
        let fm = FileManager.default
        let emu = value("EMULATOR").flatMap { fm.fileExists(atPath: $0) ? URL(fileURLWithPath: $0) : nil }
        let rom = value("GAME").flatMap { fm.fileExists(atPath: $0) ? URL(fileURLWithPath: $0) : nil }
        if emu == nil && rom == nil { return nil }
        return (rom, emu)
    }

    /// 依据已知反作弊的特征文件 / 目录名识别，区分「内核级无解」与「Linux/Proton 有限可行」两档。
    private static func detectAntiCheats(in names: Set<String>) -> [AntiCheatHit] {
        struct Signature {
            let name: String
            let severity: AntiCheatSeverity
            let advice: String
            var contains: [String] = []
            var exact: [String] = []
            var prefixes: [String] = []
        }

        let kernelAdvice = "内核级反作弊：需加载 Windows 内核驱动，而 Wine 没有 NT 内核可供加载，macOS 也不允许安装该驱动，且它会主动检测并拒绝 Wine / 虚拟机环境。无官方或可靠的变通方案。"
        let protonAdvice = "内核级反作弊：部分游戏经开发者开启后可在 Linux/Proton 运行，但 macOS 上仅能借助 CrossOver 等逐个尝试，成功率很低。"

        let signatures: [Signature] = [
            Signature(name: "ACE 反作弊专家（腾讯）", severity: .blocking, advice: kernelAdvice,
                      contains: ["anticheatexpert", "sguard", "tenprotect", "tensafe", "tprotect"],
                      exact: ["ace-base.sys"], prefixes: ["ace-drv", "ace-base"]),
            Signature(name: "Riot Vanguard", severity: .blocking, advice: kernelAdvice,
                      exact: ["vgc.exe", "vgk.sys", "vgtray.exe"]),
            Signature(name: "XIGNCODE3", severity: .blocking, advice: kernelAdvice,
                      contains: ["xigncode", "xhunter"], exact: ["x3.xem", "xmag.xem"]),
            Signature(name: "nProtect GameGuard", severity: .blocking, advice: kernelAdvice,
                      contains: ["gameguard"], exact: ["npggnt.des", "gamemon.des"], prefixes: ["npgg"]),
            Signature(name: "mhyprot（米哈游 / HoYoverse）", severity: .blocking, advice: kernelAdvice,
                      contains: ["mhyprot", "hoyoprotect"]),
            Signature(name: "Easy Anti-Cheat (EAC)", severity: .unlikely, advice: protonAdvice,
                      contains: ["easyanticheat"]),
            Signature(name: "BattlEye", severity: .unlikely, advice: protonAdvice,
                      contains: ["battleye", "bedaisy", "beservice"], prefixes: ["beclient"])
        ]

        var hits: [AntiCheatHit] = []
        for sig in signatures {
            let evidence = names.filter { name in
                sig.exact.contains(name)
                    || sig.contains.contains(where: { name.contains($0) })
                    || sig.prefixes.contains(where: { name.hasPrefix($0) })
            }
            if !evidence.isEmpty {
                let trimmed = Array(evidence.sorted().prefix(4))
                hits.append(AntiCheatHit(name: sig.name, severity: sig.severity, evidence: trimmed, advice: sig.advice))
            }
        }

        return hits.sorted { lhs, rhs in
            (lhs.severity == .blocking ? 0 : 1) < (rhs.severity == .blocking ? 0 : 1)
        }
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
