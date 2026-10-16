import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    let userPaths: UserPaths
    let rebuildProgress: String?
    let canRebuild: Bool
    let onClose: () -> Void
    let onRebuild: () -> Void
    let onINPXChange: (URL) -> Void
    @State private var cacheStatus: String = ""

    var body: some View {
        Form {
            HStack {
                Text("INPX:")
                Text(userPaths.inpxURL?.path ?? "не выбран").foregroundStyle(.secondary)
                Spacer()
                Button("Изменить…") {
                    let p = NSOpenPanel(); p.canChooseFiles = true; p.canChooseDirectories = false
                    p.allowedContentTypes = [.init(filenameExtension: "inpx")!]
                    if p.runModal() == .OK, let url = p.url { onINPXChange(url) }
                }
                .disabled(rebuildProgress != nil)
            }
            HStack {
                Text("Папка архивов:")
                Text(userPaths.archivesDirectoryURL?.path ?? "не выбрана").foregroundStyle(.secondary)
                Spacer()
                Button("Изменить…") {
                    let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
                    if p.runModal() == .OK { userPaths.archivesDirectoryURL = p.url }
                }
            }
            Divider()
            HStack {
                Text("Кэш каталога:")
                Text(cacheStatus).foregroundStyle(.secondary).font(.caption)
                Spacer()
                Button("Пересобрать каталог") { onRebuild() }
                    .disabled(!canRebuild || rebuildProgress != nil)
            }
            if let rebuildProgress {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(rebuildProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            Divider()
            HStack {
                Spacer()
                Button("Готово") { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 600)
        .onAppear { updateCacheStatus() }
        .onChange(of: rebuildProgress) { oldValue, newValue in
            if oldValue != nil && newValue == nil {
                updateCacheStatus()
            }
        }
    }

    private func cacheURL() -> URL? {
        try? LibraryLoader.cacheURL()
    }

    private func updateCacheStatus() {
        guard let url = cacheURL(),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int else {
            cacheStatus = "нет"
            return
        }
        let mb = Double(size) / 1_048_576
        cacheStatus = String(format: "%.1f МБ", mb)
    }

}
