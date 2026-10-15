import SwiftUI
import AppKit

struct MainWindowView: View {
    let library: Library
    @Environment(AppState.self) private var state
    @State private var sidebarVisible = true
    @State private var showSearch = false
    /// Окно показывается, когда разделитель сайдбара уже стоит на сохранённом
    /// месте: иначе зоны на глазах прыгают из положения по умолчанию.
    @State private var layoutReady = false

    private let booksTableMinHeight: CGFloat = 240
    private let booksTableIdealHeight: CGFloat = 300

    var body: some View {
        HSplitView {
            if sidebarVisible {
                LeftSidebarView(library: library, onOpenSearch: { showSearch = true })
                    .modifier(RestoredPaneSize(axis: .horizontal, dimension: .sidebarWidth) {
                        revealLayout()
                    })
            }
            VSplitView {
                BooksTableView(library: library)
                    .frame(maxWidth: .infinity,
                           minHeight: booksTableMinHeight,
                           idealHeight: booksTableIdealHeight)
                if let libid = state.selectedBookLibid,
                   let book = library.book(libid: libid),
                   let archives = state.userPaths.archivesDirectoryURL {
                    BookDetailView(
                        library: library, archivesRoot: archives, book: book,
                        isCurrentSelection: { state.selectedBookLibid == book.libid },
                        onSelectAuthor: { aid in
                            let name = library.author(id: aid)?.displayName
                            state.selectAuthor(aid, deepLinkName: name)
                        },
                        onSelectSeries: { sid in
                            let name = library.series(id: sid)?.name
                            state.selectSeries(sid, deepLinkName: name)
                        }
                    )
                        .frame(maxWidth: .infinity)
                        .modifier(RestoredPaneSize(axis: .vertical, dimension: .bookDetailHeight))
                } else {
                    Text("Выберите книгу")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: BookTableColumns.minimumPaneWidth, maxWidth: .infinity)
            // Без приоритета прирост ширины окна уходит сайдбару, а не таблице.
            .layoutPriority(1)
        }
        .opacity(layoutReady ? 1 : 0)
        .task {
            try? await Task.sleep(for: RestoredPaneSize.revealTimeout)
            revealLayout()
        }
        .frame(minWidth: 1000, minHeight: 640)
        .sheet(isPresented: $showSearch) {
            SearchWindowView(
                library: library,
                archivesRoot: state.userPaths.archivesDirectoryURL,
                initialLanguage: state.languageFilter,
                preferredSize: searchSheetSize(),
                onClose: { showSearch = false }
            )
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    sidebarVisible.toggle()
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(sidebarVisible ? "Скрыть боковую панель (⌃⌘S)" : "Показать боковую панель (⌃⌘S)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Поиск по библиотеке (⌘F)")
            }
        }
        .focusedSceneValue(\.mainWindowActions, MainWindowActions(
            isAvailable: !showSearch && state.exportProgress == nil && !state.isSettingsPresented,
            sidebarVisible: sidebarVisible,
            toggleSidebar: { sidebarVisible.toggle() },
            openSearch: { showSearch = true }))
        // Таблица книг — ScrollView, а её содержимое macOS пускает под панель
        // окна: без непрозрачного фона строки просвечивают в полосе заголовка.
        .toolbarBackground(.visible, for: .windowToolbar)
        .onChange(of: state.shouldStartExport) { _, newValue in
            guard newValue else { return }
            state.shouldStartExport = false
            Task { await runExport() }
        }
        .sheet(item: Binding(
            get: { state.exportProgress.map { ProgressIdentifier(progress: $0) } },
            set: { _ in
                // Read-only binding — sheet dismissal is handled by
                // ExportProgressSheet's done-closure below.
            })) { wrapper in
                ExportProgressSheet(progress: wrapper.progress) {
                    state.exportProgress = nil
                }
        }
        .onExportProgress(state.exportProgress) { progress in
            state.checkedBookLibids = progress.removingSucceeded(
                from: state.checkedBookLibids)
        }
    }

    private func revealLayout() {
        guard !layoutReady else { return }
        withAnimation(.easeOut(duration: 0.12)) { layoutReady = true }
    }

    private func searchSheetSize() -> CGSize {
        if let main = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && !$0.isSheet }) {
            let parent = main.frame.size
            return CGSize(width: parent.width * 0.8,
                          height: parent.height * 0.8)
        }
        return CGSize(width: 1100, height: 800)
    }

    private struct ProgressIdentifier: Identifiable {
        let progress: ExportProgress
        var id: ObjectIdentifier { ObjectIdentifier(progress) }
    }

    private func runExport() async {
        // Гард против двойного запуска: если предыдущий ExportRunner ещё
        // не вернулся (sheet жив, либо last in-flight книга дописывается),
        // повторный клик «Выгрузить» игнорируется — иначе два Task'а
        // погонятся за общим state.checkedBookLibids.
        guard state.exportProgress == nil else { return }
        guard !state.checkedBookLibids.isEmpty,
              let archives = state.userPaths.archivesDirectoryURL else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = state.userPaths.lastExportDirectoryURL
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard let folder = await panel.selectedDirectory() else { return }
        state.userPaths.lastExportDirectoryURL = folder

        let authorID: Int32?
        if case .authors(let id) = state.sidebar { authorID = id } else { authorID = nil }
        let seriesID: Int32?
        if case .series(let id) = state.sidebar { seriesID = id } else { seriesID = nil }
        let items = ExportPlanner.plan(
            libids: state.checkedBookLibids,
            rootFolder: folder,
            selectedAuthorID: authorID,
            selectedSeriesID: seriesID,
            in: library)
        let progress = ExportProgress()
        state.exportProgress = progress
        Task {
            await ExportRunner.run(items: items, exportRoot: folder, archivesRoot: archives,
                                   library: library, progress: progress)
            // Финальный пересчёт — страховка от любого пути, при котором
            // последний `.onChange` не был доставлен или потерял
            // `state.exportProgress`: пользователь закрыл sheet после
            // «Отмена», SwiftUI переставил порядок диспатчей, runner
            // дописал последнюю книгу после обнуления биндинга и т.п.
            // Здесь берём полное `progress.succeeded` с захваченного
            // объекта и снимаем оставшееся.
            state.checkedBookLibids = progress.removingSucceeded(
                from: state.checkedBookLibids)
        }
    }
}

private extension NSOpenPanel {
    @MainActor
    func selectedDirectory() async -> URL? {
        await withCheckedContinuation { continuation in
            begin { response in
                continuation.resume(returning: response == .OK ? self.url : nil)
            }
        }
    }
}

/// Свой `@State` у модификатора: замеры на каждом кадре перетаскивания
/// перерисовывают только его, а не всё главное окно.
private struct RestoredPaneSize: ViewModifier {
    /// Предохранитель: если разделитель так и не поставлен, зона всё равно
    /// показывается.
    static let revealTimeout: Duration = .milliseconds(500)

    let axis: Axis
    let dimension: PaneDimension
    /// Вызывается, когда разделитель стоит на месте.
    var onPlaced: () -> Void = {}
    @State private var size: CGFloat
    @State private var placed = false
    @State private var revealed = false

    init(axis: Axis, dimension: PaneDimension, onPlaced: @escaping () -> Void = {}) {
        self.axis = axis
        self.dimension = dimension
        self.onPlaced = onPlaced
        _size = State(initialValue: dimension.restore(from: .standard))
    }

    func body(content: Content) -> some View {
        content
            // Минимум ширины сайдбара задаёт его шапка: при явном minWidth frame
            // отдаёт split view это число, и шапка шире него обрезается.
            .frame(maxWidth: axis == .horizontal ? dimension.max : nil,
                   minHeight: axis == .vertical ? dimension.min : nil)
            // Скрыта до установки разделителя — и при первом показе окна,
            // и когда сайдбар снова показывают после скрытия.
            .opacity(revealed ? 1 : 0)
            .background(SplitDividerPlacer(axis: axis, size: size) {
                placed = true
                // Следующий проход: split view уже разложен по новой позиции.
                Task { @MainActor in reveal() }
            })
            .task {
                try? await Task.sleep(for: Self.revealTimeout)
                reveal()
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                axis == .horizontal ? proxy.size.width : proxy.size.height
            } action: { new in
                // До установки разделителя split view показывает свой размер,
                // а не восстановленный — такой замер затёр бы сохранённый.
                if placed { size = new }
            }
            // Пишем в defaults после паузы, а не на каждый пиксель перетаскивания:
            // `task(id:)` отменяет прежнее ожидание при каждом новом замере.
            .task(id: placed ? size : -1) {
                guard placed else { return }
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                dimension.save(size, to: .standard)
            }
    }

    private func reveal() {
        guard !revealed else { return }
        withAnimation(.easeOut(duration: 0.12)) { revealed = true }
        onPlaced()
    }
}

/// `HSplitView`/`VSplitView` не учитывают ideal-размер зоны (весь остаток
/// отдают одной из зон) и не умеют autosave, а изменение min/max после
/// раскладки заново перераспределяет место. Поэтому при появлении зоны
/// разделитель ставится так же, как его поставил бы пользователь, — через
/// `NSSplitView.setPosition`.
private struct SplitDividerPlacer: NSViewRepresentable {
    let axis: Axis
    let size: CGFloat
    let onPlaced: () -> Void

    func makeNSView(context: Context) -> PlacerView {
        PlacerView(axis: axis, size: size, onPlaced: onPlaced)
    }
    func updateNSView(_: PlacerView, context: Context) {}

    final class PlacerView: NSView {
        private let axis: Axis
        private let size: CGFloat
        private let onPlaced: () -> Void
        private var scheduled = false
        /// 20 × 50 мс: окно успевает показаться в восстановленной рамке.
        private let maxAttempts = 20

        init(axis: Axis, size: CGFloat, onPlaced: @escaping () -> Void) {
            self.axis = axis
            self.size = size
            self.onPlaced = onPlaced
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, !scheduled else { return }
            scheduled = true
            DispatchQueue.main.async { [weak self] in self?.placeDivider(attempt: 1) }
        }

        private func placeDivider(attempt: Int) {
            guard let split = enclosingSplitView() else {
                assertionFailure("SplitDividerPlacer: NSSplitView не найден среди предков")
                return
            }
            let extent = axis == .horizontal ? split.bounds.width : split.bounds.height
            let fits = extent > size + split.dividerThickness
            if (window?.isVisible != true || !fits), attempt < maxAttempts {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.placeDivider(attempt: attempt + 1)
                }
                return
            }
            onPlaced()
            // В обоих split view одна пара зон, разделитель всегда первый.
            // Карточка — нижняя зона, поэтому позиция отсчитывается снизу.
            if axis == .horizontal {
                split.setPosition(size, ofDividerAt: 0)
            } else {
                split.setPosition(extent - size - split.dividerThickness, ofDividerAt: 0)
            }
        }

        private func enclosingSplitView() -> NSSplitView? {
            var view = superview
            while let current = view {
                if let split = current as? NSSplitView, split.isVertical == (axis == .horizontal) {
                    return split
                }
                view = current.superview
            }
            return nil
        }
    }
}
