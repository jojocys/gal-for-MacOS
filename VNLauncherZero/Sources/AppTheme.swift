import SwiftUI

enum AppTheme {
    static let bgTop = Color(red: 0.10, green: 0.12, blue: 0.17)
    static let bgBottom = Color(red: 0.05, green: 0.06, blue: 0.09)
    static let card = Color.white.opacity(0.06)
    static let cardBorder = Color.white.opacity(0.10)
    static let accent = Color(red: 0.13, green: 0.74, blue: 0.53)
    static let accent2 = Color(red: 0.98, green: 0.65, blue: 0.18)
    static let danger = Color(red: 0.94, green: 0.31, blue: 0.29)

    static var backgroundGradient: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
    }
}

extension View {
    func glassCard() -> some View { modifier(GlassCardModifier()) }
}

