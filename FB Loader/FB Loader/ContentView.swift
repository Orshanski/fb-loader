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
                VStack(spacing: 12) {
                    Text("Ошибка: \(msg)").foregroundStyle(.red)
                    Button("Указать пути заново") {
                        state.userPaths.inpxURL = nil
                        state.userPaths.archivesDirectoryURL = nil
                        state.stage = .onboarding
                    }
                }
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
            let lib = try await LibraryLoader.load(inpxURL: inpx)
            state.stage = .ready(lib)
        } catch {
            state.stage = .failed("\(error)")
        }
    }
}
