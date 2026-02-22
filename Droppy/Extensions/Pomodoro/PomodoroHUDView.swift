//
//  PomodoroHUDView.swift
//  Droppy
//

import SwiftUI

struct PomodoroHUDView: View {
    let isActive: Bool
    let hudWidth: CGFloat
    var targetScreen: NSScreen? = nil
    var notchWidth: CGFloat = 180
    @State private var iconDidAppear = false

    @AppStorage(AppPreferenceKey.useTransparentBackground) private var useTransparentBackground = PreferenceDefault.useTransparentBackground

    private var manager: PomodoroManager { PomodoroManager.shared }

    private var layout: HUDLayoutCalculator {
        HUDLayoutCalculator(screen: targetScreen ?? NSScreen.main ?? NSScreen.screens.first)
    }

    private var hasPhysicalNotchOnDisplay: Bool {
        guard let screen = targetScreen ?? NSScreen.main ?? NSScreen.screens.first else { return false }
        return screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
    }

    private var useAdaptiveForegrounds: Bool {
        useTransparentBackground && !hasPhysicalNotchOnDisplay
    }

    private var accentColor: Color {
        if !isActive {
            return useAdaptiveForegrounds ? AdaptiveColors.secondaryTextAuto.opacity(0.85) : .white.opacity(0.78)
        }

        return manager.activeSectionColor
    }

    private var iconName: String {
        guard isActive else { return "timer" }
        return manager.sessionKind == .focus ? "timer" : "cup.and.saucer.fill"
    }

    private var statusText: String {
        isActive ? manager.compactStatusText : "Ready"
    }

    private var iconSize: CGFloat {
        layout.iconSize
    }

    private var statusFontSize: CGFloat {
        layout.labelFontSize
    }

    @ViewBuilder
    private var premiumIcon: some View {
        Image(systemName: iconName)
            .font(.system(size: iconSize, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(accentColor, accentColor.opacity(0.62))
            .contentTransition(.symbolEffect(.replace.byLayer.downUp))
            .symbolEffect(.bounce.up.byLayer, value: isActive)
            .scaleEffect(iconDidAppear ? 1.0 : 0.84)
            .opacity(iconDidAppear ? 1.0 : 0.0)
            .blur(radius: iconDidAppear ? 0 : 2.0)
            .animation(DroppyAnimation.scalePop, value: iconDidAppear)
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            if layout.isDynamicIslandMode {
                let symmetricPadding = layout.symmetricPadding(for: iconSize)

                HStack {
                    premiumIcon
                        .frame(width: 20, height: iconSize, alignment: .leading)

                    Spacer()

                    statusIndicator()
                }
                .padding(.horizontal, symmetricPadding)
                .frame(height: layout.notchHeight)
            } else {
                let symmetricPadding = layout.symmetricPadding(for: iconSize)
                let actualNotchWidth = layout.isDynamicIslandMode ? layout.notchWidth : notchWidth
                let wingWidth = (hudWidth - actualNotchWidth) / 2

                HStack(spacing: 0) {
                    HStack {
                        premiumIcon
                            .frame(width: iconSize, height: iconSize, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, symmetricPadding)
                    .frame(width: wingWidth)

                    Spacer()
                        .frame(width: actualNotchWidth)

                    HStack {
                        Spacer(minLength: 0)
                        statusIndicator()
                    }
                    .padding(.trailing, symmetricPadding)
                    .frame(width: wingWidth)
                }
                .frame(height: layout.notchHeight)
            }
        }
        .animation(DroppyAnimation.notchState, value: isActive)
        .animation(DroppyAnimation.notchState, value: statusText)
        .onAppear {
            iconDidAppear = false
            withAnimation(DroppyAnimation.scalePop) {
                iconDidAppear = true
            }
        }
        .onDisappear {
            iconDidAppear = false
        }
    }

    @ViewBuilder
    private func statusIndicator() -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(accentColor.opacity(isActive ? 1.0 : 0.6))
                .frame(width: 4, height: 4)

            Text(statusText)
                .font(.system(size: statusFontSize, weight: .semibold))
                .foregroundStyle(accentColor)
                .contentTransition(.numericText())
                .monospacedDigit()
        }
        .fixedSize()
    }
}

#Preview {
    ZStack {
        Color.black
        PomodoroHUDView(isActive: true, hudWidth: 300)
    }
    .frame(width: 350, height: 60)
}
