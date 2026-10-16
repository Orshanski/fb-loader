import SwiftUI

/// Pill-shaped tappable chip (authors, series) for `BookDetailView`; fills with accent on hover.
struct Chip: View {
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(isHovered ? Color.white : Color.accentColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 2)
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isHovered ? Color.accentColor : Color(white: 0.96))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isHovered ? Color.accentColor : Color(white: 0.88),
                            lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
