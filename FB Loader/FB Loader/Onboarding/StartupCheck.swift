import AppKit

/// Проверки файловой системы внедряются, чтобы классификация тестировалась без дисков.
nonisolated struct MountedVolume: Equatable, Sendable {
    let mountPoint: URL
    let remountURL: URL?
}

/// Пути, подставленные на этот запуск вместо сохранённых.
nonisolated struct PathOverrides: Equatable, Sendable {
    var inpx: URL?
    var archives: URL?
}

nonisolated struct FileSystemProbe: Sendable {
    var exists: @Sendable (URL) -> Bool
    var isMountedVolume: @Sendable (URL) -> Bool
    var mountedVolumes: @Sendable () -> [MountedVolume] = { [] }

    static let live = FileSystemProbe(
        exists: { FileManager.default.fileExists(atPath: $0.path) },
        isMountedVolume: { mountPoint in
            // /Volumes/Macintosh HD — симлинк на «/», в списке томов он под другим путём.
            let resolved = mountPoint.resolvingSymlinksInPath().path
            let mounted = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil) ?? []
            return mounted.contains { $0.path == resolved }
        },
        mountedVolumes: {
            let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil) ?? []
            return urls.map {
                MountedVolume(mountPoint: $0,
                              remountURL: (try? $0.resourceValues(forKeys: [.volumeURLForRemountingKey]))?
                                  .volumeURLForRemounting)
            }
        })
}

nonisolated enum PathState: Equatable, Sendable {
    case ok
    case notFound
    case volumeNotMounted(name: String)
    case unresponsive
    /// Том смонтирован под другим именем (flibusta-1), и файл найден там.
    case remapped(URL)

    var isReachable: Bool {
        switch self {
        case .ok, .remapped: true
        default: false
        }
    }

    static func classify(_ url: URL, volume: VolumeInfo?, fs: FileSystemProbe) -> PathState {
        let base = classify(url, fs: fs)
        guard case .volumeNotMounted(let name) = base,
              let volume, volume.isNetwork, let remount = volume.remountURL else { return base }
        let other = fs.mountedVolumes().first { m in
            let c = m.mountPoint.pathComponents
            guard c.count == 3, c[1] == "Volumes", c[2] != name, let r = m.remountURL else { return false }
            return VolumeInfo.sameShare(r, remount)
        }
        guard let other else { return base }
        let moved = url.pathComponents.dropFirst(3).reduce(other.mountPoint) { $0.appendingPathComponent($1) }
        return classify(moved, fs: fs) == .ok ? .remapped(moved) : .notFound
    }

    static func classify(_ url: URL, fs: FileSystemProbe) -> PathState {
        let c = url.pathComponents
        guard c.count >= 3, c[0] == "/", c[1] == "Volumes" else {
            return fs.exists(url) ? .ok : .notFound
        }
        // Сначала том: от отмонтированного тома остаётся пустая папка, и exists на ней даёт ложное «на месте».
        guard fs.isMountedVolume(URL(fileURLWithPath: "/Volumes/\(c[2])")) else {
            return .volumeNotMounted(name: c[2])
        }
        return fs.exists(url) ? .ok : .notFound
    }
}

nonisolated struct StorageProblem: Equatable, Sendable {
    enum Kind: Sendable { case notMounted, unresponsive }
    let kind: Kind
    let volumeName: String?
    let volume: VolumeInfo?
    /// Что спросить, если пользователь выберет «Указать заново…».
    let fallback: MissingPaths

    private var isNetwork: Bool { volume?.isNetwork == true }

    var title: String {
        let noun = isNetwork ? "Сетевой диск" : "Диск"
        let name = volumeName.map { " «\($0)»" } ?? ""
        return "\(noun)\(name) " + (kind == .notMounted ? "не подключён" : "не отвечает")
    }

    var shareAddress: String? { volume?.shareAddress }

    var message: String {
        let reconnect = "Подключите диск и нажмите «Повторить»."
        if kind == .unresponsive { return "Проверьте соединение и нажмите «Повторить»." }
        guard let shareAddress else { return reconnect }
        return "Каталог лежит на \(shareAddress). \(reconnect)"
    }

    var remountURL: URL? {
        kind == .notMounted && isNetwork ? volume?.remountURL : nil
    }
}

nonisolated enum StartupCheck: Equatable, Sendable {
    case ok(PathOverrides)
    case missing(MissingPaths)
    case problem(StorageProblem)

    /// Каждая проверка идёт вне main actor со своим таймаутом: зависший SMB может держать `stat` минутами.
    static func run(inpx: URL?, archives: URL?,
                    inpxVolume: VolumeInfo?, archivesVolume: VolumeInfo?,
                    fs: FileSystemProbe = .live,
                    timeout: Duration = .seconds(5),
                    registry: ProbeRegistry = .shared) async -> StartupCheck {
        async let i = state(inpx, volume: inpxVolume, fs: fs, timeout: timeout, registry: registry)
        async let a = state(archives, volume: archivesVolume, fs: fs, timeout: timeout, registry: registry)
        let (inpxState, archivesState) = await (i, a)

        let missing = MissingPaths.check(inpx: inpx, archives: archives) { url in
            (url == inpx ? inpxState : archivesState).isReachable
        }
        guard let missing else {
            var overrides = PathOverrides()
            if case .remapped(let u) = inpxState { overrides.inpx = u }
            if case .remapped(let u) = archivesState { overrides.archives = u }
            return .ok(overrides)
        }

        let entries = [(inpxState, inpxVolume, inpx), (archivesState, archivesVolume, archives)]
        for (state, volume, _) in entries {
            if case .volumeNotMounted(let name) = state {
                return .problem(StorageProblem(kind: .notMounted, volumeName: volume?.name ?? name,
                                               volume: volume, fallback: missing))
            }
        }
        for (state, volume, url) in entries where state == .unresponsive {
            return .problem(StorageProblem(kind: .unresponsive,
                                           volumeName: volume?.name ?? url.flatMap(volumeName),
                                           volume: volume, fallback: missing))
        }
        return .missing(missing)
    }

    private static func state(_ url: URL?, volume: VolumeInfo?, fs: FileSystemProbe, timeout: Duration,
                              registry: ProbeRegistry) async -> PathState {
        guard let url else { return .notFound }
        guard registry.begin(url.path) else { return .unresponsive }
        return await withTimeout(timeout) {
            defer { registry.end(url.path) }
            return PathState.classify(url, volume: volume, fs: fs)
        } ?? .unresponsive
    }

    private static func volumeName(_ url: URL) -> String? {
        let c = url.pathComponents
        return c.count >= 3 && c[1] == "Volumes" ? c[2] : nil
    }
}

/// Незавершённые пробы по путям: зависшая проба держит поток, поэтому новую на тот же путь не запускаем.
nonisolated final class ProbeRegistry: @unchecked Sendable {
    static let shared = ProbeRegistry()
    private let lock = NSLock()
    private var inFlight: Set<String> = []

    func begin(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return inFlight.insert(key).inserted
    }
    func end(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        inFlight.remove(key)
    }
}

/// Действие выполняется только при первом вызове: ответ работы и таймер гоняются за один continuation.
nonisolated final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func fire(_ body: () -> Void) {
        lock.lock()
        let first = !fired
        fired = true
        lock.unlock()
        if first { body() }
    }
}

/// `nil` — `work` не уложилась в `timeout`. Работа идёт на своём `Thread`, таймер — на Task.sleep:
/// исчерпание пула GCD зависшими пробами не должно ломать таймаут.
nonisolated func withTimeout<T: Sendable>(_ timeout: Duration,
                                          _ work: @escaping @Sendable () -> T) async -> T? {
    await withCheckedContinuation { (cont: CheckedContinuation<T?, Never>) in
        let gate = OnceGate()
        let timer = Task.detached {
            try? await Task.sleep(for: timeout)
            gate.fire { cont.resume(returning: nil) }
        }
        let thread = Thread {
            let value = work()
            gate.fire { cont.resume(returning: value) }
            timer.cancel()
        }
        thread.start()
    }
}

private nonisolated final class ObserverBox: @unchecked Sendable {
    private let lock = NSLock()
    private var token: NSObjectProtocol?

    func set(_ t: NSObjectProtocol) { lock.lock(); token = t; lock.unlock() }
    func take() -> NSObjectProtocol? {
        lock.lock(); defer { lock.unlock() }
        let t = token
        token = nil
        return t
    }
}

/// Ждёт появления любого тома или таймаута, чтобы после «Подключить» не опрашивать вечно.
nonisolated func waitForVolumeMount(timeout: Duration) async {
    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
        let gate = OnceGate()
        let box = ObserverBox()
        let center = NSWorkspace.shared.notificationCenter
        let finish: @Sendable () -> Void = {
            gate.fire {
                if let t = box.take() { center.removeObserver(t) }
                cont.resume()
            }
        }
        box.set(center.addObserver(forName: NSWorkspace.didMountNotification,
                                   object: nil, queue: nil) { _ in finish() })
        Task.detached {
            try? await Task.sleep(for: timeout)
            finish()
        }
    }
}
