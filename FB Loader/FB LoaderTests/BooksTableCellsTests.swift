import AppKit
import Testing
@testable import FB_Loader

@Suite("BooksTable cells")
@MainActor
struct BooksTableCellsTests {
    private func book(_ title: String) -> Book {
        Book(libid: 7, title: title, authorIDs: [1], seriesID: nil, seriesNum: nil,
             genreIDs: [], language: "ru", archiveIndex: 0, size: 0, dateAdded: nil)
    }

    @Test("галочка: не берёт фокус, роль checkbox, нажатие VoiceOver переключает")
    func checkbox() {
        let box = BookCheckbox()
        var toggles = 0
        box.onToggle = { toggles += 1 }
        #expect(box.refusesFirstResponder)
        #expect(!box.acceptsFirstResponder)
        #expect(box.accessibilityRole() == .checkBox)
        #expect(box.accessibilityValue() as? NSNumber == 0)
        box.isOn = true
        #expect(box.accessibilityValue() as? NSNumber == 1)
        #expect(box.accessibilityPerformPress())
        #expect(toggles == 1)
    }

    @Test("ячейка названия: отступ 16 вне серии и 30 в серии, выбранная — жирная, метка галочки")
    func titleCell() {
        let cell = BookTitleCellView()
        cell.configure(book: book("Война и мир"), inSeries: false, isChecked: true, isSelected: false, onToggle: {})
        #expect(cell.leadingInset == 16)
        #expect(!cell.showsSelected)
        #expect(cell.checkbox.isOn)
        #expect(cell.titleLabel.stringValue == "Война и мир")
        #expect(cell.textField === cell.titleLabel)
        #expect(cell.checkbox.accessibilityLabel() == "Отметить: Война и мир")

        cell.configure(book: book("Б"), inSeries: true, isChecked: false, isSelected: true, onToggle: {})
        #expect(cell.leadingInset == 30)
        #expect(cell.showsSelected)
        #expect(!cell.checkbox.isOn)
    }

    @Test("акцентное выделение переключает вид галочки")
    func emphasized() {
        let cell = BookTitleCellView()
        cell.backgroundStyle = .emphasized
        #expect(cell.checkbox.isEmphasized)
        cell.backgroundStyle = .normal
        #expect(!cell.checkbox.isEmphasized)
    }

    @Test("ячейки чисел — по правому краю, жанры — по левому")
    func textCells() {
        for id in [BookTableColumnID.num, .size, .date] {
            let cell = BookTextCellView(column: id)
            #expect(cell.label.alignment == .right)
            #expect(cell.textField === cell.label)
        }
        let genres = BookTextCellView(column: .genres)
        #expect(genres.label.alignment == .left)
        genres.configure(text: "Фантастика, Детектив")
        #expect(genres.label.stringValue == "Фантастика, Детектив")
    }

    @Test("заголовок серии: имя и (N)")
    func seriesHeader() {
        let cell = SeriesHeaderCellView()
        cell.configure(series: Series(id: 1, name: "Дюна"), count: 3)
        #expect(cell.nameLabel.stringValue == "Дюна")
        #expect(cell.countLabel.stringValue == "(3)")
    }

    @Test("идентификаторы колонок")
    func identifiers() {
        #expect(BookTableColumnID.title.identifier.rawValue == "title")
        #expect(BookTableColumnID.genres.identifier.rawValue == "genres")
    }
}
