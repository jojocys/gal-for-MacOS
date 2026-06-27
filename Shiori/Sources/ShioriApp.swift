import SwiftUI

@main
struct ShioriApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup(AppInfo.name) {
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
