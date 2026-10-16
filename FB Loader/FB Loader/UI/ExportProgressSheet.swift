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
                failureList
            }
            if let reason = progress.abortReason {
                Text("Выгрузка прервана: \(reason)").foregroundStyle(.red)
            }
            HStack {
                // «Закрыть» после «Отмена» не ждёт возврата runner'а.
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

    private static let rowHeight: CGFloat = 36
    private static let visibleRows = 6

    private var failureList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(progress.failed.enumerated()), id: \.offset) { _, failure in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(failure.title).lineLimit(1).truncationMode(.middle)
                        Text(failure.error).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                            .padding(.leading, 12)
                    }
                    .frame(width: 340, height: Self.rowHeight, alignment: .leading)
                }
            }
        }
        .frame(width: 360, height: Self.rowHeight * CGFloat(min(progress.failed.count, Self.visibleRows)))
    }
}
