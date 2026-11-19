import SwiftUI

struct PrimaryActionButton: View {
    let title: String
    let systemImage: String
    let isBusy: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    init(title: String, systemImage: String, isBusy: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isBusy = isBusy
        self.action = action
    }

    private var fill: Color {
        Color(white: colorScheme == .dark ? 0.94 : 0.16)
    }

    private var ink: Color {
        if !isEnabled || isBusy { return .secondary }
        return colorScheme == .dark ? .black : .white
    }

    var body: some View {
        Group {
            if !isEnabled || isBusy {
                button.buttonStyle(CapsuleActionStyle(fill: .primary.opacity(0.08)))
            } else if #available(iOS 26.0, *) {
                button
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(fill)
            } else {
                button.buttonStyle(CapsuleActionStyle(fill: fill))
            }
        }
        .disabled(isBusy)
        .accessibilityLabel(Text(verbatim: title))
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isBusy {
                    ProgressView()
                        .tint(ink)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(verbatim: title)
                    .multilineTextAlignment(.center)
            }
            .font(.headline)
            .foregroundStyle(ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 54)
            .contentShape(.capsule)
        }
    }
}

private struct CapsuleActionStyle: ButtonStyle {
    let fill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(fill.gradient, in: Capsule())
            .overlay { Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 1) }
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}
