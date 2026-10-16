import SwiftUI

/// 14×14 checkbox: the system `Toggle` is taller and doesn't fit the row's tight 13pt typography.
struct CompactCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(configuration.isOn ? Color.accentColor : Color.white)
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(
                        configuration.isOn ? Color.accentColor : Color(white: 0.78),
                        lineWidth: 1)
                if configuration.isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 14, height: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension ToggleStyle where Self == CompactCheckboxStyle {
    static var compactCheckbox: CompactCheckboxStyle { CompactCheckboxStyle() }
}
