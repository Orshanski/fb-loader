import SwiftUI
import AppKit
import UniformTypeIdentifiers   // for UTType(filenameExtension:)

struct SettingsView: View {
    let userPaths: UserPaths
    @State private var inpx: URL?
    @State private var arch: URL?
    @State private var cacheStatus: String = ""

    var body: some View {
        Form {
            HStack {
                Text("INPX:")
                Text(inpx?.path ?? "не выбран").foregroundStyle(.secondary)
                Spacer()
                Button("Изменить…") {
                    let p = NSOpenPanel(); p.canChooseFiles = true; p.canChooseDirectories = false
                    p.allowedContentTypes = [.init(filenameExtension: "inpx")!]
                    if p.runModal() == .OK { inpx = p.url; userPaths.inpxURL = p.url }
                }
            }
            HStack {
                Text("Папка архивов:")
                Text(arch?.path ?? "не выбрана").foregroundStyle(.secondary)
                Spacer()
                Button("Изменить…") {
                    let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
                    if p.runModal() == .OK { arch = p.url; userPaths.archivesDirectoryURL = p.url }
                }
            }
            Text("После смены путей перезапустите приложение.")
                .font(.caption).foregroundStyle(.secondary)

            Divider()
            HStack {
                Text("Кэш каталога:")
                Text(cacheStatus).foregroundStyle(.secondary).font(.caption)
                Spacer()
                Button("Перечитать каталог") {
                    deleteCache()
                }
            }
            Text("Удаляет library-cache.bin. Каталог пересоберётся из INPX при следующем запуске.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 600)
        .onAppear {
            inpx = userPaths.inpxURL
            arch = userPaths.archivesDirectoryURL
            updateCacheStatus()
        }
    }

    private func cacheURL() -> URL? {
        try? LibraryLoader.appSupportRoot().appendingPathComponent("library-cache.bin")
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

    private func deleteCache() {
        guard let url = cacheURL() else { return }
        try? FileManager.default.removeItem(at: url)
        updateCacheStatus()
    }
}
