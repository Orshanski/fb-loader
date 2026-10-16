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
    @State private var exportAction = ExportAction()

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
                BooksTableView(library: library, exportAction: exportAction)
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
        .onAppear {
            exportAction.perform = { Task { await startExport() } }
            exportAction.isAvailable = { !state.exportSession.isBusy }
        }
        .task {
            try? await Task.sleep(for: RestoredPaneSize.revealTimeout)
            revealLayout()
        }
        // Без minWidth: минимум ширины окна — сумма минимумов зон, иначе узкая
        // правая панель (без «Жанров» и «Размера») недостижима.
        .frame(minHeight: 640)
        .sheet(isPresented: $showSearch) {
            SearchWindowView(
                library: library,
                archivesRoot: state.userPaths.archivesDirectoryURL,
                exportSession: state.exportSession,
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
            isAvailable: !showSearch && state.exportSession.progress(for: .main) == nil
                && state.exportSession.phase != .choosingFolder && !state.isSettingsPresented,
            sidebarVisible: sidebarVisible,
            toggleSidebar: { sidebarVisible.toggle() },
            openSearch: { showSearch = true }))
        // Непрозрачная панель окна: под прозрачной просвечивает прокручиваемое
        // содержимое, которое macOS пускает под неё.
        .toolbarBackground(.visible, for: .windowToolbar)
        .sheet(item: Binding(
            get: { state.exportSession.progress(for: .main) },
            set: { _ in })) { progress in
                ExportProgressSheet(progress: progress) {
                    state.exportSession.closeProgress(origin: .main)
                }
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

    private func startExport() async {
        let authorID: Int32?
        if case .authors(let id) = state.sidebar { authorID = id } else { authorID = nil }
        let seriesID: Int32?
        if case .series(let id) = state.sidebar { seriesID = id } else { seriesID = nil }
        let state = state
        await state.exportSession.start(ExportRequest(
            libids: state.checkedBookLibids, library: library,
            selectedAuthorID: authorID, selectedSeriesID: seriesID,
            format: .fb2, origin: .main,
            uncheck: { _ = state.checkedBookLibids.remove($0) }))
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
