import SwiftUI

/// Subtle feedback for sidebar and welcome actions; Button keeps its native keyboard activation.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietButtonBody(configuration:configuration)
    }
}

private struct QuietButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    var body: some View {
        configuration.label
            .overlay { RoundedRectangle(cornerRadius:10).fill((hovered || configuration.isPressed) && enabled ? Theme.accent.opacity(configuration.isPressed ? 0.15 : 0.07) : Color.clear).allowsHitTesting(false) }
            .overlay { RoundedRectangle(cornerRadius:10).strokeBorder(focused ? Theme.accent : Color.clear,lineWidth:2).allowsHitTesting(false) }
            .opacity(enabled ? 1 : 0.45)
            .onHover { hovered = $0 }
    }
}
