import SwiftUI

@main
struct VNLauncherZeroApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup("GAL FOR MacOS") {
            RootView(store: store)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("添加游戏文件夹") {
                    store.chooseAndScanGameFolder()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("开始游戏") {
                    store.startGame()
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
    }
}
