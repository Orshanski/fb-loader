import SwiftUI

struct SearchExportMenu: View {
    let checkedCount: Int
    let isBusy: Bool
    let onExport: () -> Void

    var body: some View {
        if isBusy {
            Button("Выгрузка ещё идёт…") {}.disabled(true)
        } else {
            Button("Выгрузить отмеченные (\(checkedCount))") { onExport() }
                .disabled(checkedCount == 0)
        }
    }
}
