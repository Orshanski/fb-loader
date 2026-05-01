import SwiftUI

struct ExportProgressSheet: View {
    let progress: ExportProgress
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Выгрузка").font(.headline)
            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                .frame(width: 360)
            Text("\(progress.done) / \(progress.total) — \(progress.currentTitle)")
                .lineLimit(1).truncationMode(.middle).frame(width: 360)
            if !progress.failed.isEmpty {
                Text("Ошибки: \(progress.failed.count)")
                    .foregroundStyle(.red)
            }
            HStack {
                Button("Отмена") { progress.cancelled = true }
                    .disabled(progress.done >= progress.total)
                Spacer()
                Button("Закрыть") { onClose() }
                    .disabled(progress.total > 0 && progress.done < progress.total)
                    .keyboardShortcut(.defaultAction)
            }.frame(width: 360)
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 220)
    }
}
