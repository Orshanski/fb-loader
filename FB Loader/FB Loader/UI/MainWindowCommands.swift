import SwiftUI

/// Действия главного окна для пунктов меню: меню живёт на уровне сцены и до
/// `@State` в `MainWindowView` иначе не дотягивается. Пока каталог не открыт,
/// значения нет и пункты неактивны.
struct MainWindowActions {
    /// Ложно, пока открыт любой sheet: иначе флаг поиска «зависал» бы до его
    /// закрытия, а сайдбар прятался бы за модальным окном.
    var isAvailable: Bool
    var sidebarVisible: Bool
    var toggleSidebar: () -> Void
    var openSearch: () -> Void
}

private struct MainWindowActionsKey: FocusedValueKey {
    typealias Value = MainWindowActions
}

/// Публикует `ContentView` на любом этапе, не только при открытом каталоге:
/// пути можно сменить и с экрана ошибки.
private struct OpenSettingsKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var mainWindowActions: MainWindowActions? {
        get { self[MainWindowActionsKey.self] }
        set { self[MainWindowActionsKey.self] = newValue }
    }

    var openSettings: (() -> Void)? {
        get { self[OpenSettingsKey.self] }
        set { self[OpenSettingsKey.self] = newValue }
    }
}

struct MainWindowCommands: Commands {
    @FocusedValue(\.mainWindowActions) private var actions
    @FocusedValue(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Настройки…") {
                openSettings?()
            }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(openSettings == nil)
        }
        CommandGroup(before: .toolbar) {
            Button(actions?.sidebarVisible == false
                   ? "Показать боковую панель" : "Скрыть боковую панель") {
                actions?.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: [.control, .command])
            .disabled(actions?.isAvailable != true)
            Divider()
        }
        CommandGroup(after: .textEditing) {
            Button("Поиск по библиотеке…") {
                actions?.openSearch()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(actions?.isAvailable != true)
        }
    }
}
