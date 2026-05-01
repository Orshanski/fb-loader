import SwiftUI

@main
struct FB_LoaderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        Settings {
            SettingsView(userPaths: .shared)
        }
    }
}
