import Foundation

/// Switch 运行支撑：解析内置模拟器、把用户自备的 keys/固件铺进受管数据目录。
/// 注意：Shiori 只编排"用户自己合法获取的 keys/固件"，绝不打包/分发版权文件。
enum SwitchRuntime {
    /// 内置模拟器：打包进 App 的 Resources/EmbeddedEmulator/*.app（由 build 时提供，运行期只读取）。
    static func resolveBundledEmulator() -> URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let dir = resources.appendingPathComponent("EmbeddedEmulator", isDirectory: true)
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        return items.first(where: { $0.pathExtension.lowercased() == "app" })
    }

    /// 取 .app 内的可执行文件（优先 Info.plist 的 CFBundleExecutable）。
    static func executable(in appURL: URL) -> URL? {
        let fm = FileManager.default
        let macos = appURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        if let plist = NSDictionary(contentsOf: appURL.appendingPathComponent("Contents/Info.plist")),
           let exe = plist["CFBundleExecutable"] as? String {
            let url = macos.appendingPathComponent(exe)
            if fm.isExecutableFile(atPath: url.path) { return url }
        }
        if let items = try? fm.contentsOfDirectory(at: macos, includingPropertiesForKeys: nil) {
            return items.first(where: { fm.isExecutableFile(atPath: $0.path) })
        }
        return nil
    }

    /// 把用户自备的 keys/固件铺进受管数据目录（Ryujinx 系布局）。best-effort，幂等。
    static func prepareDataDir(_ dataDir: URL, keysPath: String, firmwarePath: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: dataDir, withIntermediateDirectories: true)

        // prod.keys -> <data>/system/prod.keys（始终覆盖，确保最新）
        if !keysPath.isEmpty, fm.fileExists(atPath: keysPath) {
            let systemDir = dataDir.appendingPathComponent("system", isDirectory: true)
            try? fm.createDirectory(at: systemDir, withIntermediateDirectories: true)
            let dest = systemDir.appendingPathComponent("prod.keys")
            try? fm.removeItem(at: dest)
            try? fm.copyItem(at: URL(fileURLWithPath: keysPath), to: dest)
        }

        // 固件 -> <data>/bis/...（首次铺设；已存在则跳过，避免每次重拷）
        let bisDst = dataDir.appendingPathComponent("bis", isDirectory: true)
        if !firmwarePath.isEmpty, fm.fileExists(atPath: firmwarePath), !fm.fileExists(atPath: bisDst.path) {
            let src = URL(fileURLWithPath: firmwarePath)
            let bisSrc = src.appendingPathComponent("bis", isDirectory: true)
            if fm.fileExists(atPath: bisSrc.path) {
                // 用户固件目录已是标准 bis 子树，整体复制最忠实
                try? fm.copyItem(at: bisSrc, to: bisDst)
            } else if let ncas = shallowNCAs(in: src, fm: fm), !ncas.isEmpty {
                // 散放的 .nca → registered
                let registered = bisDst.appendingPathComponent("system/Contents/registered", isDirectory: true)
                try? fm.createDirectory(at: registered, withIntermediateDirectories: true)
                for nca in ncas {
                    let dest = registered.appendingPathComponent(nca.lastPathComponent)
                    try? fm.copyItem(at: nca, to: dest)
                }
            }
        }
    }

    private static func shallowNCAs(in folder: URL, fm: FileManager) -> [URL]? {
        guard let en = fm.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        var found: [URL] = []
        var count = 0
        while let u = en.nextObject() as? URL {
            count += 1
            if count > 5000 { break }
            if u.pathExtension.lowercased() == "nca" { found.append(u) }
        }
        return found
    }
}
