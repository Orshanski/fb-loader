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
