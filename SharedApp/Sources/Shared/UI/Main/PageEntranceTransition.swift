import SwiftUI

/// Animate presentation without replacing the page or its playback state.
struct PageEntranceTransition: ViewModifier {
    var isSelected = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion || isPresented ? 1 : 0)
            .task(id: isSelected) {
                guard isSelected else {
                    resetPresentation()
                    return
                }
                guard !reduceMotion else {
                    isPresented = true
                    return
                }
                resetPresentation()
                // Let the newly selected native tab enter the view hierarchy first.
                do { try await Task.sleep(for: .milliseconds(16)) }
                catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    isPresented = true
                }
            }
            .onDisappear { resetPresentation() }
    }

    private func resetPresentation() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { isPresented = false }
    }
}
