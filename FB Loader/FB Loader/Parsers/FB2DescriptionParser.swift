import Foundation

struct FB2BookInfo {
    let bookTitle: String?
    let annotation: String?
    let dateWritten: String?
    let translators: [INPAuthorParser.Triple]
    let coverImageData: Data?
}

/// Takes the whole file: XMLParser sees only the prefix up to `</description>`,
/// the cover is located by a byte search; the book text is never parsed.
nonisolated enum FB2DescriptionParser {
    enum ParseError: Error { case malformed }

    static func parse(data: Data) throws -> FB2BookInfo {
        // The byte search below is ASCII-only, so UTF-16 needs the full XMLParser path.
        if isUTF16(data) { return try parseFully(data) }
        let encoding = declaredEncoding(data)
        var searchFrom = data.startIndex
        // A "</description>" inside a comment/CDATA breaks the prefix; retry with the next one.
        for _ in 0..<3 {
            guard let end = closingTag("description", in: data, from: searchFrom),
                  let rootName = rootElementName(in: data, before: end.lowerBound) else {
                throw ParseError.malformed
            }
            var prefix = data.subdata(in: data.startIndex..<end.upperBound)
            prefix.append(Data("</\(rootName)>".utf8))
            guard let delegate = try? run(prefix) else {
                searchFrom = end.upperBound
                continue
            }
            var cover: Data?
            if let href = delegate.coverHref?.trimmingCharacters(in: .init(charactersIn: "#")) {
                cover = coverBinary(id: href, encoding: encoding, in: data, after: end.upperBound)
                    ?? delegate.binariesByID[href].flatMap { decodeBase64(Data($0.utf8)) }
                // Non-ASCII ids may be spelled in ways the byte search misses.
                if cover == nil, !href.allSatisfy(\.isASCII), let full = try? parseFully(data) {
                    cover = full.coverImageData
                }
            }
            return info(delegate, cover: cover)
        }
        throw ParseError.malformed
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
        parser.shouldReportNamespacePrefixes = true
        guard parser.parse() else { throw ParseError.malformed }
        return delegate
    }

    private static func info(_ d: FB2Delegate, cover: Data?) -> FB2BookInfo {
        FB2BookInfo(bookTitle: d.bookTitle, annotation: d.annotation, dateWritten: d.dateWritten,
                    translators: d.translators, coverImageData: cover)
    }

    private static func isUTF16(_ data: Data) -> Bool {
        data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
            || data.starts(with: [0x3C, 0x00]) || data.starts(with: [0x00, 0x3C])
    }

    private static func declaredEncoding(_ data: Data) -> String.Encoding {
        let head = String(decoding: data.prefix(256).map { $0 < 0x80 ? $0 : 0x3F }, as: UTF8.self)
        guard head.contains("<?xml"),
              let m = head.firstMatch(of: /encoding\s*=\s*["']([^"']+)["']/) else { return .utf8 }
        let cf = CFStringConvertIANACharSetNameToEncoding(String(m.output.1) as CFString)
        guard cf != kCFStringEncodingInvalidId else { return .utf8 }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    }

    private static func rootElementName(in data: Data, before limit: Data.Index) -> String? {
        var i = data.startIndex
        while i < limit {
            guard let lt = data[i..<limit].firstIndex(of: UInt8(ascii: "<")) else { return nil }
            let next = lt + 1
            guard next < limit else { return nil }
            if data[next...].starts(with: Data("!--".utf8)) {
                guard let r = data.range(of: Data("-->".utf8), in: next..<limit) else { return nil }
                i = r.upperBound
            } else if data[next] == UInt8(ascii: "?") {
                guard let r = data.range(of: Data("?>".utf8), in: next..<limit) else { return nil }
                i = r.upperBound
            } else if data[next] == UInt8(ascii: "!") {
                var depth = 0
                var j = next
                while j < limit {
                    let c = data[j]
                    if c == UInt8(ascii: "[") { depth += 1 }
                    else if c == UInt8(ascii: "]") { depth -= 1 }
                    else if c == UInt8(ascii: ">"), depth <= 0 { break }
                    j += 1
                }
                guard j < limit else { return nil }
                i = j + 1
            } else {
                var j = next
                while j < limit, isNameByte(data[j]) { j += 1 }
                return j > next ? String(decoding: data[next..<j], as: UTF8.self) : nil
            }
        }
        return nil
    }

    private static func closingTag(_ local: String, in data: Data, from: Data.Index) -> Range<Data.Index>? {
        var pos = from
        while let m = data.range(of: Data("</".utf8), in: pos..<data.endIndex) {
            pos = m.upperBound
            var j = pos
            while j < data.endIndex, isNameByte(data[j]) { j += 1 }
            guard nameMatches(data[pos..<j], local) else { continue }
            while j < data.endIndex, isXMLSpace(data[j]) { j += 1 }
            if j < data.endIndex, data[j] == UInt8(ascii: ">") { return m.lowerBound..<(j + 1) }
        }
        return nil
    }

    private static func openingTag(_ local: String, in data: Data, from: Data.Index) -> Data.Index? {
        var pos = from
        while let m = data.range(of: Data("<".utf8), in: pos..<data.endIndex) {
            pos = m.upperBound
            var j = pos
            while j < data.endIndex, isNameByte(data[j]) { j += 1 }
            if nameMatches(data[pos..<j], local), j < data.endIndex, isXMLSpace(data[j]) { return j }
        }
        return nil
    }

    private static func nameMatches(_ name: Data, _ local: String) -> Bool {
        let s = String(decoding: name, as: UTF8.self)
        return s == local || s.hasSuffix(":" + local)
    }

    private static func coverBinary(id: String, encoding: String.Encoding, in data: Data, after start: Data.Index) -> Data? {
        var pos = start
        while let nameEnd = openingTag("binary", in: data, from: pos) {
            pos = nameEnd
            guard let gt = tagEnd(in: data, from: nameEnd) else { return nil }
            pos = gt
            if data[gt - 1] == UInt8(ascii: "/") { continue }
            guard let raw = idAttribute(in: data[nameEnd..<gt]),
                  let decoded = String(data: raw, encoding: encoding),
                  decodeEntities(decoded) == id else { continue }
            let bodyStart = gt + 1
            guard let close = closingTag("binary", in: data, from: bodyStart) else { return nil }
            return decodeBase64(data[bodyStart..<close.lowerBound])
        }
        return nil
    }

    private static func tagEnd(in data: Data, from: Data.Index) -> Data.Index? {
        var quote: UInt8?
        var i = from
        while i < data.endIndex {
            let b = data[i]
            if let q = quote { if b == q { quote = nil } }
            else if b == UInt8(ascii: "\"") || b == UInt8(ascii: "'") { quote = b }
            else if b == UInt8(ascii: ">") { return i }
            i += 1
        }
        return nil
    }

    private static func idAttribute(in tag: Data) -> Data? {
        var i = tag.startIndex
        let end = tag.endIndex
        func skipSpace() { while i < end, isXMLSpace(tag[i]) { i += 1 } }
        while i < end {
            skipSpace()
            let nameStart = i
            while i < end, isNameByte(tag[i]) { i += 1 }
            let name = tag[nameStart..<i]
            skipSpace()
            guard i < end, tag[i] == UInt8(ascii: "="), !name.isEmpty else { return nil }
            i += 1
            skipSpace()
            guard i < end, tag[i] == UInt8(ascii: "\"") || tag[i] == UInt8(ascii: "'") else { return nil }
            let q = tag[i]
            i += 1
            let valueStart = i
            while i < end, tag[i] != q { i += 1 }
            guard i < end else { return nil }
            if name.elementsEqual("id".utf8) { return tag[valueStart..<i] }
            i += 1
        }
        return nil
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacing(/&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);/) { m in
            let body = String(m.output.1)
            switch body {
            case "amp": return "&"
            case "lt": return "<"
            case "gt": return ">"
            case "quot": return "\""
            case "apos": return "'"
            default:
                let code = body.hasPrefix("#x") ? UInt32(body.dropFirst(2), radix: 16) : UInt32(body.dropFirst())
                return code.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? String(m.output.0)
            }
        }
    }

    private static func decodeBase64(_ raw: Data) -> Data? {
        let cleaned = Data(raw.filter { !isXMLSpace($0) })
        guard !cleaned.isEmpty else { return nil }
        // Like Python's b64decode in librarium-py: stray characters are dropped, not fatal.
        return Data(base64Encoded: cleaned, options: .ignoreUnknownCharacters)
    }

    private static func isNameByte(_ b: UInt8) -> Bool {
        (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
            || b == UInt8(ascii: "_") || b == UInt8(ascii: "-") || b == UInt8(ascii: ".") || b == UInt8(ascii: ":")
    }

    private static func isXMLSpace(_ b: UInt8) -> Bool {
        b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D
    }
}

/// Owned by a single `parse(data:)` call and never escapes, hence not Sendable.
private nonisolated final class FB2Delegate: NSObject, XMLParserDelegate {
    private enum Section { case none, titleInfo, author, translator, annotation, coverpage, binary }
    private var section: Section = .none
    private var inDescription = false
    private var currentBinaryID: String?
    private var currentBinaryBuffer = ""
    private var currentTextField: String = ""

    var bookTitle: String?
    var annotation: String?
    var dateWritten: String?
    var translators: [INPAuthorParser.Triple] = []
    var coverHref: String?
    var binariesByID: [String: String] = [:]

    private static let xlinkURI = "http://www.w3.org/1999/xlink"
    /// XMLParser keys attributes by the file's own prefix (`l:href`, `xlink:href`, …), so the
    /// XLink one is resolved through the prefix bindings in scope.
    private var prefixURIs: [String: [String]] = [:]

    private var translatorBuilder: (last: String, first: String, middle: String) = ("", "", "")
    /// Leaf text fields (names, title, date) never nest in valid FB2, so a Bool is enough.
    private var inSmallField = false
    private var annotationBuffer = ""
    private var inAnnotationDepth = 0
    /// Off → `foundCharacters` skips inter-tag whitespace from pretty-printing.
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
            if coverHref == nil { coverHref = xlinkHref(attributeDict) }
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

    func parser(_ _: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
        prefixURIs[prefix, default: []].append(namespaceURI)
    }

    func parser(_ _: XMLParser, didEndMappingPrefix prefix: String) {
        _ = prefixURIs[prefix]?.popLast()
    }

    private func xlinkHref(_ attributes: [String: String]) -> String? {
        for (key, value) in attributes {
            let parts = key.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[1] == "href",
               prefixURIs[String(parts[0])]?.last == Self.xlinkURI { return value }
        }
        return attributes["href"]
    }

    func parser(_ _: XMLParser, foundCharacters string: String) {
        if section == .binary { currentBinaryBuffer += string; return }
        if section == .annotation {
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
