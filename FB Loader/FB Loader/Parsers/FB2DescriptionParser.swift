import Foundation

struct FB2BookInfo {
    let bookTitle: String?
    let annotation: String?
    let dateWritten: String?
    let translators: [INPAuthorParser.Triple]
    let coverImageData: Data?
}

/// Parses the `<description>` block of an FB2 file plus the `<binary>` element
/// referenced by `<coverpage><image l:href="#..."/>`.
/// Takes the whole file: XMLParser sees only the prefix up to `</description>`,
/// the cover is located by a byte search; the book text is never parsed.
///
/// `nonisolated` — pure parser, no UI state. Without this it would be inferred
/// as MainActor (project default) and reject calls from `Task.detached`.
nonisolated enum FB2DescriptionParser {
    enum ParseError: Error { case malformed }

    static func parse(data: Data) throws -> FB2BookInfo {
        // The byte search below is ASCII-only, so UTF-16 needs the full XMLParser path.
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return try parseFully(data)
        }
        guard let end = data.range(of: Data("</description>".utf8)),
              let rootName = rootElementName(in: data, before: end.lowerBound) else {
            throw ParseError.malformed
        }
        // Closing the root makes the prefix well-formed without touching the declared encoding.
        var prefix = data.subdata(in: data.startIndex..<end.upperBound)
        prefix.append(Data("</\(rootName)>".utf8))
        let delegate = try run(prefix)
        var cover: Data?
        if let href = delegate.coverHref?.trimmingCharacters(in: .init(charactersIn: "#")) {
            cover = coverBinary(id: href, in: data, after: end.upperBound)
        }
        return info(delegate, cover: cover)
    }

    private static func parseFully(_ data: Data) throws -> FB2BookInfo {
        let delegate = try run(data)
        var cover: Data?
        if let href = delegate.coverHref?.trimmingCharacters(in: .init(charactersIn: "#")),
           let b64 = delegate.binariesByID[href] {
            cover = decodeBase64(Data(b64.utf8))
        }
        return info(delegate, cover: cover)
    }

    private static func run(_ data: Data) throws -> FB2Delegate {
        let delegate = FB2Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        guard parser.parse() else { throw ParseError.malformed }
        return delegate
    }

    private static func info(_ d: FB2Delegate, cover: Data?) -> FB2BookInfo {
        FB2BookInfo(bookTitle: d.bookTitle, annotation: d.annotation, dateWritten: d.dateWritten,
                    translators: d.translators, coverImageData: cover)
    }

    /// Qualified name of the first real element (skips `<?xml?>`, comments, DOCTYPE).
    private static func rootElementName(in data: Data, before limit: Data.Index) -> String? {
        var i = data.startIndex
        while i < limit {
            guard let lt = data[i..<limit].firstIndex(of: UInt8(ascii: "<")) else { return nil }
            let next = lt + 1
            guard next < limit else { return nil }
            let c = data[next]
            if c == UInt8(ascii: "?") || c == UInt8(ascii: "!") {
                guard let gt = data[next..<limit].firstIndex(of: UInt8(ascii: ">")) else { return nil }
                i = gt + 1
                continue
            }
            var j = next
            while j < limit, !isXMLSpace(data[j]), data[j] != UInt8(ascii: ">"), data[j] != UInt8(ascii: "/") { j += 1 }
            return String(decoding: data[next..<j], as: UTF8.self)
        }
        return nil
    }

    private static func coverBinary(id: String, in data: Data, after start: Data.Index) -> Data? {
        let open = Data("<binary".utf8)
        let close = Data("</binary>".utf8)
        var pos = start
        while let tag = data.range(of: open, in: pos..<data.endIndex) {
            pos = tag.upperBound
            guard pos < data.endIndex, isXMLSpace(data[pos]),
                  let gt = data[pos...].firstIndex(of: UInt8(ascii: ">")) else { continue }
            if data[gt - 1] == UInt8(ascii: "/") { continue }
            guard binaryID(in: data[pos..<gt]) == id else { continue }
            let bodyStart = gt + 1
            guard let end = data.range(of: close, in: bodyStart..<data.endIndex) else { return nil }
            return decodeBase64(data[bodyStart..<end.lowerBound])
        }
        return nil
    }

    private static func binaryID(in attributes: Data) -> String? {
        let text = String(decoding: attributes, as: UTF8.self)
        let regex = /(?:^|\s)id\s*=\s*(?:"([^"]*)"|'([^']*)')/
        guard let m = text.firstMatch(of: regex) else { return nil }
        return String(m.output.1 ?? m.output.2 ?? "")
    }

    private static func decodeBase64(_ raw: Data) -> Data? {
        let cleaned = Data(raw.filter { !isXMLSpace($0) })
        guard !cleaned.isEmpty else { return nil }
        return Data(base64Encoded: cleaned)
    }

    private static func isXMLSpace(_ b: UInt8) -> Bool {
        b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D
    }
}

/// Internal SAX state machine. `nonisolated` so XMLParser can drive it from
/// `parse(data:)` (which is itself nonisolated). Not Sendable: it's owned by
/// a single `parse(data:)` invocation and never escapes.
private nonisolated final class FB2Delegate: NSObject, XMLParserDelegate {
    // State machine
    private enum Section { case none, titleInfo, author, translator, annotation, coverpage, binary }
    private var section: Section = .none
    private var inDescription = false
    private var currentBinaryID: String?
    private var currentBinaryBuffer = ""
    private var currentTextField: String = "" // accumulator for text() inside small fields

    var bookTitle: String?
    var annotation: String?
    var dateWritten: String?
    var translators: [INPAuthorParser.Triple] = []
    var coverHref: String?
    var binariesByID: [String: String] = [:]

    private var translatorBuilder: (last: String, first: String, middle: String) = ("", "", "")
    /// `true` while we're inside one of the leaf text fields we care about
    /// (first-name / last-name / middle-name / book-title / date). These never
    /// nest in valid FB2, so a Bool is enough.
    private var inSmallField = false
    private var annotationBuffer = ""
    private var inAnnotationDepth = 0
    /// `true` while we're inside `<p>` (or other text-bearing element we treat
    /// as a paragraph) within `<annotation>`. Off → `foundCharacters` skips
    /// inter-tag whitespace from pretty-printing instead of accumulating it.
    private var inAnnotationParagraph = false

    func parser(_ _: XMLParser,
                didStartElement elementName: String,
                namespaceURI _: String?,
                qualifiedName _: String?,
                attributes attributeDict: [String : String] = [:]) {
        let n = elementName.lowercased()
        if n == "description" { inDescription = true }
        guard inDescription else {
            if n == "binary" {
                section = .binary
                currentBinaryID = attributeDict["id"]
                currentBinaryBuffer = ""
            }
            return
        }
        switch n {
        case "title-info": section = .titleInfo
        case "author" where section == .titleInfo: section = .author
        case "translator" where section == .titleInfo:
            section = .translator
            translatorBuilder = ("", "", "")
        case "annotation" where section == .titleInfo:
            section = .annotation
            annotationBuffer = ""
            inAnnotationDepth = 1
        case "coverpage" where section == .titleInfo: section = .coverpage
        case "image" where section == .coverpage:
            if let href = attributeDict["href"] ?? attributeDict["l:href"] {
                coverHref = href
            }
        case "first-name", "last-name", "middle-name", "book-title", "date":
            currentTextField = ""
            inSmallField = true
        case "p" where section == .annotation:
            inAnnotationDepth += 1
            inAnnotationParagraph = true
        case "empty-line" where section == .annotation:
            // Self-closing — synthesize a blank-line break.
            annotationBuffer += "\n\n"
        default:
            if section == .annotation { inAnnotationDepth += 1 }
        }
    }

    func parser(_ _: XMLParser, foundCharacters string: String) {
        if section == .binary { currentBinaryBuffer += string; return }
        if section == .annotation {
            // Skip inter-tag whitespace from FB2 pretty-printing — only keep
            // characters that live inside an actual `<p>` (or similar).
            if inAnnotationParagraph { annotationBuffer += string }
            return
        }
        if inSmallField { currentTextField += string }
    }

    func parser(_ _: XMLParser,
                didEndElement elementName: String,
                namespaceURI _: String?,
                qualifiedName _: String?) {
        let n = elementName.lowercased()
        switch n {
        case "binary":
            if let id = currentBinaryID { binariesByID[id] = currentBinaryBuffer }
            section = .none
        case "first-name", "last-name", "middle-name", "book-title", "date":
            let value = currentTextField.trimmingCharacters(in: .whitespacesAndNewlines)
            inSmallField = false
            switch (section, n) {
            case (.titleInfo, "book-title"): bookTitle = value
            case (.titleInfo, "date"): dateWritten = value
            case (.translator, "first-name"): translatorBuilder.first = value
            case (.translator, "last-name"): translatorBuilder.last = value
            case (.translator, "middle-name"): translatorBuilder.middle = value
            default: break
            }
        case "translator":
            translators.append(.init(
                lastName: translatorBuilder.last,
                firstName: translatorBuilder.first,
                middleName: translatorBuilder.middle))
            section = .titleInfo
        case "author" where section == .author: section = .titleInfo
        case "coverpage" where section == .coverpage: section = .titleInfo
        case "p" where section == .annotation:
            inAnnotationDepth -= 1
            inAnnotationParagraph = false
            annotationBuffer += "\n\n"
        case "annotation":
            inAnnotationDepth -= 1
            if inAnnotationDepth <= 0 {
                annotation = annotationBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                section = .titleInfo
            }
        case "title-info" where section == .titleInfo: section = .none
        case "description": inDescription = false
        default:
            if section == .annotation { inAnnotationDepth -= 1 }
        }
    }
}
