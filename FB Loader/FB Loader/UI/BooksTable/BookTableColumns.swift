import CoreGraphics

/// Какие колонки таблицы книг видны и какой ширины «Жанры» при данной
/// ширине панели. Одна функция на шапку и строки — иначе подписи разъедутся
/// со значениями.
nonisolated struct BookTableColumns: Equatable, Sendable {
    var showsSize: Bool
    var showsGenres: Bool
    var genresWidth: CGFloat

    static let checkboxWidth: CGFloat = 28
    static let numWidth: CGFloat = 50
    static let sizeWidth: CGFloat = 80
    static let dateWidth: CGFloat = 100
    static let genresMinWidth: CGFloat = 120
    static let genresIdealWidth: CGFloat = 220
    static let titleMinWidth: CGFloat = 180
    static let spacing: CGFloat = 10
    /// Отступы строки: 16 слева и 16 справа.
    static let horizontalPadding: CGFloat = 32
    /// Дополнительный отступ строк внутри группы серии (30 вместо 16).
    static let indent: CGFloat = 14
    /// Доля гибкой ширины для «Жанров»; остальное — «Названию», у него приоритет.
    static let genresShare: CGFloat = 0.3

    /// Для мест без замера ширины (окно поиска): «Жанры» идеальной ширины.
    static let standard = BookTableColumns(
        showsSize: true, showsGenres: true, genresWidth: genresIdealWidth)

    /// Самая узкая панель, в которую ещё помещаются постоянные колонки строки
    /// внутри группы серии.
    static var minimumPaneWidth: CGFloat {
        horizontalPadding + indent + checkboxWidth + numWidth + dateWidth
            + 3 * spacing + titleMinWidth
    }

    static func visibleColumns(forWidth width: CGFloat) -> BookTableColumns {
        let content = width - horizontalPadding
        let base = checkboxWidth + numWidth + dateWidth + 3 * spacing
        let withSize = base + sizeWidth + spacing
        let withGenres = withSize + spacing

        let flex = content - withGenres
        if flex >= titleMinWidth + genresMinWidth {
            return BookTableColumns(
                showsSize: true, showsGenres: true,
                genresWidth: max(genresMinWidth, (flex * genresShare).rounded(.down)))
        }
        let showsSize = content - withSize >= titleMinWidth
        return BookTableColumns(showsSize: showsSize, showsGenres: false, genresWidth: 0)
    }
}

nonisolated enum BookTableColumnID: String, CaseIterable, Sendable {
    case title, num, size, date, genres

    var headerTitle: String {
        switch self {
        case .title: "Название"
        case .num: "№"
        case .size: "Размер"
        case .date: "Дата"
        case .genres: "Жанры"
        }
    }
}

nonisolated struct BookTableColumnLayout: Equatable, Sendable {
    let title: CGFloat
    let num: CGFloat
    let size: CGFloat?
    let date: CGFloat
    let genres: CGFloat?

    func width(of column: BookTableColumnID) -> CGFloat? {
        switch column {
        case .title: title
        case .num: num
        case .size: size
        case .date: date
        case .genres: genres
        }
    }

    var totalWidth: CGFloat { title + num + (size ?? 0) + date + (genres ?? 0) }
}

nonisolated extension BookTableColumns {
    static let rowInset: CGFloat = 16

    /// Ширины колонок NSTableView при `intercellSpacing = 0`: промежуток 10
    /// входит в колонку слева, отступ строки 16 — в первую и последнюю.
    static func columnLayout(forWidth width: CGFloat) -> BookTableColumnLayout {
        let v = visibleColumns(forWidth: width)
        let num = spacing + numWidth
        let size: CGFloat? = v.showsSize ? spacing + sizeWidth : nil
        let genres: CGFloat? = v.showsGenres ? spacing + v.genresWidth + rowInset : nil
        let date = spacing + dateWidth + (genres == nil ? rowInset : 0)
        let title = width - num - (size ?? 0) - date - (genres ?? 0)
        return BookTableColumnLayout(title: title, num: num, size: size, date: date, genres: genres)
    }
}
