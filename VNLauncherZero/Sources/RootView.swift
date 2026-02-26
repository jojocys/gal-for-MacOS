import AppKit
import SwiftUI

struct RootView: View {
    @ObservedObject var store: AppStore
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1200, minHeight: 760)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.addEmptyGame()
                } label: {
                    Image(systemName: "plus")
                }
                .help("新建配置")

                Button {
                    store.chooseEXEManually()
                } label: {
                    Image(systemName: "doc.badge.plus")
                }
                .help("手动选择 EXE")

                Button {
                    store.startGame()
                } label: {
                    Image(systemName: "play.fill")
                }
                .help("启动")

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .help("删除当前配置")
                .disabled(store.selectedGame == nil)
            }
        }
        .confirmationDialog("删除当前配置？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) { store.removeSelectedGame() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只删除配置记录，不删除游戏文件。")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("已保存游戏")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 14)

            List(selection: selectionBinding) {
                ForEach(store.games) { game in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(game.name)
                            .font(.headline)
                            .lineLimit(2)
                        Text(game.displaySubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(game.engineHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 5)
                    .tag(game.id)
                }
            }
            .listStyle(.sidebar)

            VStack(spacing: 10) {
                Button {
                    store.addEmptyGame()
                } label: {
                    Label("添加新配置", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color.green.opacity(0.85))

                Button {
                    store.chooseAndScanGameFolder()
                } label: {
                    Text("更改游戏文件夹")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    store.openSelectedGameFolder()
                } label: {
                    Text("打开游戏文件夹")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Text("删除当前配置")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(store.selectedGame == nil)
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .padding(.horizontal, 10)
            .padding(.top, 6)

            HStack {
                Text("共 \(store.games.count) 个配置")
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
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 360)
        .background(
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.08, blue: 0.2), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var detail: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.11, blue: 0.17), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    heroCard
                    p1Card
                    p2Card
                    p3Card
                }
                .padding(20)
            }
        }
    }

    private var heroCard: some View {
        card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("GAL FOR MacOS")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("选择游戏文件夹 -> 检查运行环境 -> 一键启动")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))

                    HStack(spacing: 14) {
                        stepPill("P1", "选择游戏")
                        stepPill("P2", "运行环境")
                        stepPill("P3", "启动游戏")
                    }
                    .padding(.top, 8)
                }
                Spacer(minLength: 12)
                Button {
                    store.openRepairGuide()
                } label: {
                    Label("一键修复引导", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.orange.opacity(0.9))
            }
        }
    }

    private func stepPill(_ left: String, _ right: String) -> some View {
        HStack(spacing: 10) {
            Text(left)
                .font(.headline.monospaced())
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            Text(right)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.95))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(Color.white.opacity(0.06))
        )
        .overlay(
            Capsule().stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private var p1Card: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    Text("1")
                        .font(.caption.bold())
                        .foregroundStyle(.black)
                        .padding(6)
                        .background(Circle().fill(Color.orange))
                    Text("P1 选择游戏文件夹（自动识别主程序）")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Spacer()
                    if let scan = store.scanResult {
                        VStack(alignment: .trailing, spacing: 6) {
                            statBadge("识别引擎", scan.engineHint)
                            statBadge("XP3 数量", "\(scan.xp3Count)")
                            statBadge("候选 EXE", "\(scan.exeCandidates.count)")
                        }
                    } else {
                        VStack(alignment: .trailing, spacing: 6) {
                            statBadge("识别引擎", "未识别")
                            statBadge("XP3 数量", "-")
                            statBadge("候选 EXE", "-")
                        }
                    }
                }

                Text("推荐做法：直接选择整个游戏目录，启动器会自动扫描 .exe 并优先推荐真正的主程序。")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))

                VStack(alignment: .leading, spacing: 8) {
                    Text("配置名称（可自定义）")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.7))
                    TextField(
                        "例如：Senren Banka",
                        text: Binding(
                            get: { store.selectedGame?.name ?? "" },
                            set: { store.renameSelectedGame($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("当前目录")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(store.selectedGame?.gameFolderPath.isEmpty == false ? (store.selectedGame?.gameFolderPath ?? "") : "尚未选择")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    Button {
                        store.chooseAndScanGameFolder()
                    } label: {
                        Label("选择游戏文件夹", systemImage: "folder")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.green.opacity(0.8))

                    Button {
                        store.rescanCurrentFolder()
                    } label: {
                        Label("重新扫描", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        store.chooseEXEManually()
                    } label: {
                        Label("手动选择 EXE", systemImage: "doc")
                    }
                    .buttonStyle(.bordered)
                }

                if let scan = store.scanResult {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("推荐主程序候选")
                            .font(.headline)
                            .foregroundStyle(.white)
                        ForEach(Array(scan.exeCandidates.prefix(5))) { candidate in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(candidate.exeURL.lastPathComponent)
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    Text(candidate.reason)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.65))
                                    Text(candidate.exeURL.path)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.55))
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text("\(candidate.score)")
                                    .font(.system(.body, design: .monospaced).bold())
                                    .foregroundStyle(.white.opacity(0.8))
                                Button("选用") { store.applyRecommendedCandidate(candidate) }
                                    .buttonStyle(.bordered)
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.03)))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    pathRow(title: "推荐 EXE", value: store.selectedGame?.exePath ?? "") {
                        Button("选择 EXE") { store.chooseEXEManually() }.buttonStyle(.bordered)
                    }
                    pathRow(title: "Wine Prefix", value: store.selectedGame?.prefixDir ?? "") {
                        Button("选择 Prefix") { store.choosePrefixFolder() }.buttonStyle(.bordered)
                    }
                }

                HStack {
                    Button {
                        store.saveCurrentFromP1()
                    } label: {
                        Label("保存到游戏列表（进入 P2）", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.blue.opacity(0.75))

                    Spacer()
                }
            }
        }
    }

    private var p2Card: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("2")
                        .font(.caption.bold())
                        .foregroundStyle(.black)
                        .padding(6)
                        .background(Circle().fill(Color.orange))
                    Text("P2 运行环境（无需命令行，图形化引导）")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        store.refreshRuntimeStatus()
                    } label: {
                        Label("重新检测", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }

                Text("这里会检测内置 Wine / Rosetta / XQuartz / Gatekeeper。已内置 Wine 的打包版无需再单独下载 Wine。")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))

                ForEach(store.runtimeReport.items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(color(for: item.state))
                            .frame(width: 14, height: 14)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text(item.detail)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                        Spacer()
                        Text(item.state.label)
                            .font(.headline)
                            .foregroundStyle(color(for: item.state))
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Button("一键安装 XQuartz（内置）") { store.installEmbeddedXQuartz() }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.orange.opacity(0.85))
                        Button("打开“隐私与安全性”") { store.openPrivacySettings() }.buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var p3Card: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("3")
                        .font(.caption.bold())
                        .foregroundStyle(.black)
                        .padding(6)
                        .background(Circle().fill(Color.orange))
                    Text("P3 启动游戏")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Spacer()
                }

                Text("确认 P1 已识别主程序、P2 已安装 Wine 后，点击下方按钮开始游戏。首次启动可能会稍慢。")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))

                if let game = store.selectedGame {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("当前配置：\(game.name)")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("EXE：\(game.exePath.isEmpty ? "尚未选择" : game.exePath)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(2)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
                }

                Button {
                    store.startGame()
                } label: {
                    Label("开始游戏", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color.blue.opacity(0.9))

                HStack(spacing: 10) {
                    Button("打开日志") { store.openLastLog() }
                        .buttonStyle(.bordered)
                        .disabled(store.lastLogPath.isEmpty)
                    Button("在 Finder 中打开游戏目录") { store.openSelectedGameFolder() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.05), Color.white.opacity(0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
    }

    private func statBadge(_ title: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.white.opacity(0.65))
            Text(value)
                .foregroundStyle(.white)
                .fontWeight(.semibold)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.05)))
    }

    private func pathRow<Trailing: View>(title: String, value: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 92, alignment: .leading)
            Text(value.isEmpty ? "尚未设置" : value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.03)))
    }

    private func color(for state: RuntimeCheckItem.State) -> Color {
        switch state {
        case .ok: return .green
        case .warning: return .yellow
        case .missing: return .orange
        case .blocked: return .red
        }
    }

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { store.selectedGameID },
            set: { store.selectGame($0) }
        )
    }
}
