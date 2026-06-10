import AppKit
import SwiftUI

// MARK: - UI model helpers

/// 外观偏好：跟随系统 / 浅色 / 深色。持久化于 @AppStorage。
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// 侧栏顶层入口：Wine Steam 与「我的游戏」同级。
enum SidebarItem: Hashable {
    case steam
    case game(UUID)
}

/// 游戏详情内的次级标签。运行环境通常只用一次，作为次级页签。
enum GameSection: String, CaseIterable, Identifiable {
    case setup    // P1 选择游戏（频繁）
    case runtime  // P2 运行环境（一次性）

    var id: String { rawValue }

    var title: String {
        switch self {
        case .setup: return "游戏设置"
        case .runtime: return "运行环境"
        }
    }

    var symbol: String {
        switch self {
        case .setup: return "folder"
        case .runtime: return "gearshape.2"
        }
    }
}

struct RootView: View {
    @ObservedObject var store: AppStore

    @AppStorage("ui.appearance") private var appearanceRaw = AppearancePreference.system.rawValue
    @State private var sidebarSelection: SidebarItem?
    @State private var gameSection: GameSection = .setup
    @State private var showDeleteConfirm = false

    private var appearance: AppearancePreference {
        AppearancePreference(rawValue: appearanceRaw) ?? .system
    }

    private var updateHelp: String {
        switch store.updateState.phase {
        case .available: return "有新版本 \(store.updateState.latestVersion)，点击下载"
        case .checking: return "正在检查更新…"
        case .upToDate: return "已是最新版本"
        case .failed: return "检查更新失败，点击重试"
        case .idle: return "检查更新"
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1120, minHeight: 720)
        .preferredColorScheme(appearance.colorScheme)
        .toolbar { toolbarContent }
        .confirmationDialog("删除当前配置？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) { store.removeSelectedGame() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只删除配置记录，不删除游戏文件。")
        }
        .onAppear(perform: syncInitialSelection)
        .task { await store.checkForUpdates() }
        .onChange(of: store.selectedGameID) { newID in
            // 列表变化（如删除）后保持侧栏与 store 同步，但不打断 Steam 视图。
            if case .game = sidebarSelection {
                sidebarSelection = newID.map(SidebarItem.game)
            } else if sidebarSelection == nil {
                sidebarSelection = newID.map(SidebarItem.game)
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                store.addEmptyGame()
            } label: {
                Image(systemName: "plus")
            }
            .help("新建配置")

            Button {
                store.load()
                store.refreshRuntimeStatus()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("刷新")

            Button {
                if store.updateState.isAvailable {
                    store.openReleasesPage()
                } else {
                    Task { await store.checkForUpdates(userInitiated: true) }
                }
            } label: {
                if store.updateState.isAvailable {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.tint)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
            .help(updateHelp)
            .disabled(store.updateState.phase == .checking)

            Menu {
                Picker("外观", selection: $appearanceRaw) {
                    ForEach(AppearancePreference.allCases) { pref in
                        Label(pref.title, systemImage: pref.symbol).tag(pref.rawValue)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: appearance.symbol)
            }
            .help("浅色 / 深色主题")
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            brandHeader

            if store.updateState.isAvailable {
                updateBanner
            }

            List(selection: sidebarBinding) {
                Section {
                    steamRow.tag(SidebarItem.steam)
                }

                Section("我的游戏") {
                    ForEach(store.games) { game in
                        gameRow(game).tag(SidebarItem.game(game.id))
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            sidebarFooter
        }
        .frame(minWidth: 264)
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "gamecontroller.fill")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(AppInfo.name)
                    .font(.headline)
                Text(AppInfo.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var steamRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "s.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Wine Steam")
                    .font(.headline)
                Text("独立客户端入口")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func gameRow(_ game: GameEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "puzzlepiece.fill")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(game.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(game.displaySubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(game.engineHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
    }

    private var sidebarFooter: some View {
        VStack(spacing: 8) {
            Button {
                store.addEmptyGame()
            } label: {
                Label("新建配置", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack {
                Text("共 \(store.games.count) 个配置 · v\(AppInfo.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("刷新") {
                    store.load()
                    store.refreshRuntimeStatus()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(12)
    }

    private var updateBanner: some View {
        Button {
            store.openReleasesPage()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("有新版本 \(store.updateState.latestVersion)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("点击前往下载")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: Detail switch

    @ViewBuilder
    private var detail: some View {
        switch sidebarSelection {
        case .steam:
            steamDetail
        case .game:
            gameDetail
        case .none:
            emptyDetail
        }
    }

    private var emptyDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("从左侧选择一个游戏，或打开 Wine Steam")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Game detail

    private var gameDetail: some View {
        VStack(spacing: 0) {
            gameHeader
            Divider()

            Picker("", selection: $gameSection) {
                ForEach(GameSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            ScrollView {
                VStack(spacing: 18) {
                    switch gameSection {
                    case .setup:   setupContent
                    case .runtime: runtimeContent
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            statusBar
        }
    }

    /// 头部：常驻的「启动」重点区。开始游戏为最大主操作。
    private var gameHeader: some View {
        let game = store.selectedGame
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(game?.name ?? "未选择")
                    .font(.system(size: 28, weight: .bold))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    enginePill(game?.engineHint ?? "未识别")
                    Text(exeDisplay(game))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack(spacing: 10) {
                    Text("语言")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("启动语言", selection: launchLanguageBinding) {
                        ForEach(LaunchLanguageMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                    .disabled(game == nil)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 10) {
                Button {
                    store.startGame()
                } label: {
                    Label("开始游戏", systemImage: "play.fill")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(game == nil)

                HStack(spacing: 8) {
                    Button {
                        store.openLastLog()
                    } label: {
                        Label("日志", systemImage: "doc.text")
                    }
                    .controlSize(.small)
                    .disabled(store.lastLogPath.isEmpty)

                    Button {
                        store.openSelectedGameFolder()
                    } label: {
                        Label("目录", systemImage: "folder")
                    }
                    .controlSize(.small)
                    .disabled(game == nil)

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .controlSize(.small)
                    .disabled(game == nil)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: P1 设置内容

    private var setupContent: some View {
        VStack(spacing: 18) {
            if let scan = store.scanResult, !scan.antiCheats.isEmpty {
                antiCheatBanner(scan.antiCheats)
            }

            card {
                VStack(alignment: .leading, spacing: 14) {
                    sectionTitle("选择游戏", subtitle: "选择整个游戏目录，自动扫描并推荐主程序。")

                    // 主操作：选择文件夹（大）
                    Button {
                        store.chooseAndScanGameFolder()
                    } label: {
                        Label("选择游戏文件夹", systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut("o", modifiers: [.command])

                    // 次级操作（中）
                    HStack(spacing: 10) {
                        Button {
                            store.rescanCurrentFolder()
                        } label: {
                            Label("重新扫描", systemImage: "arrow.clockwise")
                        }
                        Button {
                            store.chooseEXEManually()
                        } label: {
                            Label("手动选择 EXE", systemImage: "doc")
                        }
                    }

                    labeledField("配置名称") {
                        TextField("例如：Senren Banka", text: nameBinding)
                            .textFieldStyle(.roundedBorder)
                    }

                    labeledField("当前目录") {
                        Text(store.selectedGame?.gameFolderPath.isEmpty == false
                             ? (store.selectedGame?.gameFolderPath ?? "")
                             : "尚未选择")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if let scan = store.scanResult {
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            sectionTitle("扫描结果", subtitle: nil)
                            Spacer()
                            statBadge("引擎", scan.engineHint)
                            statBadge("XP3", "\(scan.xp3Count)")
                            statBadge("候选", "\(scan.exeCandidates.count)")
                        }

                        ForEach(Array(scan.exeCandidates.prefix(5))) { candidate in
                            candidateRow(candidate)
                        }
                    }
                }
            }

            card {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("路径", subtitle: nil)
                    pathRow(title: "推荐 EXE", value: store.selectedGame?.exePath ?? "") {
                        Button("选择") { store.chooseEXEManually() }
                            .controlSize(.small)
                    }
                    pathRow(title: "Wine Prefix", value: store.selectedGame?.prefixDir ?? "") {
                        Button("选择") { store.choosePrefixFolder() }
                            .controlSize(.small)
                    }

                    Button {
                        store.saveCurrentFromP1()
                    } label: {
                        Label("保存到游戏列表", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 2)
                }
            }
        }
    }

    private func candidateRow(_ candidate: ScanCandidate) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.exeURL.lastPathComponent)
                    .font(.body.weight(.medium))
                Text(candidate.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(candidate.exeURL.path)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text("\(candidate.score)")
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .foregroundStyle(.secondary)
            Button("选用") { store.applyRecommendedCandidate(candidate) }
                .controlSize(.small)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func antiCheatBanner(_ hits: [AntiCheatHit]) -> some View {
        let blocking = hits.contains { $0.severity == .blocking }
        let accent: Color = blocking ? .red : .orange
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(accent)
                Text(blocking ? "检测到内核级反作弊 · macOS 无法运行" : "检测到反作弊 · macOS 上几乎无法运行")
                    .font(.headline)
                Spacer()
            }

            ForEach(hits) { hit in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(hit.name)
                            .font(.callout.weight(.semibold))
                        Text(hit.severity.headline)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill((hit.severity == .blocking ? Color.red : Color.orange).opacity(0.18)))
                            .foregroundStyle(hit.severity == .blocking ? Color.red : Color.orange)
                    }
                    Text(hit.advice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !hit.evidence.isEmpty {
                        Text("特征文件：" + hit.evidence.joined(separator: "、"))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accent.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: P2 运行环境内容

    private var runtimeContent: some View {
        VStack(spacing: 18) {
            card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        sectionTitle("运行环境检测", subtitle: "检测内置 Wine / Rosetta / XQuartz / Gatekeeper。通常只需一次。")
                        Spacer()
                        Button {
                            store.refreshRuntimeStatus(userInitiated: true)
                        } label: {
                            Label("重新检测", systemImage: "arrow.clockwise")
                        }
                        .controlSize(.small)
                    }

                    ForEach(store.runtimeReport.items) { item in
                        runtimeRow(item)
                    }
                }
            }

            card {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("修复与设置", subtitle: nil)
                    HStack(spacing: 10) {
                        Button {
                            store.installEmbeddedXQuartz()
                        } label: {
                            Label("安装内置 XQuartz", systemImage: "arrow.down.app")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            store.openPrivacySettings()
                        } label: {
                            Label("隐私与安全性", systemImage: "lock.shield")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            store.openRepairGuide()
                        } label: {
                            Label("一键修复引导", systemImage: "wand.and.stars")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func runtimeRow(_ item: RuntimeCheckItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(color(for: item.state))
                .frame(width: 12, height: 12)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.body.weight(.medium))
                Text(item.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(item.state.label)
                .font(.callout.weight(.semibold))
                .foregroundStyle(color(for: item.state))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: Steam detail（与「我的游戏」同级的主入口）

    private var steamDetail: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Wine Steam")
                        .font(.system(size: 28, weight: .bold))
                    Text("直接打开 Wine 版 Steam 客户端，不依赖当前游戏配置。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    store.launchWineSteamEntry()
                } label: {
                    Label("启动 Steam 客户端", systemImage: "play.fill")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(spacing: 18) {
                    card {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionTitle("客户端管理", subtitle: nil)
                            HStack(spacing: 10) {
                                Button {
                                    store.downloadAndOpenWineSteamInstaller()
                                } label: {
                                    Label("下载 Wine Steam", systemImage: "arrow.down.circle")
                                }
                                .buttonStyle(.bordered)
                                .disabled(store.isDownloadingInstaller)

                                if store.isDownloadingInstaller {
                                    ProgressView().controlSize(.small)
                                }

                                Spacer()

                                Button(role: .destructive) {
                                    store.stopWineSteamProcesses()
                                } label: {
                                    Label("关闭进程", systemImage: "power")
                                }
                                .controlSize(.small)
                            }

                            if !store.downloadStatusText.isEmpty {
                                Text(store.downloadStatusText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    card {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionTitle("说明", subtitle: nil)
                            ForEach(Array(store.wineSteamTips.enumerated()), id: \.offset) { _, tip in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "info.circle")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                        .padding(.top, 2)
                                    Text(tip)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            statusBar
        }
    }

    // MARK: Status bar（补上此前从未显示的 statusMessage）

    private var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(store.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: Reusable building blocks

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }

    private func sectionTitle(_ title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func enginePill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            .foregroundStyle(.tint)
    }

    private func statBadge(_ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    private func pathRow<Trailing: View>(title: String, value: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value.isEmpty ? "尚未设置" : value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func color(for state: RuntimeCheckItem.State) -> Color {
        switch state {
        case .ok: return .green
        case .bundled: return .blue
        case .warning: return .yellow
        case .missing: return .orange
        case .blocked: return .red
        }
    }

    private func exeDisplay(_ game: GameEntry?) -> String {
        guard let game, !game.exePath.isEmpty else { return "尚未选择主程序" }
        return game.exePath
    }

    // MARK: Bindings & selection sync

    private var sidebarBinding: Binding<SidebarItem?> {
        Binding(
            get: { sidebarSelection },
            set: { newValue in
                sidebarSelection = newValue
                if case .game(let id) = newValue {
                    store.selectGame(id)
                }
            }
        )
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { store.selectedGame?.name ?? "" },
            set: { store.renameSelectedGame($0) }
        )
    }

    private var launchLanguageBinding: Binding<LaunchLanguageMode> {
        Binding(
            get: { store.selectedGame?.launchLanguageMode ?? .auto },
            set: { store.setSelectedLaunchLanguage($0) }
        )
    }

    private func syncInitialSelection() {
        if sidebarSelection == nil {
            sidebarSelection = store.selectedGameID.map(SidebarItem.game) ?? .steam
        }
    }
}
