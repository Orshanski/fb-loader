import SwiftUI

/// Standalone book-table row used by both the main `BooksTableView` (with
/// `AppState`-derived bindings) and the search-window sheet (with local-
/// `SearchCoordinator` bindings). Selection and check state come in as
/// explicit `@Binding` parameters; an optional `contextMenuBuilder`
/// closure lets each call site provide its own context menu (or none).
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

    @State private var hovered = false

    static let checkboxWidth: CGFloat = 28
    static let numWidth: CGFloat = 50
    static let sizeWidth: CGFloat = 80
    static let dateWidth: CGFloat = 100
    static let genresWidth: CGFloat = 220

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $isChecked)
                .toggleStyle(.compactCheckbox)
                .labelsHidden()
                .frame(width: BookRow.checkboxWidth, alignment: .center)

            Text(book.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .fontWeight(isSelected ? .semibold : .regular)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(book.seriesNum.map { "\($0)" } ?? "—")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: BookRow.numWidth, alignment: .trailing)

            Text(byteCount(book.size))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: BookRow.sizeWidth, alignment: .trailing)

            Text(book.dateAdded.map(DateFormat.dayMonthYear.string(from:)) ?? "—")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: BookRow.dateWidth, alignment: .trailing)

            Text(genresString)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
                .frame(width: BookRow.genresWidth, alignment: .leading)
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
