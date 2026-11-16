import SwiftUI

/// Shared surface and emphasis colors. Content keeps the system's semantic text colors and native controls.
struct SetupPalette {
    let canvas: Color
    let sidebar: Color
    let surface: Color
    let rule: Color
    let accent: Color
    let selection: Color
    let folder: Color

    init(dark: Bool = false, increasedContrast: Bool = false) {
        canvas = Self.color(dark ? 0x1C2220 : 0xFFFFFF)
        sidebar = Self.color(dark ? 0x181E1C : 0xF0F2F0)
        surface = Self.color(dark ? 0x242B28 : 0xF7F8F6)
        rule = Self.color(dark ? (increasedContrast ? 0x77847C : 0x3B4540) : (increasedContrast ? 0x8B9890 : 0xDEE3DF))
        #if PREVIEW
        // The scratch renderer has no asset catalog. The native app resolves this through the user's accent preference.
        let resolvedAccent = Self.color(dark ? 0x9BCBBB : 0x2D6559)
        #else
        let resolvedAccent = Color.accentColor
        #endif
        accent = resolvedAccent
        selection = resolvedAccent.opacity(dark ? 0.22 : 0.12)
        folder = Self.color(dark ? 0xA3BAC1 : 0x5A7C88)
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
              blue: Double(hex & 255) / 255, opacity: 1)
    }
}

private struct SetupPaletteKey: EnvironmentKey {
    static let defaultValue = SetupPalette()
}

extension EnvironmentValues {
    var setupPalette: SetupPalette {
        get { self[SetupPaletteKey.self] }
        set { self[SetupPaletteKey.self] = newValue }
    }
}

private struct SetupPanel: ViewModifier {
    @Environment(\.setupPalette) private var palette
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(palette.canvas, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(palette.rule, lineWidth: 0.5))
    }
}

extension View {
    func panel(cornerRadius: CGFloat = 10) -> some View {
        modifier(SetupPanel(cornerRadius: cornerRadius))
    }
}

/// Small secondary actions keep a full hit area without surrounding every glyph with a permanent button plate.
struct SetupQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietButtonBody(label: configuration.label, pressed: configuration.isPressed)
    }

    private struct QuietButtonBody: View {
        let label: ButtonStyleConfiguration.Label
        let pressed: Bool
        @Environment(\.setupPalette) private var palette
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false

        var body: some View {
            label
                .foregroundStyle(enabled ? Color.secondary : Color.secondary.opacity(0.5))
                .background(pressed ? palette.selection : hovered && enabled ? palette.surface : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5))
                .contentShape(RoundedRectangle(cornerRadius: 5))
                .onHover { hovered = $0 }
        }
    }
}
