import Foundation
import Observation

enum ExportOrigin { case main, search }

struct ExportRequest {
    let libids: Set<Int32>
    let library: Library
    let selectedAuthorID: Int32?
    let selectedSeriesID: Int32?
    let format: ExportFormat
    let origin: ExportOrigin
    let uncheck: @MainActor (Int32) -> Void
}

@MainActor @Observable
final class ExportSession {
    enum Phase: Equatable { case idle, choosingFolder, running }

    private(set) var phase: Phase = .idle
    /// non-nil ⇔ окно прогресса показано.
    private(set) var progress: ExportProgress?
    private(set) var origin: ExportOrigin?
    var isBusy: Bool { phase != .idle }
    /// Выбор папки, ход выгрузки или показанный итог: пока истинно, на экране модальное окно выгрузки.
    var isPresentingUI: Bool { isBusy || progress != nil }

    typealias ChooseFolder = @MainActor (_ initial: URL?) async -> URL?
    typealias MakeConverter = (ExportFormat) -> any ExportConverter
    typealias Run = @MainActor (_ items: [ExportItem], _ exportRoot: URL, _ progress: ExportProgress,
                                _ converter: any ExportConverter,
                                _ onExported: @escaping @MainActor (Int32) -> Void) async -> Void

    @ObservationIgnored private let userPaths: UserPaths
    @ObservationIgnored private let chooseFolder: ChooseFolder
    @ObservationIgnored private let makeConverter: MakeConverter
    @ObservationIgnored private let run: Run

    init(userPaths: UserPaths, chooseFolder: @escaping ChooseFolder,
         makeConverter: @escaping MakeConverter = ExportConverters.make,
         run: @escaping Run = ExportRunner.run) {
        self.userPaths = userPaths
        self.chooseFolder = chooseFolder
        self.makeConverter = makeConverter
        self.run = run
    }

    /// nil — запуск не состоялся (занято, нечего выгружать, панель отменена).
    @discardableResult
    func start(_ request: ExportRequest) async -> Task<Void, Never>? {
        guard !isBusy, !request.libids.isEmpty,
              let archivesRoot = userPaths.effectiveArchivesURL else { return nil }
        phase = .choosingFolder
        guard let folder = await chooseFolder(initialFolder()) else {
            phase = .idle
            return nil
        }
        userPaths.lastExportDirectoryURL = folder
        let items = ExportPlanner.plan(libids: request.libids, rootFolder: folder, archivesRoot: archivesRoot,
                                       selectedAuthorID: request.selectedAuthorID,
                                       selectedSeriesID: request.selectedSeriesID,
                                       format: request.format, in: request.library)
        let newProgress = ExportProgress()
        progress = newProgress
        origin = request.origin
        phase = .running
        let converter = makeConverter(request.format)
        let uncheck = request.uncheck
        let run = run
        return Task {
            await run(items, folder, newProgress, converter, uncheck)
            phase = .idle
        }
    }

    func progress(for origin: ExportOrigin) -> ExportProgress? {
        self.origin == origin ? progress : nil
    }

    func closeProgress(origin: ExportOrigin) {
        guard self.origin == origin else { return }
        progress = nil
        self.origin = nil
    }

    private func initialFolder() -> URL {
        var isDirectory: ObjCBool = false
        if let last = userPaths.lastExportDirectoryURL,
           FileManager.default.fileExists(atPath: last.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return last
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
