import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Shown when both INPX and archives directory are not configured.
/// User picks INPX; archives folder defaults to the INPX file's parent
/// directory (typical Flibusta layout). Override is available later
/// in Settings if the user actually has a split setup.
struct CatalogPickerView: View {
    @State private var inpx: URL?
    let onComplete: (URL, URL) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("FB Loader").font(.largeTitle)
            Text("Укажите INPX-файл. Папка с zip-архивами по умолчанию — это директория, где лежит INPX. Изменить отдельно её можно потом в Настройках.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack {
                Button("Выбрать INPX…") {
                    let p = NSOpenPanel()
                    p.canChooseFiles = true
                    p.canChooseDirectories = false
                    p.allowedContentTypes = [.init(filenameExtension: "inpx")!]
                    if p.runModal() == .OK { inpx = p.url }
                }
                Text(inpx?.path ?? "не выбран").foregroundStyle(.secondary)
            }
            Button("Продолжить") {
                if let i = inpx {
                    onComplete(i, i.deletingLastPathComponent())
                }
            }
            .disabled(inpx == nil)
            .keyboardShortcut(.defaultAction)
        }
        .padding(30)
        .frame(minWidth: 600, minHeight: 350)
    }
}
