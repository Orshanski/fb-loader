import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Спрашивает только недостающий путь. Без путей вовсе — INPX, а папкой
/// архивов становится его директория (типичная раскладка Flibusta); отдельно
/// её можно сменить потом в Настройках.
struct CatalogPickerView: View {
    let missing: MissingPaths
    let userPaths: UserPaths
    let onComplete: (_ inpx: URL, _ archives: URL) -> Void
    @State private var picked: URL?

    var body: some View {
        VStack(spacing: 20) {
            Text("FB Loader").font(.largeTitle)
            Text(prompt)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack {
                Button(missing == .archives ? "Выбрать папку…" : "Выбрать INPX…") {
                    if let url = choose() { picked = url }
                }
                Text(picked?.path ?? (missing == .archives ? "не выбрана" : "не выбран"))
                    .foregroundStyle(.secondary)
            }
            Button("Продолжить") {
                if let picked,
                   let paths = missing.resolve(picked: picked,
                                               inpx: userPaths.inpxURL,
                                               archives: userPaths.archivesDirectoryURL) {
                    onComplete(paths.inpx, paths.archives)
                }
            }
            .disabled(picked == nil)
            .keyboardShortcut(.defaultAction)
        }
        .padding(30)
        .frame(minWidth: 600, minHeight: 350)
    }

    private var prompt: String {
        switch missing {
        case .both:
            "Укажите INPX-файл. Папка с zip-архивами по умолчанию — это директория, где лежит INPX. Изменить отдельно её можно потом в Настройках."
        case .inpx:
            "INPX-файл не найден: \(userPaths.inpxURL?.path ?? "—"). Укажите INPX заново."
        case .archives:
            "Папка с zip-архивами не найдена: \(userPaths.archivesDirectoryURL?.path ?? "—"). Укажите папку с архивами заново."
        }
    }

    private func choose() -> URL? {
        let p = NSOpenPanel()
        if missing == .archives {
            p.canChooseFiles = false
            p.canChooseDirectories = true
        } else {
            p.canChooseFiles = true
            p.canChooseDirectories = false
            p.allowedContentTypes = [.init(filenameExtension: "inpx")!]
        }
        return p.runModal() == .OK ? p.url : nil
    }
}
