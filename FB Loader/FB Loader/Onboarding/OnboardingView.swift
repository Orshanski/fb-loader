import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Shown until both INPX and archives directory are configured.
/// Calls `onComplete` when the user picks both.
struct OnboardingView: View {
    @State private var inpx: URL?
    @State private var archives: URL?
    let onComplete: (URL, URL) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("FB Loader").font(.largeTitle)
            Text("Укажите путь к INPX-файлу и папке с zip-архивами Flibusta.")
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
            HStack {
                Button("Выбрать папку с архивами…") {
                    let p = NSOpenPanel()
                    p.canChooseFiles = false
                    p.canChooseDirectories = true
                    if p.runModal() == .OK { archives = p.url }
                }
                Text(archives?.path ?? "не выбрана").foregroundStyle(.secondary)
            }
            Button("Продолжить") {
                if let i = inpx, let a = archives { onComplete(i, a) }
            }
            .disabled(inpx == nil || archives == nil)
            .keyboardShortcut(.defaultAction)
        }
        .padding(30)
        .frame(minWidth: 600, minHeight: 350)
    }
}
