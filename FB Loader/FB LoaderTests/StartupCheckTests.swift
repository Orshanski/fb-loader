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
                     fs: FileSystemProbe, timeout: Duration = .seconds(5)) async -> StartupCheck {
        await StartupCheck.run(inpx: inpx, archives: archives,
                               inpxVolume: inpxVolume, archivesVolume: archivesVolume,
                               fs: fs, timeout: timeout)
    }

    @Test("классификация одного пути")
    func classify() {
        let present = fs(existing: [nas.path])
        #expect(PathState.classify(nas, fs: present) == .ok)
        #expect(PathState.classify(nas, fs: fs(mounted: ["/Volumes/flibusta"])) == .notFound)
        #expect(PathState.classify(nas, fs: fs()) == .volumeNotMounted(name: "flibusta"))
        #expect(PathState.classify(local, fs: fs()) == .notFound)
    }

    @Test("пустой каталог точки монтирования не считается подключённым томом")
    func staleMountPoint() {
        let stale = fs(existing: ["/Volumes/flibusta"])
        #expect(PathState.classify(nas, fs: stale) == .volumeNotMounted(name: "flibusta"))
    }

    @Test("оба пути на месте")
    func allOK() async {
        let r = await run(inpx: nas, archives: nasArchives,
                          fs: fs(existing: [nas.path, nasArchives.path]))
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

    @Test("разные тома — сообщение про том INPX, повтор покажет следующий")
    func differentVolumes() async {
        let r = await run(inpx: nas, archives: usb, inpxVolume: smb, fs: fs())
        guard case .problem(let p) = r else { Issue.record("ожидалась проблема"); return }
        #expect(p.volumeName == "flibusta")
        #expect(p.fallback == .both)
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

    @Test("зависший вызов даёт «не отвечает» и не блокирует проверку")
    func timeout() async {
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let hanging = FileSystemProbe(exists: { _ in gate.wait(); return true },
                                      isMountedVolume: { _ in true })
        let r = await run(inpx: nas, archives: nasArchives, inpxVolume: smb, fs: hanging,
                          timeout: .milliseconds(50))
        guard case .problem(let p) = r else { Issue.record("ожидалась проблема"); return }
        #expect(p.kind == .unresponsive)
        #expect(p.title == "Сетевой диск «flibusta» не отвечает")
        #expect(p.remountURL == nil)
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
