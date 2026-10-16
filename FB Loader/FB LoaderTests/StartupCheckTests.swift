import Foundation
import Testing
@testable import FB_Loader

@Suite("StartupCheck")
struct StartupCheckTests {
    private let nas = URL(fileURLWithPath: "/Volumes/flibusta/lib.inpx")
    private let nasArchives = URL(fileURLWithPath: "/Volumes/flibusta/archives")
    private let usb = URL(fileURLWithPath: "/Volumes/USB/archives")
    private let local = URL(fileURLWithPath: "/Users/me/lib.inpx")
    private let smb = VolumeInfo(name: "flibusta", isNetwork: true,
                                 remountURL: URL(string: "smb://alexey@DXP2800-0C7F._smb._tcp.local/flibusta"))

    private func fs(existing: Set<String> = [], mounted: Set<String> = []) -> FileSystemProbe {
        FileSystemProbe(exists: { existing.contains($0.path) },
                        isMountedVolume: { mounted.contains($0.path) })
    }

    private func run(inpx: URL?, archives: URL?,
                     inpxVolume: VolumeInfo? = nil, archivesVolume: VolumeInfo? = nil,
                     fs: FileSystemProbe, timeout: Duration = .seconds(5),
                     registry: ProbeRegistry = ProbeRegistry()) async -> StartupCheck {
        await StartupCheck.run(inpx: inpx, archives: archives,
                               inpxVolume: inpxVolume, archivesVolume: archivesVolume,
                               fs: fs, timeout: timeout, registry: registry)
    }

    @Test("классификация одного пути")
    func classify() {
        let present = fs(existing: [nas.path], mounted: ["/Volumes/flibusta"])
        #expect(PathState.classify(nas, fs: present) == .ok)
        #expect(PathState.classify(nas, fs: fs(mounted: ["/Volumes/flibusta"])) == .notFound)
        #expect(PathState.classify(nas, fs: fs()) == .volumeNotMounted(name: "flibusta"))
        #expect(PathState.classify(local, fs: fs()) == .notFound)
        #expect(PathState.classify(local, fs: fs(existing: [local.path])) == .ok)
    }

    @Test("пустая папка-остаток точки монтирования не считается подключённым томом")
    func staleMountPoint() {
        let stale = fs(existing: ["/Volumes/flibusta", nas.path])
        #expect(PathState.classify(nas, fs: stale) == .volumeNotMounted(name: "flibusta"))
        let mountPoint = URL(fileURLWithPath: "/Volumes/flibusta")
        #expect(PathState.classify(mountPoint, fs: stale) == .volumeNotMounted(name: "flibusta"))
    }

    @Test("оба пути на месте")
    func allOK() async {
        let r = await run(inpx: nas, archives: nasArchives,
                          fs: fs(existing: [nas.path, nasArchives.path], mounted: ["/Volumes/flibusta"]))
        #expect(r == .ok)
    }

    @Test("файл не найден при подключённом томе — прежний онбординг")
    func fileNotFound() async {
        let r = await run(inpx: nas, archives: nasArchives,
                          fs: fs(existing: [nasArchives.path], mounted: ["/Volumes/flibusta"]))
        #expect(r == .missing(.inpx))
        let none = await run(inpx: nil, archives: nil, fs: fs())
        #expect(none == .missing(.both))
    }

    @Test("оба пути на одном неподключённом томе — одна проблема про том")
    func sameVolume() async {
        let r = await run(inpx: nas, archives: nasArchives, inpxVolume: smb, archivesVolume: smb, fs: fs())
        #expect(r == .problem(StorageProblem(kind: .notMounted, volumeName: "flibusta",
                                             volume: smb, fallback: .both)))
    }

    @Test("разные тома — сначала том INPX, после его подключения следующий")
    func differentVolumes() async {
        let first = await run(inpx: nas, archives: usb, inpxVolume: smb, fs: fs())
        guard case .problem(let p1) = first else { Issue.record("ожидалась проблема"); return }
        #expect(p1.volumeName == "flibusta")
        #expect(p1.fallback == .both)

        let second = await run(inpx: nas, archives: usb, inpxVolume: smb,
                               fs: fs(existing: [nas.path], mounted: ["/Volumes/flibusta"]))
        guard case .problem(let p2) = second else { Issue.record("ожидалась проблема"); return }
        #expect(p2.volumeName == "USB")
        #expect(p2.fallback == .archives)
    }

    @Test("том не подключён, второй путь на месте — fallback спрашивает только неподключённый")
    func fallbackKeepsReachable() async {
        let r = await run(inpx: nas, archives: local, fs: fs(existing: [local.path]))
        guard case .problem(let p) = r else { Issue.record("ожидалась проблема"); return }
        #expect(p.fallback == .inpx)
    }

    @Test("без сведений о томе: «Диск … не подключён», без «Подключить»")
    func unknownVolume() async {
        let r = await run(inpx: nas, archives: nasArchives, fs: fs())
        guard case .problem(let p) = r else { Issue.record("ожидалась проблема"); return }
        #expect(p.title == "Диск «flibusta» не подключён")
        #expect(p.shareAddress == nil)
        #expect(p.remountURL == nil)
        #expect(p.message == "Подключите диск и нажмите «Повторить».")
    }

    @Test("сетевой том: заголовок, адрес без логина и «Подключить»")
    func networkVolume() async {
        let r = await run(inpx: nas, archives: nasArchives, inpxVolume: smb, archivesVolume: smb, fs: fs())
        guard case .problem(let p) = r else { Issue.record("ожидалась проблема"); return }
        #expect(p.title == "Сетевой диск «flibusta» не подключён")
        #expect(p.message == "Каталог лежит на smb://DXP2800-0C7F.local/flibusta. Подключите диск и нажмите «Повторить».")
        #expect(p.remountURL == smb.remountURL)
    }

    @Test("локальный внешний диск: «Подключить» нет даже с URL")
    func localVolumeNoRemount() {
        let info = VolumeInfo(name: "USB", isNetwork: false, remountURL: URL(string: "file:///Volumes/USB/"))
        let p = StorageProblem(kind: .notMounted, volumeName: "USB", volume: info, fallback: .both)
        #expect(p.title == "Диск «USB» не подключён")
        #expect(p.remountURL == nil)
    }

    private func hangingProbe(gate: DispatchSemaphore, hangingPaths: Set<String>,
                              calls: Counter = Counter()) -> FileSystemProbe {
        FileSystemProbe(
            exists: { url in
                calls.increment()
                if hangingPaths.contains(url.path) { gate.wait() }
                return true
            },
            isMountedVolume: { $0.path == "/Volumes/flibusta" })
    }

    @Test("зависший вызов даёт «не отвечает» и не блокирует проверку")
    func timeout() async {
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal(); gate.signal() }
        let hanging = hangingProbe(gate: gate, hangingPaths: [nas.path, nasArchives.path])
        let r = await run(inpx: nas, archives: nasArchives, inpxVolume: smb, fs: hanging,
                          timeout: .milliseconds(50))
        guard case .problem(let p) = r else { Issue.record("ожидалась проблема"); return }
        #expect(p.kind == .unresponsive)
        #expect(p.title == "Сетевой диск «flibusta» не отвечает")
        #expect(p.remountURL == nil)
    }

    @Test("«не подключён» важнее «не отвечает»")
    func notMountedBeatsUnresponsive() async {
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let hanging = hangingProbe(gate: gate, hangingPaths: [nas.path])
        let r = await run(inpx: nas, archives: usb, fs: hanging, timeout: .milliseconds(50))
        guard case .problem(let p) = r else { Issue.record("ожидалась проблема"); return }
        #expect(p.kind == .notMounted)
        #expect(p.volumeName == "USB")
    }

    @Test("при «не отвечает» fallback спрашивает только зависший путь")
    func unresponsiveFallback() async {
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let probe = FileSystemProbe(
            exists: { url in if url == nas { gate.wait() }; return true },
            isMountedVolume: { _ in true })
        let r = await run(inpx: nas, archives: local, fs: probe, timeout: .milliseconds(50))
        guard case .problem(let p) = r else { Issue.record("ожидалась проблема"); return }
        #expect(p.kind == .unresponsive)
        #expect(p.fallback == .inpx)
    }

    @Test("пока проба пути висит, новая не создаётся — сразу «не отвечает»")
    func hungProbeIsNotRepeated() async {
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let calls = Counter()
        let registry = ProbeRegistry()
        let hanging = hangingProbe(gate: gate, hangingPaths: [nas.path], calls: calls)
        _ = await run(inpx: nas, archives: nil, fs: hanging, timeout: .milliseconds(50), registry: registry)
        let before = calls.value
        let started = ContinuousClock.now
        let r = await run(inpx: nas, archives: nil, fs: hanging, timeout: .seconds(5), registry: registry)
        guard case .problem(let p) = r else { Issue.record("ожидалась проблема"); return }
        #expect(p.kind == .unresponsive)
        #expect(calls.value == before)
        #expect(ContinuousClock.now - started < .seconds(2))
    }

    @Test("withTimeout: быстрый результат возвращается, зависший — nil")
    func withTimeoutBehaviour() async {
        #expect(await withTimeout(.seconds(5)) { 42 } == 42)
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let r: Int? = await withTimeout(.milliseconds(50)) { gate.wait(); return 1 }
        #expect(r == nil)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func increment() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

@Suite("VolumeInfo")
struct VolumeInfoTests {
    @Test("адрес шары без логина и служебных меток Bonjour")
    func shareAddress() {
        let cases: [(String, String)] = [
            ("smb://alexey@DXP2800-0C7F._smb._tcp.local/flibusta", "smb://DXP2800-0C7F.local/flibusta"),
            ("smb://user:pw@nas.local/share", "smb://nas.local/share"),
            ("afp://nas._afpovertcp._tcp.local/Lib", "afp://nas.local/Lib"),
            ("smb://192.168.1.5/books", "smb://192.168.1.5/books"),
        ]
        for (input, expected) in cases {
            let info = VolumeInfo(name: "x", isNetwork: true, remountURL: URL(string: input))
            #expect(info.shareAddress == expected, "\(input)")
        }
    }

    @Test("адрес шары декодируется для показа")
    func shareAddressDecoded() {
        let info = VolumeInfo(name: "x", isNetwork: true,
                              remountURL: URL(string: "smb://nas.local/%D0%9A%D0%BD%D0%B8%D0%B3%D0%B8%20%D1%80"))
        #expect(info.shareAddress == "smb://nas.local/Книги р")
    }

    @Test("логин и пароль не попадают в сохраняемый URL")
    func credentialsStripped() {
        let url = URL(string: "smb://alexey:secret@nas.local/flibusta")!
        #expect(VolumeInfo.withoutCredentials(url).absoluteString == "smb://nas.local/flibusta")
    }

    @Test("у локального тома адреса шары нет")
    func localHasNoAddress() {
        let info = VolumeInfo(name: "USB", isNetwork: false, remountURL: URL(string: "file:///Volumes/USB/"))
        #expect(info.shareAddress == nil)
    }

    @Test("определение тома существующего пути")
    func detect() {
        let info = VolumeInfo.detect(FileManager.default.temporaryDirectory)
        #expect(info != nil)
        #expect(info?.isNetwork == false)
    }
}
