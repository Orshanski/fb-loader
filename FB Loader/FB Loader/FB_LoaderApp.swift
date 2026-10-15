import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }
}

@main
struct FB_LoaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Не `WindowGroup`: у каждого окна свой `AppState` и своя копия каталога
        // (~750 МБ), а восстановление окон при запуске открывало два.
        Window("FB Loader", id: "main") {
            ContentView()
        }
        .commands {
            MainWindowCommands()
        }
    }
}
