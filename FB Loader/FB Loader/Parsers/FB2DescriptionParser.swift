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
/// Reads only the prefix needed to find description+cover; the caller can pass
/// just the first ~64 KB of the file.
enum FB2DescriptionParser {
    enum ParseError: Error { case malformed }

    static func parse(data: Data) throws -> FB2BookInfo {
        let delegate = FB2Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        guard parser.parse() else { throw ParseError.malformed }
        // Resolve cover binary by id.
        var cover: Data? = nil
        if let href = delegate.coverHref?.trimmingCharacters(in: .init(charactersIn: "#")),
           let b64 = delegate.binariesByID[href] {
            cover = Data(base64Encoded: b64.replacingOccurrences(of: "\n", with: "")
                                          .replacingOccurrences(of: "\r", with: "")
                                          .trimmingCharacters(in: .whitespaces))
        }
        return FB2BookInfo(
            bookTitle: delegate.bookTitle,
            annotation: delegate.annotation,
            dateWritten: delegate.dateWritten,
            translators: delegate.translators,
            coverImageData: cover
        )
    }
}

private final class FB2Delegate: NSObject, XMLParserDelegate {
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

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
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
        default:
            if section == .annotation { inAnnotationDepth += 1 }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if section == .binary { currentBinaryBuffer += string; return }
        if section == .annotation { annotationBuffer += string; return }
        if inSmallField { currentTextField += string }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
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
