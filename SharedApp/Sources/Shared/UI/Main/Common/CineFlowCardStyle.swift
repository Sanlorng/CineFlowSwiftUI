import SwiftUI

struct CineFlowCardInteraction: Equatable, Sendable {
    var isHovering = false
    var isPressed = false
    var isSelected = false
    var isFocused = false

    var tint: Color {
        if isSelected {
            return Color.accentColor.opacity(isPressed ? 0.2 : isHovering ? 0.16 : 0.12)
        }
        return Color.primary.opacity(isPressed ? 0.08 : isHovering ? 0.04 : 0)
    }

    var border: Color {
        if isPressed || isHovering {
            return Color.primary.opacity(isPressed ? 0.38 : 0.3)
        }
        return Color.accentColor.opacity(isFocused ? 0.8 : 0.55)
    }
}

private struct CineFlowCardInteractionKey: EnvironmentKey {
    static let defaultValue = CineFlowCardInteraction()
}

extension EnvironmentValues {
    var cineFlowCardInteraction: CineFlowCardInteraction {
        get { self[CineFlowCardInteractionKey.self] }
        set { self[CineFlowCardInteractionKey.self] = newValue }
    }
}

// Base surfaces stay in each feature. Only interaction feedback is shared.
struct CineFlowCardButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 18
    var usesCapsule = false
    var liftsOnHover = true
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        CardButton(configuration: configuration, style: self)
    }

    private struct CardButton: View {
        let configuration: ButtonStyle.Configuration
        let style: CineFlowCardButtonStyle
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovering = false

        private var interaction: CineFlowCardInteraction {
            CineFlowCardInteraction(
                isHovering: isEnabled && isHovering,
                isPressed: isEnabled && configuration.isPressed,
                isSelected: isEnabled && style.isSelected,
                isFocused: isEnabled && isFocused
            )
        }

        private var shape: CineFlowInteractionShape {
            CineFlowInteractionShape(cornerRadius: style.cornerRadius, usesCapsule: style.usesCapsule)
        }

        var body: some View {
            configuration.label
                .foregroundStyle(.primary)
                .environment(\.cineFlowCardInteraction, interaction)
                .contentShape(shape)
                .overlay {
                    if interaction.isHovering || interaction.isPressed || interaction.isSelected || interaction.isFocused {
                        shape.strokeBorder(
                            interaction.border,
                            lineWidth: interaction.isFocused ? 2 : interaction.isSelected ? 1.5 : 1
                        )
                        .allowsHitTesting(false)
                    }
                    // Opaque artwork still shows the button's pressed state.
                    if interaction.isPressed {
                        shape.fill(Color.primary.opacity(0.04))
                            .allowsHitTesting(false)
                    }
                }
                .offset(y: interaction.isHovering && style.liftsOnHover && !reduceMotion ? -2 : 0)
                .shadow(
                    color: .black.opacity(interaction.isHovering && style.liftsOnHover ? 0.1 : 0),
                    radius: 12,
                    y: 6
                )
                .zIndex(interaction.isHovering ? 1 : 0)
                .onHover { isHovering = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: interaction)
                .accessibilityAddTraits(style.isSelected ? .isSelected : [])
        }
    }
}

private struct CineFlowInteractionShape: InsettableShape {
    let cornerRadius: CGFloat
    var usesCapsule = false
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        if usesCapsule {
            Capsule(style: .continuous).inset(by: insetAmount).path(in: rect)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .inset(by: insetAmount).path(in: rect)
        }
    }

    func inset(by amount: CGFloat) -> Self {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

private struct CineFlowCardInteractionTint: ViewModifier {
    let cornerRadius: CGFloat
    let usesCapsule: Bool
    @Environment(\.cineFlowCardInteraction) private var interaction

    func body(content: Content) -> some View {
        content.overlay {
            CineFlowInteractionShape(cornerRadius: cornerRadius, usesCapsule: usesCapsule)
                .fill(interaction.tint)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    func cineFlowCardInteractionTint(cornerRadius: CGFloat = 18, usesCapsule: Bool = false) -> some View {
        modifier(CineFlowCardInteractionTint(cornerRadius: cornerRadius, usesCapsule: usesCapsule))
    }
}
