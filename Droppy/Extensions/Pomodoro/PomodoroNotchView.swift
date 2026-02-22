//
//  PomodoroNotchView.swift
//  Droppy
//

import SwiftUI

struct PomodoroNotchView: View {
    var manager: PomodoroManager
    @Binding var isVisible: Bool

    var notchHeight: CGFloat = 0
    var isExternalWithNotchStyle: Bool = false

    @AppStorage(AppPreferenceKey.useTransparentBackground) private var useTransparentBackground = PreferenceDefault.useTransparentBackground

    private var contentPadding: EdgeInsets {
        NotchLayoutConstants.contentEdgeInsets(notchHeight: notchHeight, isExternalWithNotchStyle: isExternalWithNotchStyle)
    }

    private var useAdaptiveForegrounds: Bool {
        useTransparentBackground && notchHeight == 0
    }

    private func primaryText(_ opacity: Double = 1.0) -> Color {
        useAdaptiveForegrounds ? AdaptiveColors.primaryTextAuto.opacity(opacity) : .white.opacity(opacity)
    }

    private func secondaryText(_ opacity: Double) -> Color {
        useAdaptiveForegrounds ? AdaptiveColors.secondaryTextAuto.opacity(opacity) : .white.opacity(opacity)
    }

    private func overlayTone(_ opacity: Double) -> Color {
        useAdaptiveForegrounds ? AdaptiveColors.overlayAuto(opacity) : .white.opacity(opacity)
    }

    private var activeAccentColor: Color {
        manager.activeSectionColor
    }

    private var iconName: String {
        guard manager.isActive else { return "timer" }
        return manager.sessionKind == .focus ? "timer" : "cup.and.saucer.fill"
    }

    private var statusText: String {
        manager.isActive ? manager.compactStatusText : "Ready"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(spacing: 6) {
                Button {
                    togglePomodoro()
                } label: {
                    ZStack {
                        Circle()
                            .fill(manager.isActive ? activeAccentColor.opacity(0.20) : overlayTone(0.05))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle()
                                    .stroke(manager.isActive ? activeAccentColor : overlayTone(0.1), lineWidth: 2)
                            )

                        Image(systemName: iconName)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(manager.isActive ? activeAccentColor : primaryText(0.82))
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 44))

                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(manager.isActive ? activeAccentColor : secondaryText(0.62))
                    .monospacedDigit()
                    .animation(DroppyAnimation.smoothContent, value: statusText)

                if manager.isActive && manager.sessionKind == .focus, let focusTitle = manager.focusTitle {
                    Text(focusTitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(secondaryText(0.70))
                        .lineLimit(1)
                        .frame(maxWidth: 68)
                }
            }
            .frame(width: 60)

            Divider()
                .background(overlayTone(0.15))
                .frame(height: 56)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(manager.sections) { section in
                    sectionRow(section)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, contentPadding.top)
        .padding(.bottom, contentPadding.bottom)
        .padding(.trailing, contentPadding.trailing)
        .padding(.leading, contentPadding.leading)
    }

    @ViewBuilder
    private func sectionRow(_ section: PomodoroSection) -> some View {
        let accentColor = sectionAccentColor(for: section)

        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 8, height: 8)

                Text(section.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(secondaryText(0.80))
                    .lineLimit(1)
            }
            .frame(minWidth: 68, maxWidth: 112, alignment: .leading)

            HStack(spacing: 8) {
                ForEach(section.timers, id: \.self) { minutes in
                    PomodoroPresetButton(
                        minutes: minutes,
                        accentColor: accentColor,
                        isActive: isTimerActive(sectionID: section.id, minutes: minutes),
                        useAdaptiveForegrounds: useAdaptiveForegrounds
                    ) {
                        selectTimer(sectionID: section.id, minutes: minutes)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionAccentColor(for section: PomodoroSection) -> Color {
        Color(hex: section.colorHex) ?? .blue
    }

    private func isTimerActive(sectionID: String, minutes: Int) -> Bool {
        guard manager.isActive, let selection = manager.activeSelection else { return false }
        return selection.sectionID == sectionID && selection.minutes == minutes
    }

    private func togglePomodoro() {
        HapticFeedback.drop()
        withAnimation(DroppyAnimation.hover) {
            if manager.isActive {
                manager.stop()
                return
            }

            manager.startLastUsedSelection()
        }
    }

    private func selectTimer(sectionID: String, minutes: Int) {
        HapticFeedback.tap()
        withAnimation(DroppyAnimation.hover) {
            manager.toggle(sectionID: sectionID, minutes: minutes)
        }
    }
}

struct PomodoroPresetButton: View {
    let minutes: Int
    let accentColor: Color
    let isActive: Bool
    var useAdaptiveForegrounds: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text("\(minutes)m")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(
                    isActive
                        ? .black
                        : (useAdaptiveForegrounds ? AdaptiveColors.primaryTextAuto : .white)
                )
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    Capsule()
                        .fill(
                            isActive
                                ? accentColor
                                : (useAdaptiveForegrounds
                                   ? AdaptiveColors.overlayAuto(isHovering ? 0.18 : 0.12)
                                   : Color.white.opacity(isHovering ? 0.18 : 0.12))
                        )
                )
                .overlay(
                    Capsule()
                        .stroke(
                            useAdaptiveForegrounds
                                ? AdaptiveColors.overlayAuto(isActive ? 0 : 0.1)
                                : Color.white.opacity(isActive ? 0 : 0.1),
                            lineWidth: 1
                        )
                )
                .scaleEffect(isHovering ? 1.02 : 1.0)
                .animation(DroppyAnimation.hoverQuick, value: isHovering)
                .animation(DroppyAnimation.hover, value: isActive)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            if hovering { HapticFeedback.hover() }
        }
    }
}

#Preview {
    ZStack {
        Color.black
        PomodoroNotchView(
            manager: PomodoroManager.shared,
            isVisible: .constant(true),
            notchHeight: 32
        )
        .frame(width: 430, height: 190)
    }
}
