import AppKit
import Foundation

struct RuntimeInstaller {
    enum InstallerKind {
        case wine
        case xquartz

        var displayName: String {
            switch self {
            case .wine: return "Wine"
            case .xquartz: return "XQuartz"
            }
        }

        var fallbackURL: URL {
            switch self {
            case .wine:
                return URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/latest")!
            case .xquartz:
                return URL(string: "https://github.com/XQuartz/XQuartz/releases/latest")!
            }
        }

        var candidateRepos: [(owner: String, repo: String)] {
            switch self {
            case .wine:
                return [("Gcenx", "macOS_Wine_builds")]
            case .xquartz:
                return [("XQuartz", "XQuartz")]
            }
        }

        var allowedExtensions: Set<String> { ["pkg", "dmg"] }
    }

    private struct GitHubRelease: Decodable {
        let assets: [GitHubAsset]
        let html_url: String
    }

    private struct GitHubAsset: Decodable {
        let name: String
        let browser_download_url: String
    }

    static func downloadLatestInstaller(kind: InstallerKind) async throws -> InstallerDownloadResult {
        let fm = FileManager.default
        let dir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".vnlauncher", isDirectory: true)
            .appendingPathComponent("downloads", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let session = URLSession(configuration: .default)
        var selectedAssetURL: URL?

        for repo in kind.candidateRepos {
            let apiURL = URL(string: "https://api.github.com/repos/\(repo.owner)/\(repo.repo)/releases/latest")!
            var req = URLRequest(url: apiURL)
            req.setValue("GAL-FOR-MacOS/1.0", forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await session.data(for: req)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { continue }
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                if let asset = chooseAsset(from: release.assets, kind: kind) {
                    selectedAssetURL = URL(string: asset.browser_download_url)
                    break
                }
            } catch {
                continue
            }
        }

        guard let sourceURL = selectedAssetURL else {
            NSWorkspace.shared.open(kind.fallbackURL)
            throw NSError(domain: "RuntimeInstaller", code: 1, userInfo: [NSLocalizedDescriptionKey: "未找到可下载安装包，已为你打开官方发布页。"])
        }

        var downloadReq = URLRequest(url: sourceURL)
        downloadReq.setValue("GAL-FOR-MacOS/1.0", forHTTPHeaderField: "User-Agent")
        let (tmpURL, response) = try await session.download(for: downloadReq)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "RuntimeInstaller", code: 2, userInfo: [NSLocalizedDescriptionKey: "下载安装包失败（网络或服务器返回异常）。"])
        }

        let targetURL = dir.appendingPathComponent(sourceURL.lastPathComponent)
        try? fm.removeItem(at: targetURL)
        try fm.moveItem(at: tmpURL, to: targetURL)
        NSWorkspace.shared.open(targetURL)
        return InstallerDownloadResult(downloadedFileURL: targetURL, sourceURL: sourceURL)
    }

    private static func chooseAsset(from assets: [GitHubAsset], kind: InstallerKind) -> GitHubAsset? {
        let filtered = assets.filter { asset in
            let ext = URL(fileURLWithPath: asset.name).pathExtension.lowercased()
            return kind.allowedExtensions.contains(ext)
        }

        let scored = filtered.map { asset -> (GitHubAsset, Int) in
            let name = asset.name.lowercased()
            var score = 0
            if name.contains("mac") || name.contains("osx") || name.contains("darwin") { score += 30 }
            if name.contains("arm64") || name.contains("apple") || name.contains("silicon") { score += 20 }
            if name.contains("stable") { score += 10 }
            if name.contains("debug") { score -= 20 }
            if name.contains("symbols") { score -= 50 }
            return (asset, score)
        }

        return scored.sorted { lhs, rhs in
            if lhs.1 == rhs.1 { return lhs.0.name < rhs.0.name }
            return lhs.1 > rhs.1
        }.first?.0
    }
}
