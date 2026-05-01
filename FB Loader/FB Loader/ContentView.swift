import SwiftUI

struct ContentView: View {
    @State private var state = AppState()
    @State private var showSettings = false
    @State private var settingsRebuildProgress: String?
    @State private var loadGate = LoadSessionGate()

    var body: some View {
        Group {
            switch state.stage {
            case .starting:
                LoaderScreen(progress: "Подготовка…")
            case .onboarding:
                CatalogPickerView { inpx, arch in
                    state.userPaths.inpxURL = inpx
                    state.userPaths.archivesDirectoryURL = arch
                    Task { await loadLibrary() }
                }
            case .loading(let p):
                LoaderScreen(progress: p)
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
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                userPaths: state.userPaths,
                rebuildProgress: settingsRebuildProgress,
                onClose: { showSettings = false },
                onRebuild: {
                    state.reset()
                    settingsRebuildProgress = "Чтение каталога…"
                    if let cache = try? LibraryLoader.appSupportRoot()
                        .appendingPathComponent("library-cache.bin") {
                        try? FileManager.default.removeItem(at: cache)
                    }
                    Task {
                        await loadLibrary { progress in
                            settingsRebuildProgress = progress
                        }
                        settingsRebuildProgress = nil
                    }
                }
            )
        }
    }

    private func loadLibrary(onProgressText: ((String) -> Void)? = nil) async {
        guard let inpx = state.userPaths.inpxURL else { return }
        let loadToken = loadGate.begin()
        state.stage = .loading(progress: "Чтение каталога…")
        onProgressText?("Чтение каталога…")
        do {
            // UI throttle: importer ticks 1000s of times during a real import
            // (every 200 books). We hop each tick to MainActor, but only commit
            // a state.stage write if at least 100 ms passed since the last commit.
            let progress = LoadingProgressBag()
            let lastCountUpdate = AtomicLastUpdate()
            let lib = try await Task.detached {
                try await LibraryLoader.load(
                    inpxURL: inpx,
                    onStatus: { msg in
                        let formatted = progress.setStatus(msg)
                        Task { @MainActor in
                            loadGate.apply(loadToken) {
                                state.stage = .loading(progress: formatted)
                                onProgressText?(formatted)
                            }
                        }
                    },
                    onProgress: { count in
                        let formatted = progress.setCount(count)
                        Task { @MainActor in
                            if lastCountUpdate.shouldCommit() {
                                loadGate.apply(loadToken) {
                                    state.stage = .loading(progress: formatted)
                                    onProgressText?(formatted)
                                }
                            }
                        }
                    }
                )
            }.value
            if loadGate.finish(loadToken) {
                state.stage = .ready(lib)
            }
        } catch {
            if loadGate.finish(loadToken) {
                state.stage = .failed("\(error)")
            }
        }
    }
}

private struct LoaderScreen: View {
    let progress: String

    var body: some View {
        ZStack {
            Image("Loader")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(progress)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 24)
                    .textSelection(.enabled)
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(30)
        }
        .frame(minWidth: 600, minHeight: 350)
    }
}

@MainActor
final class LoadSessionGate {
    struct Token: Equatable, Sendable {
        fileprivate let id: UUID
    }

    private var activeToken: Token?

    func begin() -> Token {
        let token = Token(id: UUID())
        activeToken = token
        return token
    }

    func apply(_ token: Token, _ body: () -> Void) {
        guard activeToken == token else { return }
        body()
    }

    @discardableResult
    func finish(_ token: Token) -> Bool {
        guard activeToken == token else { return false }
        activeToken = nil
        return true
    }
}

/// Two-field progress bag used by `loadLibrary()`: the importer pushes
/// status-message updates and per-N-books counter updates from a background
/// thread; this bag combines them into a single render string under a lock,
/// so neither stream overwrites the other.
private nonisolated final class LoadingProgressBag: @unchecked Sendable {
    private let lock = NSLock()
    private var lastStatus: String = ""
    private var lastCount: Int = 0

    func setStatus(_ s: String) -> String {
        lock.lock(); defer { lock.unlock() }
        lastStatus = s
        return formatLocked()
    }
    func setCount(_ c: Int) -> String {
        lock.lock(); defer { lock.unlock() }
        lastCount = c
        return formatLocked()
    }
    private func formatLocked() -> String {
        if lastCount > 0 && !lastStatus.isEmpty {
            return "\(lastStatus)\nПрочитано книг: \(lastCount)"
        }
        if lastCount > 0 { return "Прочитано книг: \(lastCount)" }
        return lastStatus
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
