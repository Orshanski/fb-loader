import SwiftUI

extension Notification.Name {
    /// Posted from the menu's "Настройки…" command. ContentView listens and
    /// shows the SettingsView as a sheet attached to the main window — so
    /// closing the main window automatically dismisses Settings, no stranded
    /// auxiliary panel.
    static let openSettings = Notification.Name("FBLoader.openSettings")
}

@main
struct FB_LoaderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Настройки…") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
