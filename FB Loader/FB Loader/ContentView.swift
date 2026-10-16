import SwiftUI

struct ContentView: View {
    @State private var state = AppState()
    @State private var settingsRebuildProgress: String?
    @State private var loadGate = LoadSessionGate()
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        Group {
            switch state.stage {
            case .starting:
                LoaderScreen(progress: "Подготовка…")
            case .onboarding(let missing):
                CatalogPickerView(missing: missing, userPaths: state.userPaths) { inpx, arch in
                    state.userPaths.inpxURL = inpx
                    state.userPaths.archivesDirectoryURL = arch
                    startLoad()
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
                        state.stage = .onboarding(.both)
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding(24)
                .frame(minWidth: 600, minHeight: 350)
            }
        }
        .task {
            if let missing = MissingPaths.check(
                inpx: state.userPaths.inpxURL,
                archives: state.userPaths.archivesDirectoryURL,
                isReachable: { FileManager.default.fileExists(atPath: $0.path) }) {
                state.stage = .onboarding(missing)
                return
            }
            startLoad()
        }
        .focusedSceneValue(\.openSettings, state.isAnySheetPresented ? nil : {
            state.isSettingsPresented = true
        })
        .sheet(isPresented: $state.isSettingsPresented) {
            SettingsView(
                userPaths: state.userPaths,
                rebuildProgress: settingsRebuildProgress,
                canRebuild: state.canRebuildCatalog,
                onClose: { state.isSettingsPresented = false },
                onRebuild: rebuildCatalog,
                onINPXChange: { url in
                    state.userPaths.inpxURL = url
                    if state.canRebuildCatalog { rebuildCatalog() }
                }
            )
        }
    }

    private func rebuildCatalog() {
        state.reset()
        settingsRebuildProgress = "Чтение каталога…"
        startLoad(forceRebuild: true,
                  onProgressText: { settingsRebuildProgress = $0 },
                  onFinish: { settingsRebuildProgress = nil })
    }

    /// Новая загрузка ждёт конца отменённой: иначе в памяти две `Library`.
    private func startLoad(forceRebuild: Bool = false,
                           onProgressText: ((String) -> Void)? = nil,
                           onFinish: (() -> Void)? = nil) {
        guard let inpx = state.userPaths.inpxURL else {
            onFinish?()
            return
        }
        let previous = loadTask
        previous?.cancel()
        loadGate.cancel()
        loadTask = Task {
            await previous?.value
            if !Task.isCancelled {
                await loadLibrary(inpx: inpx, forceRebuild: forceRebuild,
                                  onProgressText: onProgressText)
            }
            onFinish?()
        }
    }

    private func loadLibrary(inpx: URL, forceRebuild: Bool,
                             onProgressText: ((String) -> Void)?) async {
        let loadToken = loadGate.begin()
        state.stage = .loading(progress: "Чтение каталога…")
        onProgressText?("Чтение каталога…")
        do {
            // UI throttle: importer ticks 1000s of times during a real import
            // (every 200 books). We hop each tick to MainActor, but only commit
            // a state.stage write if at least 100 ms passed since the last commit.
            let progress = LoadingProgressBag()
            let lastCountUpdate = AtomicLastUpdate()
            let lib = try await runDetachedCancellable {
                try await LibraryLoader.load(
                    inpxURL: inpx,
                    forceRebuild: forceRebuild,
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
            }
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

    /// Колбэки и результат отменённой загрузки стадию уже не трогают.
    func cancel() {
        activeToken = nil
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
