import AppKit
import SwiftUI

struct RootView: View {
    @ObservedObject var store: AppStore
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationSplitView {
            SidebarPanel(store: store, showDeleteConfirm: $showDeleteConfirm)
                .navigationSplitViewColumnWidth(min: 280, ideal: 300, max: 360)
        } detail: {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HeroHeader(store: store)
                        P1GameSelectionCard(store: store)
                        P2RuntimeCard(store: store)
                        P3LaunchCard(store: store)
                    }
                    .padding(20)
                    .frame(maxWidth: 980, alignment: .leading)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .confirmationDialog("删除当前游戏配置？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) { store.removeSelectedGame() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只删除启动器中的配置，不会删除游戏文件。")
        }
    }
}

private struct SidebarPanel: View {
    @ObservedObject var store: AppStore
    @Binding var showDeleteConfirm: Bool

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text("已保存游戏")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 4)

                List(selection: selectionBinding) {
                    ForEach(store.games) { game in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(game.name.isEmpty ? "未命名游戏" : game.name)
                                .font(.headline)
                                .lineLimit(1)
                            Text(game.displaySubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(game.engine.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .tag(game.id)
                        .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(.clear)

                VStack(spacing: 10) {
                    Button {
                        store.selectedWizardStep = .p1
                        store.chooseAndScanGameFolder()
                    } label: {
                        Label("添加游戏文件夹", systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)

                    Button {
                        store.revealSelectedGameFolder()
                    } label: {
                        Text("打开游戏文件夹")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.selectedGame == nil)

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Text("删除当前配置")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.selectedGame == nil)
                }

                Spacer(minLength: 0)

                Text("共 \(store.games.count) 个配置")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
    }

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { store.selectedGameID },
            set: { store.selectGame($0) }
        )
    }
}

private struct HeroHeader: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("GAL FOR MacOS")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("支持在Mac上运行轻量级exe文件")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Button {
                    store.autoFixGuidance()
                } label: {
                    Label("一键修复引导", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent2)
            }

            HStack(spacing: 10) {
                StepBadge(title: "P1", text: "选择游戏", active: store.selectedWizardStep == .p1)
                StepBadge(title: "P2", text: "运行环境", active: store.selectedWizardStep == .p2)
                StepBadge(title: "P3", text: "启动游戏", active: store.selectedWizardStep == .p3)
            }

        }
        .glassCard()
    }
}

private struct StepBadge: View {
    var title: String
    var text: String
    var active: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(.white.opacity(active ? 0.95 : 0.82))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.05))
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(active ? 0.12 : 0.08), lineWidth: 1)
        )
        .clipShape(Capsule())
    }
}

private struct P1GameSelectionCard: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(icon: "1.circle.fill", title: "P1 选择游戏文件夹（自动识别主程序）")

            Text("推荐做法：直接选择整个游戏目录，启动器会自动扫描 `.exe` 并优先推荐真正的主程序。")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.78))

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    labeledPath("当前目录", store.scanResult?.folderPath ?? "尚未选择")
                    HStack(spacing: 8) {
                        Button {
                            store.selectedWizardStep = .p1
                            store.chooseAndScanGameFolder()
                        } label: {
                            Label("选择游戏文件夹", systemImage: "folder")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)

                        Button {
                            if let path = store.scanResult?.folderPath {
                                store.scanGameFolder(URL(fileURLWithPath: path))
                            }
                        } label: {
                            Label("重新扫描", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.scanResult == nil)
                    }
                }

                Spacer()

                VStack(alignment: .leading, spacing: 6) {
                    statusChip(title: "识别引擎", value: store.scanResult?.engine.rawValue ?? "未识别")
                    statusChip(title: "XP3 数量", value: store.scanResult.map { "\($0.xp3Count)" } ?? "-")
                    statusChip(title: "候选 EXE", value: store.scanResult.map { "\($0.candidates.count)" } ?? "-")
                }
            }

            if let scan = store.scanResult {
                VStack(alignment: .leading, spacing: 10) {
                    Text("推荐主程序")
                        .font(.headline)
                        .foregroundStyle(.white)
                    HStack {
                        Text(store.recommendedOrChosenEXEPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "未识别")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        Button("手动选择 EXE") {
                            store.manuallyChooseEXEForScannedFolder()
                        }
                        .buttonStyle(.bordered)
                    }
                    labeledPath("EXE 路径", store.recommendedOrChosenEXEPath ?? "未选择")

                    if !scan.candidates.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("候选列表（按优先级排序）")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.9))
                            ForEach(Array(scan.candidates.prefix(5))) { candidate in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(candidate.fileName)
                                        .font(.system(.callout, design: .monospaced))
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text("分数 \(candidate.score)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(candidate.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, -2)
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
                    }

                    if !scan.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(scan.notes, id: \.self) { note in
                                Label(note, systemImage: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    HStack {
                        Button {
                            store.saveScannedGameProfile()
                        } label: {
                            Label("保存到游戏列表（进入 P2）", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)
                        .disabled(store.recommendedOrChosenEXEPath == nil)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.03)))
            }
        }
        .glassCard()
    }

    private func sectionTitle(icon: String, title: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.accent2)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
        }
    }

    private func labeledPath(_ label: String, _ path: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(path)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }

    private func statusChip(title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }
}

private struct P2RuntimeCard: View {
    @ObservedObject var store: AppStore
    @State private var showGuideSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "2.circle.fill")
                    .foregroundStyle(AppTheme.accent2)
                Text("P2 运行环境（无需命令行，图形化引导）")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    store.selectedWizardStep = .p2
                    store.refreshRuntime()
                } label: {
                    Label("重新检测", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            Text("这里会检测 `Wine / Rosetta / XQuartz / Gatekeeper`。你可以直接点按钮打开官网或系统设置，不需要终端命令。")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.78))

            VStack(spacing: 10) {
                ForEach(Array(store.runtimeReport.components.enumerated()), id: \.offset) { _, component in
                    RuntimeComponentRow(component: component)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("已检测路径")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                runtimePathLine("CPU", store.runtimeReport.cpuDescription)
                runtimePathLine("Wine Binary", store.runtimeReport.wineBinaryPath ?? "未检测到")
                runtimePathLine("Wine App", store.runtimeReport.wineAppPath ?? "未检测到")
                runtimePathLine("XQuartz", store.runtimeReport.xQuartzPath ?? "未检测到")
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))

            HStack(spacing: 10) {
                Button {
                    showGuideSheet = true
                } label: {
                    Label("一键安装引导", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent2)

                Button("选择 Wine 可执行文件") { store.chooseWineBinary() }
                    .buttonStyle(.bordered)
                Button("选择 Wine.app") { store.chooseWineApp() }
                    .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button {
                        Task { await store.downloadAndOpenWineInstaller() }
                    } label: {
                        Label("下载并打开 Wine 安装包", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .disabled(store.runtimeInstallBusy)

                    Button {
                        Task { await store.downloadAndOpenXQuartzInstaller() }
                    } label: {
                        Label("下载并打开 XQuartz 安装包", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.runtimeInstallBusy)

                    if store.runtimeInstallBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if !store.runtimeInstallMessage.isEmpty {
                    Text(store.runtimeInstallMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !store.lastDownloadedInstallerPath.isEmpty {
                    HStack(spacing: 8) {
                        Text(store.lastDownloadedInstallerPath)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                        Spacer()
                        Button("打开安装包") { store.openLastDownloadedInstaller() }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }
            }
        }
        .glassCard()
        .sheet(isPresented: $showGuideSheet) {
            RuntimeInstallGuideSheet(store: store)
        }
    }

    private func runtimePathLine(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }
}

private struct RuntimeComponentRow: View {
    let component: RuntimeComponentStatus

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color(for: component.state))
                .frame(width: 10, height: 10)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(component.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(component.state.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color(for: component.state))
                }
                Text(component.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(component.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.035)))
    }

    private func color(for state: ComponentState) -> Color {
        switch state {
        case .ready: return AppTheme.accent
        case .warning: return AppTheme.accent2
        case .blocked: return AppTheme.danger
        case .missing: return AppTheme.danger
        case .unknown: return .gray
        }
    }
}

private struct RuntimeInstallGuideSheet: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text("一键安装引导（P2）")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text("这是图形化引导，不需要命令行。按顺序点即可。安装完成后回到主界面点击“重新检测”。")
                    .foregroundStyle(.white.opacity(0.8))

                VStack(spacing: 10) {
                    guideRow(title: "1. 下载 / 安装 Wine", subtitle: "打开 Wine 发布页面（推荐 Gcenx 构建）") {
                        RuntimeManager.openWineDownloadPage()
                    }
                    guideRow(title: "1A. App 内置下载 Wine 安装包（推荐）", subtitle: "不跳网页，直接下载并打开安装包") {
                        Task { await store.downloadAndOpenWineInstaller() }
                    }
                    guideRow(title: "2. 下载 / 安装 XQuartz（可选但建议）", subtitle: "部分 Wine 场景需要图形层支持") {
                        RuntimeManager.openXQuartzDownloadPage()
                    }
                    guideRow(title: "2A. App 内置下载 XQuartz 安装包", subtitle: "不跳网页，直接下载并打开安装包") {
                        Task { await store.downloadAndOpenXQuartzInstaller() }
                    }
                    guideRow(title: "3. Rosetta 安装说明（M 系列建议）", subtitle: "打开苹果官方说明页") {
                        RuntimeManager.openRosettaGuide()
                    }
                    guideRow(title: "4. 放行被拦截的 Wine", subtitle: "打开“隐私与安全性”页面") {
                        RuntimeManager.openPrivacySecuritySettings()
                    }
                    guideRow(title: "5. 已安装但仍未识别？", subtitle: "手动选择 Wine.app") {
                        store.chooseWineApp()
                    }
                }

                Spacer()

                HStack {
                    Button("重新检测运行环境") {
                        store.refreshRuntime()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    Spacer()
                    if store.runtimeInstallBusy { ProgressView() }
                    Button("关闭") { dismiss() }
                        .buttonStyle(.bordered)
                }
            }
            .padding(24)
            .frame(width: 720, height: 520, alignment: .topLeading)
        }
    }

    private func guideRow(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(.white)
                    .font(.headline)
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Spacer()
            Button("打开") { action() }
                .buttonStyle(.bordered)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }
}

private struct P3LaunchCard: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "3.circle.fill")
                    .foregroundStyle(AppTheme.accent2)
                Text("P3 启动游戏")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }

            if let game = store.selectedGame {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("游戏名称", text: Binding(
                                get: { store.selectedGame?.name ?? "" },
                                set: { store.updateSelectedGame(name: $0) }
                            ))
                            .textFieldStyle(.roundedBorder)

                            labeledValue("游戏目录", game.folderPath)
                            labeledValue("主程序 EXE", game.exePath)
                            labeledValue("Wine Prefix", game.prefixPath)
                            labeledValue("引擎识别", game.engine.rawValue)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Button("改 EXE") { store.chooseCustomEXEForSelectedGame() }
                                .buttonStyle(.bordered)
                            Button("改 Prefix") { store.chooseCustomPrefixForSelectedGame() }
                                .buttonStyle(.bordered)
                            Button("打开游戏目录") { store.revealSelectedGameFolder() }
                                .buttonStyle(.bordered)
                            Button("打开日志") { store.openLastLog() }
                                .buttonStyle(.bordered)
                                .disabled(store.lastLogPath.isEmpty)
                        }
                    }

                    DisclosureGroup("高级设置（可选）", isExpanded: $store.showAdvanced) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("备注（启动器内保存）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: Binding(
                                get: { store.selectedGame?.notes ?? "" },
                                set: { store.updateSelectedGame(notes: $0) }
                            ))
                            .frame(minHeight: 84)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
                        }
                        .padding(.top, 8)
                    }
                    .foregroundStyle(.white)

                    Button {
                        store.selectedWizardStep = .p3
                        store.startCurrentGame()
                    } label: {
                        Label("开始游戏", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.03)))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("还没有游戏配置")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("请先在 P1 选择游戏文件夹并保存到列表，然后再来这里一键启动。")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.78))
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.03)))
            }

            if !store.lastLogPath.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("最近日志")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(store.lastLogPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }
        }
        .glassCard()
    }

    private func labeledValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }
}

struct DeveloperExportView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("P3 独立 App 打包导出（开发者侧）")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text("用户使用时不需要 Xcode。这里是给你打包 `.app` / `.dmg` 用的说明入口。项目目录已附带脚本（含图标生成）：`scripts/generate_app_icon.sh`、`scripts/build_release_app.sh`、`scripts/make_dmg.sh`。")
                        .foregroundStyle(.white.opacity(0.8))

                    Group {
                        infoRow("项目根目录", store.rootDir.deletingLastPathComponent().path)
                        infoRow("运行时数据目录", store.rootDir.path)
                        infoRow("导出输出目录（默认）", store.exportsDir.path)
                    }
                    .glassCard()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("推荐发布流程")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("1. 在本项目根目录执行 `scripts/build_release_app.sh` 生成 `dist/GAL FOR MacOS.app`。")
                            .foregroundStyle(.secondary)
                        Text("2. 脚本会自动生成并注入默认图标（若缺失）。")
                            .foregroundStyle(.secondary)
                        Text("3. 运行 `scripts/make_dmg.sh` 生成 `GAL FOR MacOS.dmg`（可选）。")
                            .foregroundStyle(.secondary)
                        Text("4. 首次分发给用户时，建议附带一页“如何在 macOS 隐私与安全性中允许 Wine”说明。")
                            .foregroundStyle(.secondary)
                    }
                    .glassCard()
                }
                .padding(20)
            }
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.white)
                .textSelection(.enabled)
        }
    }
}
