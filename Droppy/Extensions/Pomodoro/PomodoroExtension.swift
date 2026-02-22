//
//  PomodoroExtension.swift
//  Droppy
//

import SwiftUI

struct PomodoroExtension: ExtensionDefinition {
    static let id = "pomodoro"
    static let title = "Pomodoro"
    static let subtitle = "Custom focus sections in your notch"
    static let category: ExtensionGroup = .productivity
    static let categoryColor: Color = .blue

    static let description = "Run Pomodoro sessions directly from Droppy with customizable sections, timer presets, and colors. Start quickly from the shelf, monitor remaining time in the HUD, and keep context with an optional focus title."

    static let features: [(icon: String, text: String)] = [
        ("square.stack.3d.up", "Create custom sections with your own names"),
        ("paintpalette.fill", "Choose section colors and timer presets"),
        ("rectangle.split.2x1", "Compact HUD and expanded shelf controls"),
        ("list.bullet.rectangle", "Optional focus title per session")
    ]

    static var screenshotURL: URL? {
        URL(string: "https://getdroppy.app/assets/images/pomodoro-screenshot.png")
    }

    static var iconURL: URL? {
        URL(string: "https://getdroppy.app/assets/icons/pomodoro.png?v=20260221")
    }

    static let iconPlaceholder = "timer"
    static let iconPlaceholderColor: Color = .blue

    static func cleanup() {
        PomodoroManager.shared.stop()
    }
}
