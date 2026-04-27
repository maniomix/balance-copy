import UIKit

// MARK: - Haptics

enum Haptics {
    private static var isEnabled: Bool {
        // Default is true if not set yet
        if UserDefaults.standard.object(forKey: "app.hapticFeedback") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "app.hapticFeedback")
    }

    static func light() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func medium() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    static func heavy() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }
    static func soft() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
    static func rigid() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }
    static func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
    static func error() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    // Complex patterns
    static func transactionAdded() {
        soft()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            medium()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                success()
            }
        }
    }

    static func transactionDeleted() {
        heavy()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            light()
        }
    }

    /// Light tick when a goal contribution crosses a 25 / 50 / 75 % milestone.
    static func goalMilestone() {
        soft()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            light()
        }
    }

    /// Celebratory pattern fired when a goal hits 100%.
    static func goalCompleted() {
        medium()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            heavy()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                success()
            }
        }
    }

    static func budgetExceeded() {
        heavy()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            warning()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                heavy()
            }
        }
    }

    static func monthChanged() {
        rigid()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            soft()
        }
    }

    static func longPressStart() {
        medium()
    }

    static func contextMenuOpened() {
        soft()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            light()
        }
    }

    static func exportSuccess() {
        medium()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            success()
        }
    }

    static func backupCreated() {
        rigid()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            success()
        }
    }

    static func backupRestored() {
        heavy()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            success()
        }
    }

    static func importSuccess() {
        medium()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            success()
        }
    }
}
