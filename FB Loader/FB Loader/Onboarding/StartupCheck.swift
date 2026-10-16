import AppKit

/// Проверки файловой системы внедряются, чтобы классификация тестировалась без дисков.
nonisolated struct FileSystemProbe: Sendable {
    var exists: @Sendable (URL) -> Bool
    var isMountedVolume: @Sendable (URL) -> Bool

    static let live = FileSystemProbe(
        exists: { FileManager.default.fileExists(atPath: $0.path) },
        isMountedVolume: { mountPoint in
            // /Volumes/Macintosh HD — симлинк на «/», в списке томов он под другим путём.
            let resolved = mountPoint.resolvingSymlinksInPath().path
            let mounted = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil) ?? []
            return mounted.contains { $0.path == resolved }
        })
}

nonisolated enum PathState: Equatable, Sendable {
    case ok
    case notFound
    case volumeNotMounted(name: String)
    case unresponsive

    static func classify(_ url: URL, fs: FileSystemProbe) -> PathState {
        if fs.exists(url) { return .ok }
        let c = url.pathComponents
        guard c.count >= 3, c[0] == "/", c[1] == "Volumes" else { return .notFound }
        let mountPoint = URL(fileURLWithPath: "/Volumes/\(c[2])")
        return fs.isMountedVolume(mountPoint) ? .notFound : .volumeNotMounted(name: c[2])
    }
}

/// Проблема с носителем, а не с самим файлом: экран онбординга показывает её отдельно.
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
    case ok
    case missing(MissingPaths)
    case problem(StorageProblem)

    /// Каждая проверка идёт вне main actor со своим таймаутом: зависший SMB может держать `stat` минутами.
    static func run(inpx: URL?, archives: URL?,
                    inpxVolume: VolumeInfo?, archivesVolume: VolumeInfo?,
                    fs: FileSystemProbe = .live,
                    timeout: Duration = .seconds(5)) async -> StartupCheck {
        async let i = state(inpx, fs: fs, timeout: timeout)
        async let a = state(archives, fs: fs, timeout: timeout)
        let (inpxState, archivesState) = await (i, a)

        let missing = MissingPaths.check(inpx: inpx, archives: archives) { url in
            (url == inpx ? inpxState : archivesState) == .ok
        }
        guard let missing else { return .ok }

        let entries = [(inpxState, inpxVolume, inpx), (archivesState, archivesVolume, archives)]
        for (state, volume, _) in entries {
            if case .volumeNotMounted(let name) = state {
                return .problem(StorageProblem(kind: .notMounted, volumeName: name,
                                               volume: volume, fallback: missing))
            }
        }
        for (state, volume, url) in entries where state == .unresponsive {
            return .problem(StorageProblem(kind: .unresponsive, volumeName: url.flatMap(volumeName),
                                           volume: volume, fallback: missing))
        }
        return .missing(missing)
    }

    private static func state(_ url: URL?, fs: FileSystemProbe, timeout: Duration) async -> PathState {
        guard let url else { return .notFound }
        return await withTimeout(timeout) { PathState.classify(url, fs: fs) } ?? .unresponsive
    }

    private static func volumeName(_ url: URL) -> String? {
        let c = url.pathComponents
        return c.count >= 3 && c[1] == "Volumes" ? c[2] : nil
    }
}

/// Возобновляет continuation ровно один раз, кто бы ни пришёл первым.
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

/// `nil` — `work` не уложилась в `timeout`. Зависший вызов остаётся на своём потоке, но UI не держит.
nonisolated func withTimeout<T: Sendable>(_ timeout: Duration,
                                          _ work: @escaping @Sendable () -> T) async -> T? {
    await withCheckedContinuation { (cont: CheckedContinuation<T?, Never>) in
        let gate = OnceGate()
        DispatchQueue.global(qos: .userInitiated).async {
            let value = work()
            gate.fire { cont.resume(returning: value) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout.timeInterval) {
            gate.fire { cont.resume(returning: nil) }
        }
    }
}

private extension Duration {
    nonisolated var timeInterval: TimeInterval {
        let c = components
        return TimeInterval(c.seconds) + TimeInterval(c.attoseconds) / 1e18
    }
}

private nonisolated final class ObserverBox: @unchecked Sendable {
    var token: NSObjectProtocol?
}

/// Ждёт появления любого тома или таймаута, чтобы после «Подключить» не опрашивать вечно.
nonisolated func waitForVolumeMount(timeout: Duration) async {
    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
        let gate = OnceGate()
        let box = ObserverBox()
        let center = NSWorkspace.shared.notificationCenter
        let finish: @Sendable () -> Void = {
            gate.fire {
                if let t = box.token { center.removeObserver(t) }
                cont.resume()
            }
        }
        box.token = center.addObserver(forName: NSWorkspace.didMountNotification,
                                       object: nil, queue: nil) { _ in finish() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout.timeInterval) { finish() }
    }
}
