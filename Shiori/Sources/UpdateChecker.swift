import Foundation

/// 应用品牌与版本信息（单一真相源）。
enum AppInfo {
    static let name = "栞 Shiori"
    static let subtitle = "exe · galgame · switch · lightweight games for macOS"

    /// 运行版本：优先取打包后 Info.plist 的 CFBundleShortVersionString，开发期回退常量。
    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }

    static let repoOwner = "jojocys"
    static let repoName = "gal-for-MacOS"
    /// 版本清单在仓库中的相对路径（应用位于 Shiori/ 子目录）。
    static let manifestPath = "Shiori/version.json"
    /// 分支名。
    static let branch = "main"

    static var isRepoConfigured: Bool {
        repoOwner != "OWNER" && repoName != "REPO"
    }

    static var updateManifestURL: URL? {
        URL(string: "https://raw.githubusercontent.com/\(repoOwner)/\(repoName)/\(branch)/\(manifestPath)")
    }

    static var releasesPageURL: URL? {
        URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest")
    }
}

/// 仓库里 version.json 的结构：push 时改 version 即可触发用户端检测。
struct UpdateManifest: Codable {
    let version: String
    let notes: String?
    let url: String?
}

struct UpdateState: Equatable {
    enum Phase: Equatable {
        case idle, checking, upToDate, available, failed
    }

    var phase: Phase = .idle
    var latestVersion: String = ""
    var notes: String = ""
    var downloadURL: String = ""
    var message: String = ""

    var isAvailable: Bool { phase == .available }
}

enum UpdateChecker {
    static func fetch() async -> UpdateState {
        guard AppInfo.isRepoConfigured, let url = AppInfo.updateManifestURL else {
            return UpdateState(phase: .idle, message: "未配置更新源（请在 AppInfo 填入 GitHub 仓库）。")
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12
        request.setValue("Shiori/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return UpdateState(phase: .failed, message: "检查更新失败（服务器无响应）。")
            }
            let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
            let latest = manifest.version.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackURL = AppInfo.releasesPageURL?.absoluteString ?? ""

            if isNewer(latest, than: AppInfo.version) {
                return UpdateState(
                    phase: .available,
                    latestVersion: latest,
                    notes: manifest.notes ?? "",
                    downloadURL: manifest.url?.isEmpty == false ? manifest.url! : fallbackURL,
                    message: "发现新版本 \(latest)（当前 \(AppInfo.version)）"
                )
            } else {
                return UpdateState(
                    phase: .upToDate,
                    latestVersion: latest,
                    message: "已是最新版本（\(AppInfo.version)）"
                )
            }
        } catch {
            return UpdateState(phase: .failed, message: "检查更新失败：\(error.localizedDescription)")
        }
    }

    /// 语义化版本比较：逐段数字比较，缺位补 0，忽略 v 前缀与预发布后缀。
    static func isNewer(_ remote: String, than local: String) -> Bool {
        let r = parse(remote)
        let l = parse(local)
        let count = max(r.count, l.count)
        for i in 0..<count {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }

    private static func parse(_ version: String) -> [Int] {
        version
            .split(whereSeparator: { $0 == "." || $0 == "-" || $0 == "+" })
            .map { Int($0.filter(\.isNumber)) ?? 0 }
    }
}
