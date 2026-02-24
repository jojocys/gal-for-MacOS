import SwiftUI

@main
struct VNLauncherZeroApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup("GAL FOR MacOS") {
            RootView(store: store)
                .frame(minWidth: 1100, minHeight: 720)
        }
        Settings {
            DeveloperExportView(store: store)
                .frame(width: 760, height: 560)
        }
    }
}
