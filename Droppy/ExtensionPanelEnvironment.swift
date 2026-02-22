import SwiftUI

private struct DroppyPanelCloseActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var droppyPanelCloseAction: (() -> Void)? {
        get { self[DroppyPanelCloseActionKey.self] }
        set { self[DroppyPanelCloseActionKey.self] = newValue }
    }
}

extension View {
    func droppyPanelCloseAction(_ action: (() -> Void)?) -> some View {
        environment(\.droppyPanelCloseAction, action)
    }
}

@MainActor
func closePanelOrDismiss(_ panelCloseAction: (() -> Void)?, dismiss: DismissAction) {
    if let panelCloseAction {
        panelCloseAction()
    } else {
        dismiss()
    }
}
