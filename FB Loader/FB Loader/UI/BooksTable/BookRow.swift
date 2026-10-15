import SwiftUI

/// Строка книги окна поиска (`SearchWindowView`): выбор и галочка — через
/// `@Binding`, контекстное меню — необязательное. Главное окно рисует книги
/// в `NSTableView` (`BooksTableRepresentable`).
struct BookRow: View {
    let book: Book
    let library: Library
    let indented: Bool
    @Binding var isChecked: Bool
    @Binding var isSelected: Bool

    /// Optional context-menu builder. Wrapped in `AnyView` so the View tree
    /// stays type-erased — the call sites have very different menu shapes
    /// (BooksTable's "Выгрузить отмеченные" vs search-window's local-export
    /// menu). If `nil`, no context menu is attached.
    var contextMenuBuilder: (() -> AnyView)? = nil

    @Environment(\.bookTableColumns) private var columns
    @State private var hovered = false

    var body: some View {
        HStack(spacing: BookTableColumns.spacing) {
            Toggle("", isOn: $isChecked)
                .toggleStyle(.compactCheckbox)
                .labelsHidden()
                .frame(width: BookTableColumns.checkboxWidth, alignment: .center)

            Text(book.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .fontWeight(isSelected ? .semibold : .regular)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(book.seriesNum.map { "\($0)" } ?? "—")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: BookTableColumns.numWidth, alignment: .trailing)

            if columns.showsSize {
                Text(byteCount(book.size))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: BookTableColumns.sizeWidth, alignment: .trailing)
            }

            Text(book.dateAdded.map(DateFormat.dayMonthYear.string(from:)) ?? "—")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: BookTableColumns.dateWidth, alignment: .trailing)

            if columns.showsGenres {
                Text(genresString)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
                    .frame(width: columns.genresWidth, alignment: .leading)
            }
        }
        .font(.system(size: 13))
        .padding(.leading, indented ? 30 : 16)
        .padding(.trailing, 16)
        .padding(.vertical, 4)
        .background(hovered ? Color.black.opacity(0.03) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { isSelected = true }
        .modifier(OptionalContextMenu(builder: contextMenuBuilder))
    }

    private func byteCount(_ n: Int32) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }

    private var genresString: String {
        let names = book.genreIDs.compactMap { library.genreByID[$0]?.name }
        return names.joined(separator: ", ")
    }
}

private struct OptionalContextMenu: ViewModifier {
    let builder: (() -> AnyView)?

    func body(content: Content) -> some View {
        if let builder {
            content.contextMenu { builder() }
        } else {
            content
        }
    }
}

private struct BookTableColumnsKey: EnvironmentKey {
    static let defaultValue = BookTableColumns.standard
}

extension EnvironmentValues {
    var bookTableColumns: BookTableColumns {
        get { self[BookTableColumnsKey.self] }
        set { self[BookTableColumnsKey.self] = newValue }
    }
}
