import SwiftUI
import AppKit

struct BookDetailView: View {
    let library: Library
    let archivesRoot: URL
    let book: Book
    @Environment(AppState.self) private var state
    @State private var coverImage: NSImage?
    @State private var info: FB2BookInfo?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(book.title).font(.title)
                HStack(alignment: .top, spacing: 6) {
                    Text("Авторы:").bold().frame(width: 110, alignment: .trailing)
                    HStack(spacing: 4) {
                        ForEach(book.authorIDs, id: \.self) { aid in
                            if let author = library.authorByID[aid] {
                                Button(author.displayName) {
                                    state.sidebarTab = .authors
                                    state.selectedAuthorID = aid
                                    state.selectedSeriesID = nil
                                }
                                .buttonStyle(.link)
                            }
                            if aid != book.authorIDs.last { Text(";") }
                        }
                    }
                }
                row(label: "Жанры", text: genresString)
                if let sid = book.seriesID, let s = library.seriesByID[sid] {
                    HStack(alignment: .top, spacing: 6) {
                        Text("Серия:").bold().frame(width: 110, alignment: .trailing)
                        Button(seriesString ?? s.name) {
                            state.sidebarTab = .series
                            state.selectedSeriesID = sid
                            state.selectedAuthorID = nil
                        }
                        .buttonStyle(.link)
                    }
                }
                if let d = info?.dateWritten { row(label: "Дата написания", text: d) }
                if let t = translatorsString { row(label: "Переводчики", text: t) }
                if let a = info?.annotation, !a.isEmpty {
                    Divider()
                    Text(a).font(.body)
                }
            }
            Spacer(minLength: 0)
            if let img = coverImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 220, maxHeight: 320)
            }
        }
        .padding(12)
        .task(id: book.libid) { await loadDetail() }
    }

    private func row(label: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label + ":").bold().frame(width: 110, alignment: .trailing)
            Text(text)
        }
    }

    private var authorsString: String {
        // O(1) lookup via the secondary index built in Library.init.
        book.authorIDs.compactMap { library.authorByID[$0]?.displayName }
            .joined(separator: "; ")
    }
    private var genresString: String {
        book.genreIDs.compactMap { library.genreByID[$0]?.name }
            .joined(separator: ", ")
    }
    private var seriesString: String? {
        guard let sid = book.seriesID, let s = library.seriesByID[sid] else { return nil }
        if let n = book.seriesNum { return "\(s.name), №\(n)" }
        return s.name
    }
    private var translatorsString: String? {
        guard let info, !info.translators.isEmpty else { return nil }
        return info.translators
            .map { [$0.lastName, $0.firstName, $0.middleName].filter { !$0.isEmpty }.joined(separator: " ") }
            .joined(separator: ", ")
    }

    private func loadDetail() async {
        let lib = library
        let root = archivesRoot
        let b = book
        let cache = try? CoverCache()
        await Task.detached(priority: .utility) {
            let archiveName = lib.archives[Int(b.archiveIndex)] + ".zip"
            let url = root.appendingPathComponent(archiveName)
            print("[BookDetail] libid=\(b.libid) archive=\(url.path)")
            print("[BookDetail]   archive exists: \(FileManager.default.fileExists(atPath: url.path))")
            do {
                let fb2 = try ZipFB2Reader.readFB2(libid: b.libid, archiveURL: url)
                print("[BookDetail]   read .fb2: \(fb2.count) bytes")
                let parsed = try FB2DescriptionParser.parse(data: fb2.prefix(64 * 1024))
                print("[BookDetail]   parsed: title=\(parsed.bookTitle ?? "nil") date=\(parsed.dateWritten ?? "nil") cover=\(parsed.coverImageData?.count ?? 0)B")
                let img = cache?.image(for: b, in: lib, archivesRoot: root)
                print("[BookDetail]   NSImage: \(img == nil ? "nil" : "ok")")
                await MainActor.run {
                    self.info = parsed
                    self.coverImage = img
                }
            } catch {
                print("[BookDetail]   ERROR: \(error)")
                await MainActor.run {
                    self.info = nil
                    self.coverImage = nil
                }
            }
        }.value
    }
}
