import AppKit

enum ExportFolderPanel {
    /// Панель — sheet ключевого окна; без ключевого окна — отдельное окно.
    @MainActor
    static func choose(initial: URL?) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = initial
        return await withCheckedContinuation { continuation in
            let finish: (NSApplication.ModalResponse) -> Void = { response in
                // Sheet прогресса не покажется на окне, пока панель ещё на нём.
                panel.orderOut(nil)
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
            if let window = NSApp.keyWindow {
                panel.beginSheetModal(for: window, completionHandler: finish)
            } else {
                panel.begin(completionHandler: finish)
            }
        }
    }
}
