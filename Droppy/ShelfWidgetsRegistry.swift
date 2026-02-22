import SwiftUI

struct ShelfWidgetDescriptor: Identifiable {
    var id: ShelfWidgetType { type }
    var type: ShelfWidgetType
    var title: String
    var icon: String
    var subtitle: String
}

enum ShelfWidgetsRegistry {
    static let descriptors: [ShelfWidgetDescriptor] = [
        ShelfWidgetDescriptor(type: .files, title: "Files Shelf", icon: "tray.2.fill", subtitle: "Dropped files and folders"),
        ShelfWidgetDescriptor(type: .media, title: "Media HUD", icon: "music.note", subtitle: "Now playing controls"),
        ShelfWidgetDescriptor(type: .highAlert, title: "High Alert", icon: "eyes", subtitle: "Keep your Mac awake"),
        ShelfWidgetDescriptor(type: .terminal, title: "TermiNotch", icon: "terminal", subtitle: "Quick command bar"),
        ShelfWidgetDescriptor(type: .camera, title: "Notchface", icon: "camera.fill", subtitle: "Live camera preview"),
        ShelfWidgetDescriptor(type: .tasksCalendar, title: "Tasks & Calendar", icon: "calendar.badge.clock", subtitle: "Reminders and events")
    ]

    static func descriptor(for type: ShelfWidgetType) -> ShelfWidgetDescriptor {
        descriptors.first(where: { $0.type == type }) ?? ShelfWidgetDescriptor(type: type, title: type.rawValue, icon: "square.grid.2x2", subtitle: "")
    }

    static func availability(for type: ShelfWidgetType) -> (isAvailable: Bool, reason: String?) {
        switch type {
        case .files:
            return (true, nil)
        case .media:
            let enabled = UserDefaults.standard.preference(
                AppPreferenceKey.showMediaPlayer,
                default: PreferenceDefault.showMediaPlayer
            )
            return enabled ? (true, nil) : (false, "Enable Media Player in HUD settings")
        case .highAlert:
            let installed = UserDefaults.standard.preference(
                AppPreferenceKey.caffeineInstalled,
                default: PreferenceDefault.caffeineInstalled
            )
            let enabled = UserDefaults.standard.preference(
                AppPreferenceKey.caffeineEnabled,
                default: PreferenceDefault.caffeineEnabled
            )
            guard installed && !ExtensionType.caffeine.isRemoved else {
                return (false, "Install High Alert extension")
            }
            return enabled ? (true, nil) : (false, "Enable High Alert extension")
        case .terminal:
            let installed = UserDefaults.standard.preference(
                AppPreferenceKey.terminalNotchInstalled,
                default: PreferenceDefault.terminalNotchInstalled
            )
            let enabled = UserDefaults.standard.preference(
                AppPreferenceKey.terminalNotchEnabled,
                default: PreferenceDefault.terminalNotchEnabled
            )
            guard installed && !ExtensionType.terminalNotch.isRemoved else {
                return (false, "Install TermiNotch extension")
            }
            return enabled ? (true, nil) : (false, "Enable TermiNotch extension")
        case .camera:
            let installed = UserDefaults.standard.preference(
                AppPreferenceKey.cameraInstalled,
                default: PreferenceDefault.cameraInstalled
            )
            let enabled = UserDefaults.standard.preference(
                AppPreferenceKey.cameraEnabled,
                default: PreferenceDefault.cameraEnabled
            )
            guard installed && !ExtensionType.camera.isRemoved else {
                return (false, "Install Notchface extension")
            }
            return enabled ? (true, nil) : (false, "Enable Notchface extension")
        case .tasksCalendar:
            let installed = UserDefaults.standard.preference(
                AppPreferenceKey.todoInstalled,
                default: PreferenceDefault.todoInstalled
            )
            let enabled = UserDefaults.standard.preference(
                AppPreferenceKey.todoEnabled,
                default: PreferenceDefault.todoEnabled
            )
            guard installed && !ExtensionType.todo.isRemoved else {
                return (false, "Install Reminders extension")
            }
            return enabled ? (true, nil) : (false, "Enable Reminders extension")
        }
    }

    static func isAvailable(_ type: ShelfWidgetType) -> Bool {
        availability(for: type).isAvailable
    }
}
