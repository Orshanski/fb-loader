import SwiftUI

struct ContentView: View {
    @State private var state = AppState()

    var body: some View {
        Group {
            switch state.stage {
            case .onboarding:
                OnboardingView { inpx, arch in
                    state.userPaths.inpxURL = inpx
                    state.userPaths.archivesDirectoryURL = arch
                    Task { await loadLibrary() }
                }
            case .loading(let p):
                VStack(spacing: 12) {
                    ProgressView()
                    Text(p).foregroundStyle(.secondary)
                }
                .frame(minWidth: 600, minHeight: 350)
            case .ready(let lib):
                MainWindowView(library: lib)
                    .environment(state)
            case .failed(let msg):
                VStack(spacing: 16) {
                    Text("Не удалось открыть каталог")
                        .font(.title2).bold()
                    if let inpx = state.userPaths.inpxURL {
                        Text(inpx.path)
                            .font(.callout).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    DisclosureGroup("Подробности ошибки") {
                        ScrollView {
                            Text(msg)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(8)
                        }
                        .frame(maxWidth: 560, maxHeight: 160)
                        .background(Color(nsColor: .controlBackgroundColor))
                    }
                    .frame(maxWidth: 560)
                    Button("Указать пути заново") {
                        state.userPaths.inpxURL = nil
                        state.userPaths.archivesDirectoryURL = nil
                        state.stage = .onboarding
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding(24)
                .frame(minWidth: 600, minHeight: 350)
            }
        }
        .task {
            // On every launch: if both paths configured and reachable, load.
            // Otherwise show onboarding.
            guard let inpx = state.userPaths.inpxURL,
                  let arch = state.userPaths.archivesDirectoryURL,
                  FileManager.default.fileExists(atPath: inpx.path),
                  FileManager.default.fileExists(atPath: arch.path) else {
                state.stage = .onboarding
                return
            }
            await loadLibrary()
        }
    }

    private func loadLibrary() async {
        guard let inpx = state.userPaths.inpxURL else { return }
        state.stage = .loading(progress: "Чтение каталога…")
        do {
            // Capture state weakly via the surrounding View — onProgress is
            // called from a background thread inside INPXImporter.import_;
            // we hop to MainActor for each tick. SwiftUI coalesces redraws
            // automatically, so a tick every 1000 books is cheap.
            let lib = try await LibraryLoader.load(inpxURL: inpx) { count in
                Task { @MainActor in
                    state.stage = .loading(progress: "Прочитано книг: \(count)")
                }
            }
            state.stage = .ready(lib)
        } catch {
            state.stage = .failed("\(error)")
        }
    }
}
