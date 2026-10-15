import Testing
import Foundation
@testable import FB_Loader

@Suite("BookTableColumns")
struct BookTableColumnsTests {
    private typealias C = BookTableColumns

    /// Ширина панели, при которой Название получает ровно `titleMinWidth`
    /// при заданном наборе колонок.
    private func paneWidth(size: Bool, genres: Bool) -> CGFloat {
        var fixed = C.checkboxWidth + C.numWidth + C.dateWidth
        var gaps: CGFloat = 3
        if size { fixed += C.sizeWidth; gaps += 1 }
        if genres { fixed += C.genresMinWidth; gaps += 1 }
        return C.horizontalPadding + fixed + gaps * C.spacing + C.titleMinWidth
    }

    @Test("широкая панель — все колонки, Жанры шире идеала")
    func wide() {
        let c = C.visibleColumns(forWidth: 1400)
        #expect(c.showsSize)
        #expect(c.showsGenres)
        #expect(c.genresWidth > C.genresIdealWidth)
    }

    @Test("на пороге все колонки видны, Жанры — минимальной ширины")
    func atGenresThreshold() {
        let c = C.visibleColumns(forWidth: paneWidth(size: true, genres: true))
        #expect(c.showsSize)
        #expect(c.showsGenres)
        #expect(c.genresWidth == C.genresMinWidth)
    }

    @Test("чуть уже порога — первыми скрываются Жанры")
    func belowGenresThreshold() {
        let c = C.visibleColumns(forWidth: paneWidth(size: true, genres: true) - 1)
        #expect(c.showsSize)
        #expect(!c.showsGenres)
    }

    @Test("ещё уже — скрывается и Размер")
    func belowSizeThreshold() {
        let atSize = C.visibleColumns(forWidth: paneWidth(size: true, genres: false))
        #expect(atSize.showsSize)
        let c = C.visibleColumns(forWidth: paneWidth(size: true, genres: false) - 1)
        #expect(!c.showsSize)
        #expect(!c.showsGenres)
    }

    @Test("пороги в пунктах: Жанры скрыты уже 640, Размер — уже 510")
    func literalThresholds() {
        #expect(C.visibleColumns(forWidth: 640).showsGenres)
        #expect(!C.visibleColumns(forWidth: 639).showsGenres)
        #expect(C.visibleColumns(forWidth: 510).showsSize)
        #expect(!C.visibleColumns(forWidth: 509).showsSize)
    }

    @Test("Жанры никогда не видны без Размера")
    func genresHiddenBeforeSize() {
        for w in stride(from: CGFloat(0), through: 2000, by: 5) {
            let c = C.visibleColumns(forWidth: w)
            #expect(!(c.showsGenres && !c.showsSize), "width \(w)")
        }
    }

    @Test("Жанры не уже минимума, Название не уже Жанров и своего минимума")
    func titleKeepsPriority() {
        for w in stride(from: paneWidth(size: true, genres: true), through: 3000, by: 7) {
            let c = C.visibleColumns(forWidth: w)
            let flex = w - C.horizontalPadding - C.checkboxWidth - C.numWidth
                - C.sizeWidth - C.dateWidth - 5 * C.spacing
            let title = flex - c.genresWidth
            #expect(c.genresWidth >= C.genresMinWidth, "width \(w)")
            #expect(title >= c.genresWidth, "width \(w)")
            #expect(title >= C.titleMinWidth, "width \(w)")
        }
    }

    @Test("при типичной ширине панели Жанры не уже идеала")
    func genresReachIdeal() {
        #expect(C.visibleColumns(forWidth: 1100).genresWidth >= C.genresIdealWidth)
    }

    @Test("минимальная ширина панели вмещает постоянные колонки вложенной строки")
    func minimumPaneWidthFitsIndentedRow() {
        let c = C.visibleColumns(forWidth: C.minimumPaneWidth)
        #expect(!c.showsSize)
        #expect(!c.showsGenres)
        let fixed = C.checkboxWidth + C.numWidth + C.dateWidth + 3 * C.spacing
        let title = C.minimumPaneWidth - C.horizontalPadding - C.indent - fixed
        #expect(title >= C.titleMinWidth)
    }

    @Test("стандартный набор — все колонки, Жанры идеальной ширины")
    func standard() {
        #expect(C.standard.showsSize)
        #expect(C.standard.showsGenres)
        #expect(C.standard.genresWidth == C.genresIdealWidth)
    }

    @Test("columnLayout: сумма ширин = ширине, Дата видна, последняя колонка содержит 16 справа",
          arguments: [CGFloat(1400), 640, 639, 510, 509, BookTableColumns.minimumPaneWidth])
    func columnLayoutSums(width: CGFloat) {
        let l = C.columnLayout(forWidth: width)
        let v = C.visibleColumns(forWidth: width)
        #expect(l.totalWidth == width)
        #expect(l.num == C.spacing + C.numWidth)
        #expect((l.size != nil) == v.showsSize)
        #expect((l.genres != nil) == v.showsGenres)
        if let genres = l.genres {
            #expect(genres == C.spacing + v.genresWidth + C.rowInset)
            #expect(l.date == C.spacing + C.dateWidth)
        } else {
            #expect(l.date == C.spacing + C.dateWidth + C.rowInset)
        }
        #expect(l.title >= C.rowInset + C.checkboxWidth + C.spacing + C.titleMinWidth)
        #expect(l.width(of: .date) == l.date)
        #expect(l.width(of: .size) == l.size)
        #expect(l.width(of: .genres) == l.genres)
    }

    @Test("заголовки колонок")
    func headerTitles() {
        #expect(BookTableColumnID.allCases.map(\.headerTitle) == ["Название", "№", "Размер", "Дата", "Жанры"])
    }
}
