import Testing
import Foundation
@testable import FB_Loader

@Suite("FB2DescriptionParser")
struct FB2DescriptionParserTests {
    @Test("parses sample.fb2 description")
    func parsesSample() throws {
        let url = try #require(TestBundleAnchor.bundle
            .url(forResource: "sample", withExtension: "fb2"))
        let data = try Data(contentsOf: url)
        let info = try FB2DescriptionParser.parse(data: data)
        #expect(info.bookTitle == "Война и мир")
        #expect(info.annotation?.contains("Эпопея") ?? false)
        #expect(info.dateWritten == "1869")
        #expect(info.translators.count == 1)
        #expect(info.translators[0].lastName == "Garnett")
        #expect(info.coverImageData != nil)
    }

    // MARK: - Prefix parsing

    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])

    private static func fb2(
        encoding: String = "utf-8",
        title: String = "Title",
        annotation: String = "<p>Text</p>",
        cover: String? = "#cover",
        binaries: String = "",
        body: String = "<body><section><p>Hi</p></section></body>"
    ) -> String {
        let coverXML = cover.map { "<coverpage><image l:href=\"\($0)\"/></coverpage>" } ?? ""
        return """
        <?xml version="1.0" encoding="\(encoding)"?>
        <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
        <description><title-info><book-title>\(title)</book-title>\
        <annotation>\(annotation)</annotation>\(coverXML)</title-info></description>
        \(body)\(binaries)</FictionBook>
        """
    }

    private static func binary(id: String, quote: String = "\"", data: Data, wrapped: Bool = false) -> String {
        var b64 = data.base64EncodedString()
        if wrapped {
            b64 = stride(from: 0, to: b64.count, by: 8).map { i in
                String(b64.dropFirst(i).prefix(8))
            }.joined(separator: "\r\n")
        }
        return "<binary content-type=\"image/png\" id=\(quote)\(id)\(quote)>\n\(b64)\n</binary>"
    }

    @Test("broken XML in body after description does not affect description or cover")
    func brokenBody() throws {
        let xml = Self.fb2(
            binaries: Self.binary(id: "cover", data: Self.png),
            body: "<body><section><p>unclosed <b></section></body>")
        let info = try FB2DescriptionParser.parse(data: Data(xml.utf8))
        #expect(info.bookTitle == "Title")
        #expect(info.annotation == "Text")
        #expect(info.coverImageData == Self.png)
    }

    @Test("broken description is malformed")
    func brokenDescription() {
        let xml = "<?xml version=\"1.0\"?><FictionBook><description><title-info><book-title>T</title-info></description><body/></FictionBook>"
        #expect(throws: FB2DescriptionParser.ParseError.malformed) {
            try FB2DescriptionParser.parse(data: Data(xml.utf8))
        }
    }

    @Test("missing </description> is malformed")
    func noDescriptionEnd() {
        let xml = "<?xml version=\"1.0\"?><FictionBook><description><title-info><book-title>T</book-title></title-info><body/></FictionBook>"
        #expect(throws: FB2DescriptionParser.ParseError.malformed) {
            try FB2DescriptionParser.parse(data: Data(xml.utf8))
        }
    }

    @Test("cover is picked by id among several binaries")
    func severalBinaries() throws {
        let other = Data([9, 9, 9, 9, 9, 9])
        let binaries = Self.binary(id: "a", data: other)
            + Self.binary(id: "cover", data: Self.png)
            + Self.binary(id: "z", data: other)
        let info = try FB2DescriptionParser.parse(data: Data(Self.fb2(binaries: binaries).utf8))
        #expect(info.coverImageData == Self.png)
    }

    @Test("single-quoted id and base64 with line breaks")
    func singleQuotesWrapped() throws {
        let binaries = Self.binary(id: "cover", quote: "'", data: Self.png, wrapped: true)
        let info = try FB2DescriptionParser.parse(data: Data(Self.fb2(binaries: binaries).utf8))
        #expect(info.coverImageData == Self.png)
    }

    @Test("id attribute before other attributes")
    func idFirst() throws {
        let b64 = Self.png.base64EncodedString()
        let binaries = "<binary id=\"cover\" content-type=\"image/png\">\(b64)</binary>"
        let info = try FB2DescriptionParser.parse(data: Data(Self.fb2(binaries: binaries).utf8))
        #expect(info.coverImageData == Self.png)
    }

    @Test("annotation with nested elements")
    func nestedAnnotation() throws {
        let xml = Self.fb2(annotation: "<p>One <emphasis>two</emphasis> three</p><empty-line/><p>Four</p>")
        let info = try FB2DescriptionParser.parse(data: Data(xml.utf8))
        #expect(info.annotation == "One two three\n\n\n\nFour")
    }

    @Test("windows-1251 description")
    func windows1251() throws {
        let xml = Self.fb2(encoding: "windows-1251", title: "Война и мир", annotation: "<p>Эпопея</p>",
                           binaries: Self.binary(id: "cover", data: Self.png))
        let data = try #require(xml.data(using: .windowsCP1251))
        let info = try FB2DescriptionParser.parse(data: data)
        #expect(info.bookTitle == "Война и мир")
        #expect(info.annotation == "Эпопея")
        #expect(info.coverImageData == Self.png)
    }

    @Test("missing cover binary gives nil without error")
    func missingCoverBinary() throws {
        let binaries = Self.binary(id: "other", data: Self.png)
        let info = try FB2DescriptionParser.parse(data: Data(Self.fb2(binaries: binaries).utf8))
        #expect(info.bookTitle == "Title")
        #expect(info.coverImageData == nil)
    }

    @Test("UTF-16 file is parsed in full")
    func utf16() throws {
        let xml = Self.fb2(encoding: "utf-16", binaries: Self.binary(id: "cover", data: Self.png))
        let data = try #require(xml.data(using: .utf16))
        #expect(data.prefix(2) == Data([0xFF, 0xFE]) || data.prefix(2) == Data([0xFE, 0xFF]))
        let info = try FB2DescriptionParser.parse(data: data)
        #expect(info.bookTitle == "Title")
        #expect(info.coverImageData == Self.png)
    }


    private static func ns(_ body: String) -> String {
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n" + body
    }

    @Test("non-ASCII cover id in windows-1251")
    func cyrillicID() throws {
        let xml = Self.fb2(encoding: "windows-1251", cover: "#обложка",
                           binaries: Self.binary(id: "обложка", data: Self.png))
        let info = try FB2DescriptionParser.parse(data: try #require(xml.data(using: .windowsCP1251)))
        #expect(info.coverImageData == Self.png)
    }

    @Test("cover id with entities")
    func entityID() throws {
        let xml = Self.fb2(cover: "#a&amp;b&#x31;",
                           binaries: Self.binary(id: "a&amp;b&#49;", data: Self.png))
        let info = try FB2DescriptionParser.parse(data: Data(xml.utf8))
        #expect(info.coverImageData == Self.png)
    }

    @Test("</description> inside an earlier comment")
    func descriptionInComment() throws {
        let xml = Self.ns("""
        <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
        <!-- old </description> -->
        <description><title-info><book-title>T</book-title></title-info></description><body/></FictionBook>
        """)
        let info = try FB2DescriptionParser.parse(data: Data(xml.utf8))
        #expect(info.bookTitle == "T")
    }

    @Test("DOCTYPE with internal subset and comment with markup before root")
    func doctypeAndComment() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <!-- <fake> > -->
        <!DOCTYPE FictionBook [ <!ENTITY e "x"> ]>
        <FictionBook><description><title-info><book-title>T</book-title></title-info></description><body/></FictionBook>
        """
        let info = try FB2DescriptionParser.parse(data: Data(xml.utf8))
        #expect(info.bookTitle == "T")
    }

    @Test("UTF-16 without BOM")
    func utf16NoBOM() throws {
        let xml = Self.fb2(encoding: "utf-16", binaries: Self.binary(id: "cover", data: Self.png))
        let data = try #require(xml.data(using: .utf16LittleEndian))
        #expect(data.prefix(2) == Data([0x3C, 0x00]))
        let info = try FB2DescriptionParser.parse(data: data)
        #expect(info.bookTitle == "Title")
        #expect(info.coverImageData == Self.png)
    }

    @Test("binary placed before </description> is used")
    func binaryBeforeDescriptionEnd() throws {
        let b64 = Self.png.base64EncodedString()
        let xml = Self.ns("""
        <FictionBook xmlns:l="http://www.w3.org/1999/xlink"><description><title-info><book-title>T</book-title>\
        <coverpage><image l:href="#cover"/></coverpage></title-info></description>\
        <body/></FictionBook>
        """).replacingOccurrences(of: "<description>", with: "<binary id=\"cover\">\(b64)</binary><description>")
        let info = try FB2DescriptionParser.parse(data: Data(xml.utf8))
        #expect(info.coverImageData == Self.png)
    }

    @Test("namespace prefixes on all elements")
    func prefixed() throws {
        let b64 = Self.png.base64EncodedString()
        let xml = Self.ns("""
        <fb:FictionBook xmlns:fb="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">\
        <fb:description><fb:title-info><fb:book-title>T</fb:book-title>\
        <fb:coverpage><fb:image l:href="#cover"/></fb:coverpage></fb:title-info></fb:description >\
        <fb:body><fb:p>broken</fb:body>\
        <fb:binary id="cover" content-type="image/png">\(b64)</fb:binary ></fb:FictionBook>
        """)
        let info = try FB2DescriptionParser.parse(data: Data(xml.utf8))
        #expect(info.bookTitle == "T")
        #expect(info.coverImageData == Self.png)
    }

    @Test("UTF-8 BOM")
    func utf8BOM() throws {
        let xml = Self.fb2(binaries: Self.binary(id: "cover", data: Self.png))
        let info = try FB2DescriptionParser.parse(data: Data([0xEF, 0xBB, 0xBF]) + Data(xml.utf8))
        #expect(info.bookTitle == "Title")
        #expect(info.coverImageData == Self.png)
    }

    @Test("self-closed binary and xid are not the cover")
    func decoys() throws {
        let other = Data([7, 7, 7, 7])
        let binaries = "<binary id=\"cover\" content-type=\"image/png\"/>"
            + "<binary xid=\"cover\">\(other.base64EncodedString())</binary>"
            + "<binary content-type=\"image/png\" id = 'cover' >\(Self.png.base64EncodedString())</binary>"
        let info = try FB2DescriptionParser.parse(data: Data(Self.fb2(binaries: binaries).utf8))
        #expect(info.coverImageData == Self.png)
    }

    // MARK: - Cover href, aligned with librarium-py

    @Test("XLink href is found under any prefix", arguments: ["xlink", "x"])
    func xlinkPrefix(prefix: String) throws {
        let xml = Self.fb2(binaries: Self.binary(id: "cover", data: Self.png))
            .replacingOccurrences(of: "xmlns:l=", with: "xmlns:\(prefix)=")
            .replacingOccurrences(of: "l:href", with: "\(prefix):href")
        let info = try FB2DescriptionParser.parse(data: Data(xml.utf8))
        #expect(info.coverImageData == Self.png)
    }

    @Test("href under a prefix bound to another namespace is not the cover")
    func foreignPrefix() throws {
        let xml = Self.fb2(cover: nil, binaries: Self.binary(id: "cover", data: Self.png))
            .replacingOccurrences(of: "</title-info>",
                                  with: "<coverpage xmlns:l=\"urn:other\"><image l:href=\"#cover\"/></coverpage></title-info>")
        let info = try FB2DescriptionParser.parse(data: Data(xml.utf8))
        #expect(info.coverImageData == nil)
    }

    @Test("first image of coverpage is the cover")
    func firstImage() throws {
        let other = Data([7, 7, 7, 7])
        let xml = Self.fb2(cover: nil,
                           binaries: Self.binary(id: "cover", data: Self.png) + Self.binary(id: "back", data: other))
            .replacingOccurrences(of: "</title-info>",
                                  with: "<coverpage><image l:href=\"#cover\"/><image l:href=\"#back\"/></coverpage></title-info>")
        let info = try FB2DescriptionParser.parse(data: Data(xml.utf8))
        #expect(info.coverImageData == Self.png)
    }

    @Test("non-base64 characters in binary are skipped")
    func base64Junk() throws {
        var b64 = Self.png.base64EncodedString()
        b64.insert("!", at: b64.index(b64.startIndex, offsetBy: 4))
        let binaries = "<binary content-type=\"image/png\" id=\"cover\">\(b64)</binary>"
        let info = try FB2DescriptionParser.parse(data: Data(Self.fb2(binaries: binaries).utf8))
        #expect(info.coverImageData == Self.png)
    }
}
