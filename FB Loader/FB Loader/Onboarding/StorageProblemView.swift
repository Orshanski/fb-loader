import SwiftUI

/// Каталог лежит на диске, который сейчас недоступен: файл не потерян, пути менять не нужно.
struct StorageProblemView: View {
    let problem: StorageProblem
    let onRetry: () -> Void
    let onRepick: () -> Void
    let onRemount: (URL) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("FB Loader").font(.largeTitle)
            Text(problem.title).font(.title2).bold()
            Text(problem.message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                Button("Указать заново…", action: onRepick)
                if let url = problem.remountURL {
                    Button("Подключить") { onRemount(url) }
                }
                Button("Повторить", action: onRetry)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(minWidth: 600, minHeight: 350)
    }
}
