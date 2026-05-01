import SwiftUI
import AppKit
import UniformTypeIdentifiers   // for UTType(filenameExtension:)

struct SettingsView: View {
    let userPaths: UserPaths
    @State private var inpx: URL?
    @State private var arch: URL?

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
            Text("После смены путей перезапустите приложение.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 600)
        .onAppear {
            inpx = userPaths.inpxURL
            arch = userPaths.archivesDirectoryURL
        }
    }
}
