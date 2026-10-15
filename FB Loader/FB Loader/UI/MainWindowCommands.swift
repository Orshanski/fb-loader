import SwiftUI

/// Действия главного окна для пунктов меню: меню живёт на уровне сцены и до
/// `@State` в `MainWindowView` иначе не дотягивается. Пока каталог не открыт,
/// значения нет и пункты неактивны.
struct MainWindowActions {
    var sidebarVisible: Bool
    var toggleSidebar: () -> Void
    var openSearch: () -> Void
}

private struct MainWindowActionsKey: FocusedValueKey {
    typealias Value = MainWindowActions
}

extension FocusedValues {
    var mainWindowActions: MainWindowActions? {
        get { self[MainWindowActionsKey.self] }
        set { self[MainWindowActionsKey.self] = newValue }
    }
}

struct MainWindowCommands: Commands {
    @FocusedValue(\.mainWindowActions) private var actions

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button(actions?.sidebarVisible == false
                   ? "Показать боковую панель" : "Скрыть боковую панель") {
                actions?.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: [.control, .command])
            .disabled(actions == nil)
            Divider()
        }
        CommandGroup(after: .textEditing) {
            Button("Поиск по библиотеке…") {
                actions?.openSearch()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(actions == nil)
        }
    }
}
