import AppKit
import Foundation

enum RuntimeInstallerError: LocalizedError {
    case releaseFetchFailed
    case noSuitableAsset(String)
    case downloadFailed(String)
    case fileMoveFailed

    var errorDescription: String? {
        switch self {
        case .releaseFetchFailed:
            return "无法获取安装包发布信息，请检查网络后重试。"
        case .noSuitableAsset(let item):
            return "没有找到适合下载的 \(item) 安装包。"
        case .downloadFailed(let msg):
            return "下载安装包失败：\(msg)"
        case .fileMoveFailed:
            return "下载完成但无法保存安装包到本地目录。"
        }
    }
}

enum RuntimeInstallTarget {
    case wine
    case xquartz
}

enum RuntimeInstaller {
    struct GitHubRelease: Decodable {
        let tagName: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String
        let size: Int?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
        }
    }

    static func downloadLatestInstaller(
        _ target: RuntimeInstallTarget,
        destinationDir: URL,
        preferredArchitecture: String
    ) async throws -> URL {
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        switch target {
        case .wine:
            let release = try await fetchLatestRelease(owner: "Gcenx", repo: "macOS_Wine_builds")
            let asset = chooseWineAsset(from: release.assets, arch: preferredArchitecture)
                ?? chooseGenericInstallerAsset(from: release.assets)
            guard let asset else { throw RuntimeInstallerError.noSuitableAsset("Wine") }
            return try await downloadAsset(asset, destinationDir: destinationDir, prefix: "Wine")
        case .xquartz:
            let release = try await fetchLatestRelease(owner: "XQuartz", repo: "XQuartz")
            let asset = chooseXQuartzAsset(from: release.assets) ?? chooseGenericInstallerAsset(from: release.assets)
            guard let asset else { throw RuntimeInstallerError.noSuitableAsset("XQuartz") }
            return try await downloadAsset(asset, destinationDir: destinationDir, prefix: "XQuartz")
        }
    }

    static func openInstaller(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private static func fetchLatestRelease(owner: String, repo: String) async throws -> GitHubRelease {
        let endpoint = "https://api.github.com/repos/\(owner)/\(repo)/releases/latest"
        guard let url = URL(string: endpoint) else { throw RuntimeInstallerError.releaseFetchFailed }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("VNLauncherZero/0.1", forHTTPHeaderField: "User-Agent")

        let data: Data
        do {
            let (d, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw RuntimeInstallerError.releaseFetchFailed
            }
            data = d
        } catch {
            throw RuntimeInstallerError.downloadFailed(error.localizedDescription)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(GitHubRelease.self, from: data)
        } catch {
            throw RuntimeInstallerError.releaseFetchFailed
        }
    }

    private static func downloadAsset(_ asset: Asset, destinationDir: URL, prefix: String) async throws -> URL {
        guard let url = URL(string: asset.browserDownloadURL) else {
            throw RuntimeInstallerError.downloadFailed("下载地址无效")
        }

        let tempURL: URL
        do {
            var request = URLRequest(url: url)
            request.setValue("VNLauncherZero/0.1", forHTTPHeaderField: "User-Agent")
            let (downloadedURL, response) = try await URLSession.shared.download(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw RuntimeInstallerError.downloadFailed("HTTP \(http.statusCode)")
            }
            tempURL = downloadedURL
        } catch {
            throw RuntimeInstallerError.downloadFailed(error.localizedDescription)
        }

        let safeName = sanitizeFileName(asset.name)
        let targetURL = uniqueDestinationURL(
            in: destinationDir,
            preferredName: safeName.isEmpty ? "\(prefix)-Installer.pkg" : safeName
        )
        do {
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: targetURL)
            return targetURL
        } catch {
            throw RuntimeInstallerError.fileMoveFailed
        }
    }

    private static func chooseWineAsset(from assets: [Asset], arch: String) -> Asset? {
        let normalizedArch = arch.lowercased()
        let installers = assets.filter { isInstallerAssetName($0.name) && $0.name.lowercased().contains("wine") }
        guard !installers.isEmpty else { return nil }

        let preferredKeywords: [String]
        if normalizedArch.contains("arm") {
            preferredKeywords = ["arm64", "apple", "silicon", "universal"]
        } else {
            preferredKeywords = ["x86_64", "intel", "universal"]
        }

        for key in preferredKeywords {
            if let asset = installers.first(where: { $0.name.lowercased().contains(key) }) {
                return asset
            }
        }
        return installers.first
    }

    private static func chooseXQuartzAsset(from assets: [Asset]) -> Asset? {
        let installers = assets.filter { isInstallerAssetName($0.name) && $0.name.lowercased().contains("xquartz") }
        return installers.first ?? assets.first(where: { isInstallerAssetName($0.name) })
    }

    private static func chooseGenericInstallerAsset(from assets: [Asset]) -> Asset? {
        assets.first(where: { isInstallerAssetName($0.name) })
    }

    private static func isInstallerAssetName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".pkg") || lower.hasSuffix(".dmg")
    }

    private static func sanitizeFileName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "_")
    }

    private static func uniqueDestinationURL(in dir: URL, preferredName: String) -> URL {
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent(preferredName)
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var i = 2
        while true {
            let name = ext.isEmpty ? "\(base)-\(i)" : "\(base)-\(i).\(ext)"
            candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }
}

