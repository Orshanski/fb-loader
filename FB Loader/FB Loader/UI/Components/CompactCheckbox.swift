import SwiftUI

/// 14×14 checkbox styled to match the UI polish mockup
/// (`docs/superpowers/specs/2026-05-01-ui-polish-design.md`):
/// thin gray border + white fill when off, accent fill + white tick when on.
/// macOS's default `Toggle` checkbox is taller and uses the system control
/// look, which doesn't match the row's tight 13pt typography.
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
