import SwiftUI

/// Pill-shaped clickable chip used for authors / series / similar tappable
/// metadata in `BookDetailView`. Mirrors the spec in the UI polish design
/// (2026-05-01): light-gray fill, soft border, accent text; on hover the
/// fill flips to accent and text to white.
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
