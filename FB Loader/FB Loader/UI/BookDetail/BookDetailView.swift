import SwiftUI
import AppKit

struct BookDetailView: View {
    let library: Library
    let archivesRoot: URL
    let book: Book

    /// Returns true if the current `book` is still the user's active
    /// selection. Used to discard stale `loadDetail` results when the user
    /// has clicked another book mid-load. Owner provides the closure
    /// (main window: AppState's selected libid == book.libid; search sheet:
    /// `coord.selectedBookLibid == book.libid`).
    let isCurrentSelection: () -> Bool

    /// Called when the user taps an author chip in the detail card. Owner
    /// decides what to do (main window: navigate to author tab; search
    /// sheet: no-op for v1).
    let onSelectAuthor: (Int32) -> Void

    /// Called when the user taps the series chip.
    let onSelectSeries: (Int32) -> Void

    @State private var coverImage: NSImage?
    @State private var info: FB2BookInfo?
    @State private var readError: String?
    @State private var translatorsExpanded = false

    /// Шире строку читать тяжело.
    static let textColumnMaxWidth: CGFloat = 680

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            cover
                .padding(.vertical, 16)
            // Метаданные и аннотация прокручиваются одним блоком: при прокрутке
            // шапка уходит вверх и аннотации достаётся вся высота панели.
            // Закреплённая шапка отнимала бы её постоянно.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    meta
                    Divider().padding(.vertical, 12)
                    annotationView
                }
                .frame(maxWidth: Self.textColumnMaxWidth, alignment: .leading)
                .padding(.vertical, 16)
                .padding(.trailing, 20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.automatic)
            .id(book.libid)
        }
        .padding(.leading, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: book.libid) { await loadDetail() }
    }

    // MARK: - Meta

    private var meta: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleAndMeta
            authorsBlock
            HStack(alignment: .top, spacing: 22) {
                seriesBlock
                    .frame(maxWidth: .infinity, alignment: .leading)
                translatorsBlock
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var cover: some View {
        Group {
            if let img = coverImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
            }
        }
        .frame(width: 150, height: 218)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
    }

    private var titleAndMeta: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(book.title)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)

            Text(metaInline)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var metaInline: String {
        var parts: [String] = []
        let genres = book.genreIDs.compactMap { library.genreByID[$0]?.name }
        if !genres.isEmpty { parts.append(genres.joined(separator: " · ")) }
        parts.append(byteCount(book.size))
        if let added = book.dateAdded {
            parts.append(DateFormat.dayMonthYear.string(from: added))
        }
        if let written = info?.dateWritten, !written.isEmpty {
            parts.append("написано \(written)")
        }
        return parts.joined(separator: " · ")
    }

    private var authorsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            label("Авторы")
            FlowLayout(spacing: 4, lineSpacing: 4) {
                ForEach(book.authorIDs, id: \.self) { aid in
                    if let author = library.author(id: aid) {
                        Chip(title: author.displayName) {
                            onSelectAuthor(aid)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var seriesBlock: some View {
        if let sid = book.seriesID, let s = library.series(id: sid) {
            VStack(alignment: .leading, spacing: 4) {
                label("Серия")
                Chip(title: seriesChipTitle(s)) {
                    onSelectSeries(sid)
                }
            }
        } else {
            // Keep the column slot stable when there's no series so the
            // translators column doesn't jump leftward on books without series.
            Color.clear.frame(height: 0)
        }
    }

    private func seriesChipTitle(_ s: Series) -> String {
        if let n = book.seriesNum { return "\(s.name), №\(n)" }
        return s.name
    }

    @ViewBuilder
    private var translatorsBlock: some View {
        if let translators = info?.translators, !translators.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                label("Переводчики")
                Button {
                    translatorsExpanded.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text(translatorsExpanded ? "▾" : "▸")
                        Text(translatorsButtonLabel(count: translators.count))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)

                if translatorsExpanded {
                    Text(translatorsString(translators))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Color.clear.frame(height: 0)
        }
    }

    private func translatorsButtonLabel(count: Int) -> String {
        russianPlural(count, one: "переводчик", few: "переводчика", many: "переводчиков")
    }

    private func translatorsString(_ triples: [INPAuthorParser.Triple]) -> String {
        triples
            .map { [$0.lastName, $0.firstName, $0.middleName].filter { !$0.isEmpty }.joined(separator: " ") }
            .joined(separator: ", ")
    }

    // MARK: - Annotation

    @ViewBuilder
    private var annotationView: some View {
        if let readError {
            Text(readError)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else if let a = info?.annotation, !a.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(annotationParagraphs(a), id: \.self) { p in
                    Text(p)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(NSColor.textColor).opacity(0.85))
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Parser emits "\n\n" between `<p>` blocks. Some files have stray
    /// extra blank lines (consecutive empty-lines), so collapse runs of
    /// blank-only paragraphs to one separator.
    private func annotationParagraphs(_ s: String) -> [String] {
        s.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Helpers

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(.secondary)
    }

    private func byteCount(_ n: Int32) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }

    // MARK: - Loader

    private func loadDetail() async {
        // Clear the previous book's data immediately so the user doesn't stare
        // at stale annotation+cover for the duration of the new book's load.
        info = nil
        coverImage = nil
        readError = nil
        translatorsExpanded = false

        let lib = library
        let root = archivesRoot
        let b = book
        let cache = CoverCache.shared
        await runDetachedCancellable(priority: .utility) {
            let t0 = ContinuousClock.now
            let archiveName = lib.archives[Int(b.archiveIndex)] + ".zip"
            let url = root.appendingPathComponent(archiveName)

            // Fast path: cover image already cached on disk from a prior visit.
            let cachedCover = cache?.cachedImage(for: b)
            if cachedCover != nil, !Task.isCancelled {
                let img = cachedCover
                await MainActor.run {
                    guard isCurrentSelection() else { return }
                    self.coverImage = img
                }
                print("[BookDetail] cover cache hit in \(ContinuousClock.now - t0)")
            }

            do {
                let tRead = ContinuousClock.now
                let fb2 = try ZipFB2Reader.readFB2(entryName: b.archiveEntryName, archiveURL: url)
                print("[BookDetail] read \(fb2.count)B in \(ContinuousClock.now - tRead)")
                if Task.isCancelled { return }

                let tParse = ContinuousClock.now
                let parsed = try FB2DescriptionParser.parse(data: Data(fb2))
                print("[BookDetail] parse in \(ContinuousClock.now - tParse): title=\(parsed.bookTitle ?? "nil") date=\(parsed.dateWritten ?? "nil") cover=\(parsed.coverImageData?.count ?? 0)B")
                if Task.isCancelled { return }

                let img: NSImage? = cachedCover ?? {
                    guard let bytes = parsed.coverImageData else { return nil }
                    return cache?.store(bytes, for: b)
                }()

                print("[BookDetail] total \(ContinuousClock.now - t0)")
                await MainActor.run {
                    guard isCurrentSelection() else { return }
                    self.info = parsed
                    self.coverImage = img
                }
            } catch {
                print("[BookDetail] ERROR in \(ContinuousClock.now - t0): \(error)")
                if Task.isCancelled { return }
                let message = BookReadFailure.message(for: error)
                await MainActor.run {
                    guard isCurrentSelection() else { return }
                    self.readError = message
                }
            }
        }
    }
}
