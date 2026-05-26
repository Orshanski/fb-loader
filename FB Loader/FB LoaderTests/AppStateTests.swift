import Testing
@testable import FB_Loader

@Suite("AppStateTests")
@MainActor
struct AppStateTests {

    @Test("Дефолт: .authors(nil), пустые per-tab поля")
    func defaultState() {
        let s = AppState()
        #expect(s.sidebar == .authors(nil))
        #expect(s.selectedBookLibid == nil)
        #expect(s.sidebarFilter == "")
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.languageFilter == "ru")
    }

    @Test("selectSection — смена case'а сбрасывает per-tab")
    func selectSectionSwitchesCase() {
        let s = AppState()
        s.selectSection(.series(99))
        s.selectedBookLibid = 7
        s.sidebarFilter = "abc"
        s.checkedBookLibids = [1, 2]
        s.languageFilter = "en"

        s.selectSection(.authors(nil))

        #expect(s.sidebar == .authors(nil))
        #expect(s.selectedBookLibid == nil)
        #expect(s.sidebarFilter == "")
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.languageFilter == "en")
    }

    @Test("selectSection — точный no-op при равном sidebar")
    func selectSectionExactNoop() {
        let s = AppState()
        s.selectSection(.authors(10))
        s.sidebarFilter = "x"
        s.checkedBookLibids = [1]
        s.selectedBookLibid = 7
        s.languageFilter = "en"

        s.selectSection(.authors(10))

        #expect(s.sidebar == .authors(10))
        #expect(s.sidebarFilter == "x")
        #expect(s.checkedBookLibids == [1])
        #expect(s.selectedBookLibid == 7)
        #expect(s.languageFilter == "en")
    }

    @Test("selectSection — same-case другой ID: полный сброс")
    func selectSectionSameCaseDifferentID() {
        let s = AppState()
        s.selectSection(.authors(10))
        s.sidebarFilter = "x"
        s.checkedBookLibids = [1]
        s.selectedBookLibid = 7
        s.languageFilter = "en"

        s.selectSection(.authors(nil))

        #expect(s.sidebar == .authors(nil))
        #expect(s.sidebarFilter == "")
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.selectedBookLibid == nil)
        #expect(s.languageFilter == "en")
    }

    @Test("selectAuthor без имени — same-case другой ID: гасит preview и галочки")
    func selectAuthorClickInList() {
        let s = AppState()
        s.selectSection(.authors(10))
        s.sidebarFilter = "x"
        s.checkedBookLibids = [1]
        s.selectedBookLibid = 7

        s.selectAuthor(42)

        #expect(s.sidebar == .authors(42))
        #expect(s.selectedBookLibid == nil)
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.sidebarFilter == "x")
    }

    @Test("selectAuthor без имени — same-ID no-op")
    func selectAuthorSameIDNoop() {
        let s = AppState()
        s.selectSection(.authors(10))
        s.sidebarFilter = "x"
        s.checkedBookLibids = [1]
        s.selectedBookLibid = 7

        s.selectAuthor(10)

        #expect(s.sidebar == .authors(10))
        #expect(s.selectedBookLibid == 7)
        #expect(s.checkedBookLibids == [1])
        #expect(s.sidebarFilter == "x")
    }

    @Test("selectAuthor с именем — cross-section: фильтр в имя, preview сохраняется")
    func selectAuthorDeepLinkCrossSection() {
        let s = AppState()
        s.selectSection(.series(99))
        s.selectedBookLibid = 7
        s.sidebarFilter = "x"
        s.checkedBookLibids = [1]
        s.languageFilter = "en"

        s.selectAuthor(42, deepLinkName: "Иванов")

        #expect(s.sidebar == .authors(42))
        #expect(s.sidebarFilter == "Иванов")
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.selectedBookLibid == 7)
        #expect(s.languageFilter == "en")
    }

    @Test("selectAuthor с именем — same-section: фильтр перезаписан, preview сохранён")
    func selectAuthorDeepLinkSameSection() {
        let s = AppState()
        s.selectSection(.authors(10))
        s.sidebarFilter = "Толстой"
        s.checkedBookLibids = [1]
        s.selectedBookLibid = 7

        s.selectAuthor(42, deepLinkName: "Иванов")

        #expect(s.sidebar == .authors(42))
        #expect(s.sidebarFilter == "Иванов")
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.selectedBookLibid == 7)
    }

    @Test("selectAuthor с именем — same-ID re-click: идемпотентный прицел")
    func selectAuthorDeepLinkSameIDIdempotent() {
        let s = AppState()
        s.selectSection(.authors(10))
        s.sidebarFilter = "Толстой"
        s.checkedBookLibids = [1]
        s.selectedBookLibid = 7

        s.selectAuthor(10, deepLinkName: "Иванов")

        #expect(s.sidebar == .authors(10))
        #expect(s.sidebarFilter == "Иванов")
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.selectedBookLibid == 7)
    }

    @Test("selectSeries с именем — симметрично selectAuthor")
    func selectSeriesDeepLink() {
        let s = AppState()
        s.selectSection(.authors(10))
        s.sidebarFilter = "x"
        s.checkedBookLibids = [1]
        s.selectedBookLibid = 7

        s.selectSeries(55, deepLinkName: "Ахейский цикл")

        #expect(s.sidebar == .series(55))
        #expect(s.sidebarFilter == "Ахейский цикл")
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.selectedBookLibid == 7)
    }

    @Test("selectGenre — без имени, как клик в списке")
    func selectGenreClickInList() {
        let s = AppState()
        s.selectSection(.series(99))
        s.selectedBookLibid = 7
        s.checkedBookLibids = [1]
        s.sidebarFilter = "x"

        s.selectGenre(7)

        #expect(s.sidebar == .genres(7))
        #expect(s.selectedBookLibid == nil)
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.sidebarFilter == "x")
    }

    @Test("selectAuthor(nil) внутри секции — same-section с nil ID")
    func selectAuthorNilInsideSection() {
        let s = AppState()
        s.selectSection(.authors(10))
        s.sidebarFilter = "x"
        s.checkedBookLibids = [1]
        s.selectedBookLibid = 7

        s.selectAuthor(nil)

        #expect(s.sidebar == .authors(nil))
        #expect(s.selectedBookLibid == nil)
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.sidebarFilter == "x")
    }

    @Test("reset — sidebar=.authors(nil), все per-tab и language к дефолтам")
    func resetState() {
        let s = AppState()
        s.selectSection(.series(99))
        s.selectedBookLibid = 7
        s.sidebarFilter = "x"
        s.checkedBookLibids = [1]
        s.languageFilter = "en"

        s.reset()

        #expect(s.sidebar == .authors(nil))
        #expect(s.selectedBookLibid == nil)
        #expect(s.sidebarFilter == "")
        #expect(s.checkedBookLibids.isEmpty)
        #expect(s.languageFilter == "ru")
    }
}
