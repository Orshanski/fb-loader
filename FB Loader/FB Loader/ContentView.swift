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
                // Disable implicit animations on rapid progress-string changes —
                // ProgressView's internal animator otherwise logs
                // "Animating backwards in time!" when ticks arrive faster than
                // the next render frame.
                .animation(nil, value: p)
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
            // UI throttle: importer ticks ~1000s of times during a real import.
            // We hop each tick to MainActor, but only commit a state.stage write
            // if at least 100 ms passed since the last commit — keeps the visible
            // counter responsive without flooding SwiftUI's animator.
            let lastUpdate = AtomicLastUpdate()
            let lib = try await LibraryLoader.load(inpxURL: inpx) { count in
                Task { @MainActor in
                    if lastUpdate.shouldCommit() {
                        state.stage = .loading(progress: "Прочитано книг: \(count)")
                    }
                }
            }
            state.stage = .ready(lib)
        } catch {
            state.stage = .failed("\(error)")
        }
    }
}

/// Trivial 100-ms throttle for MainActor-bound progress writes.
/// Lives here (not in AppState) because it's purely a view-side concern.
@MainActor
private final class AtomicLastUpdate {
    private var lastTick: ContinuousClock.Instant = .now - .seconds(1)
    private let minInterval: Duration = .milliseconds(100)

    func shouldCommit() -> Bool {
        let now = ContinuousClock.now
        if now - lastTick >= minInterval {
            lastTick = now
            return true
        }
        return false
    }
}
