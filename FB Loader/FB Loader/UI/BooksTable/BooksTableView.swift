import SwiftUI

struct BooksTableView: View {
    let library: Library
    @Environment(AppState.self) private var state
    /// DisclosureGroup needs an explicit isExpanded binding to be reliably
    /// clickable inside a List on macOS 26 — without this, the implicit
    /// `@State` inside DisclosureGroup gets reset on every parent re-render
    /// and series simply don't expand. Stores series IDs that are open.
    @State private var expandedSeries: Set<Int32> = []

    private struct GroupedRow: Identifiable {
        enum Kind { case loose(Book); case seriesHeader(Series, [Book]) }
        let kind: Kind
        var id: String {
            switch kind {
            case .loose(let b): return "b-\(b.libid)"
            case .seriesHeader(let s, _): return "s-\(s.id)"
            }
        }
    }

    private var visibleBooks: [Book] {
        if let aid = state.selectedAuthorID, state.sidebarTab == .authors {
            return BooksByContext.books(for: .author(aid),
                                        language: state.languageFilter,
                                        in: library)
        }
        if let sid = state.selectedSeriesID, state.sidebarTab == .series {
            return BooksByContext.books(for: .series(sid),
                                        language: state.languageFilter,
                                        in: library)
        }
        return []
    }

    private var groups: [GroupedRow] {
        let books = visibleBooks
        var loose: [Book] = []
        var bySeries: [Int32: [Book]] = [:]
        for b in books {
            if let sid = b.seriesID { bySeries[sid, default: []].append(b) }
            else { loose.append(b) }
        }
        var rows: [GroupedRow] = loose.map { GroupedRow(kind: .loose($0)) }
        // O(1) series name lookup via the secondary index from Library.init.
        for (sid, items) in bySeries.sorted(by: {
            (library.seriesByID[$0.key]?.name ?? "") < (library.seriesByID[$1.key]?.name ?? "")
        }) {
            let s = library.seriesByID[sid] ?? Series(id: sid, name: "?")
            let sorted = items.sorted { ($0.seriesNum ?? Int16.max) < ($1.seriesNum ?? Int16.max) }
            rows.append(GroupedRow(kind: .seriesHeader(s, sorted)))
        }
        return rows
    }

    var body: some View {
        VStack(spacing: 0) {
            LanguageFilterPicker(library: library)
                .padding(8)
            List {
                ForEach(groups) { row in
                    switch row.kind {
                    case .loose(let b):
                        bookRow(b)
                    case .seriesHeader(let s, let items):
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedSeries.contains(s.id) },
                                set: { isOpen in
                                    if isOpen { expandedSeries.insert(s.id) }
                                    else      { expandedSeries.remove(s.id) }
                                }
                            )
                        ) {
                            ForEach(items) { b in bookRow(b) }
                        } label: {
                            Text("\(s.name) (\(items.count))")
                                .font(.headline)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if expandedSeries.contains(s.id) {
                                        expandedSeries.remove(s.id)
                                    } else {
                                        expandedSeries.insert(s.id)
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func bookRow(_ b: Book) -> some View {
        @Bindable var s = state
        return HStack {
            Toggle("", isOn: Binding(
                get: { s.checkedBookLibids.contains(b.libid) },
                set: { isOn in
                    if isOn { s.checkedBookLibids.insert(b.libid) }
                    else    { s.checkedBookLibids.remove(b.libid) }
                }))
                .labelsHidden()
            Text(b.title)
            Spacer()
            if let n = b.seriesNum { Text("\(n)").foregroundStyle(.secondary) }
            Text(byteCount(b.size)).foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
            Text(date(b.dateAdded)).foregroundStyle(.secondary).frame(width: 90)
            Text(genres(b)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail).frame(maxWidth: 200, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture { s.selectedBookLibid = b.libid }
        .background(s.selectedBookLibid == b.libid ? Color.accentColor.opacity(0.2) : .clear)
        .contextMenu {
            Button("Выгрузить отмеченные (\(s.checkedBookLibids.count))") {
                // The actual export is started by MainWindowView via the
                // `shouldStartExport` flag on AppState (Phase 12.3).
                s.shouldStartExport = true
            }
            .disabled(s.checkedBookLibids.isEmpty)
        }
    }

    private func byteCount(_ n: Int32) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }
    private func date(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        return f.string(from: d)
    }
    private func genres(_ b: Book) -> String {
        // O(1) lookup via the secondary index built in Library.init.
        let names = b.genreIDs.compactMap { library.genreByID[$0]?.name }
        return names.joined(separator: ", ")
    }
}

struct LanguageFilterPicker: View {
    let library: Library
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var s = state
        Picker("Язык книг", selection: $s.languageFilter) {
            ForEach(displayLanguages(), id: \.self) { code in
                Text(label(for: code)).tag(code)
            }
        }
        .pickerStyle(.menu)
    }

    private func displayLanguages() -> [String] {
        var langs = library.languages
        // Replace empty string with our sentinel for the picker.
        langs.removeAll { $0.isEmpty }
        if library.languages.contains("") {
            langs.append(BooksByContext.unspecifiedLanguageToken)
        }
        return langs
    }
    private func label(for code: String) -> String {
        if code == BooksByContext.unspecifiedLanguageToken { return "Не указан" }
        return code.uppercased()
    }
}
