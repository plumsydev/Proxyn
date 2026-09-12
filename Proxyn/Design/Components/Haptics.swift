import SwiftUI
import UIKit

/// Centralised haptics so feedback stays consistent — and so the user can turn
/// the whole thing off from Settings.
@MainActor
enum Haptics {
    static var enabled = true

    static func tap() { impact(.light) }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func commit() { impact(.medium) }
    static func heavy() { impact(.heavy) }

    static func success() { notify(.success) }
    static func warning() { notify(.warning) }
    static func failure() { notify(.error) }

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard enabled else { return }
        let g = UIImpactFeedbackGenerator(style: style)
        g.prepare()
        g.impactOccurred()
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
