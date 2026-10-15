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
            if let reason = progress.abortReason {
                Text("Выгрузка прервана: \(reason)").foregroundStyle(.red)
            }
            HStack {
                // «Отмена» гаснет после нажатия, чтобы не дать выставить
                // `cancelled` повторно. «Закрыть» становится активной при
                // `cancelled == true` НЕ дожидаясь возврата runner'а из
                // последнего Task.detached — пользователь должен иметь
                // возможность выйти из окна сразу. Этот вариант требует
                // финального пересчёта `checkedBookLibids` после
                // `await ExportRunner.run` в родительских вьюхах: без него
                // libid'ы, дописавшиеся в `succeeded` уже после закрытия
                // окна, не снимутся с галочки.
                Button("Отмена") { progress.cancelled = true }
                    .disabled(progress.done >= progress.total || progress.cancelled || progress.abortReason != nil)
                Spacer()
                Button("Закрыть") { onClose() }
                    .disabled(progress.total > 0 && progress.done < progress.total && !progress.cancelled
                              && progress.abortReason == nil)
                    .keyboardShortcut(.defaultAction)
            }.frame(width: 360)
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 220)
    }
}
