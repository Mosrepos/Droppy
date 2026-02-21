//
//  BatteryHUDView.swift
//  Droppy
//
//  Created by Droppy on 07/01/2026.
//  Beautiful battery HUD matching MediaHUDView style
//

import SwiftUI

private enum BatteryAssetVariant {
    case bar
    case bolt
    case boltTop

    var suffix: String {
        switch self {
        case .bar: return "Bar"
        case .bolt: return "Bolt"
        case .boltTop: return "BoltTop"
        }
    }

    var groupName: String {
        switch self {
        case .bar: return "Bar"
        case .bolt: return "Bolt"
        case .boltTop: return "BoltTop"
        }
    }
}

private func quantizedBatteryLevel(_ rawLevel: Int) -> Int {
    let clamped = max(0, min(100, rawLevel))
    let roundedUpToFive = Int((Double(clamped) / 5.0).rounded(.up) * 5)
    return min(100, max(5, roundedUpToFive))
}

/// Battery icon loader for imported SystemBatteryDark assets.
struct SystemBatteryAssetIcon: View {
    let level: Int
    let isCharging: Bool
    let isPluggedIn: Bool
    var width: CGFloat
    var height: CGFloat

    private var variant: BatteryAssetVariant {
        if isCharging { return .boltTop }
        if isPluggedIn { return .bolt }
        return .bar
    }

    private var clampedLevel: Int {
        max(0, min(100, level))
    }

    private var assetName: String {
        "\(quantizedBatteryLevel(clampedLevel))\(variant.suffix)"
    }

    private var candidateNames: [String] {
        [
            assetName,
            "SystemBatteryDark/\(variant.groupName)/\(assetName)",
            "SystemBatteryDark.\(variant.groupName).\(assetName)"
        ]
    }

    private var resolvedImage: NSImage? {
        for candidate in candidateNames {
            if let image = NSImage(named: NSImage.Name(candidate)) {
                return image
            }
        }
        return nil
    }

    private var fallbackOuterColor: Color {
        if isCharging || isPluggedIn {
            return Color(white: 0.62)
        }
        if clampedLevel <= 10 {
            return Color(red: 0.62, green: 0.12, blue: 0.18)
        }
        return Color(red: 0.16, green: 0.48, blue: 0.24)
    }

    private var fallbackInnerColor: Color {
        if isCharging || isPluggedIn {
            return Color(red: 0.46, green: 0.96, blue: 0.56)
        }
        if clampedLevel <= 10 {
            return Color(red: 1.0, green: 0.33, blue: 0.40)
        }
        return Color(red: 0.46, green: 0.93, blue: 0.52)
    }

    private var fallbackTerminalColor: Color {
        if isCharging || isPluggedIn {
            return Color(white: 0.62)
        }
        if clampedLevel <= 10 {
            return Color(red: 0.68, green: 0.14, blue: 0.20)
        }
        return Color(red: 0.20, green: 0.56, blue: 0.28)
    }

    var body: some View {
        Group {
            if let resolvedImage {
                Image(nsImage: resolvedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                IOSBatteryGlyph(
                    level: CGFloat(clampedLevel) / 100.0,
                    outerColor: fallbackOuterColor,
                    innerColor: fallbackInnerColor,
                    terminalColor: fallbackTerminalColor,
                    chargingSegmentColor: Color(white: 0.58),
                    isCharging: isCharging
                )
            }
        }
        .frame(width: width, height: height)
    }
}

/// iOS-style battery glyph (body + right cap), without embedded percentage text.
struct IOSBatteryGlyph: View {
    let level: CGFloat          // 0...1
    let outerColor: Color
    let innerColor: Color
    let terminalColor: Color
    let chargingSegmentColor: Color
    let isCharging: Bool
    var bodyWidth: CGFloat = 22
    var bodyHeight: CGFloat = 12

    private var clampedLevel: CGFloat {
        max(0, min(1, level))
    }

    private var fillWidth: CGFloat {
        // Keep a tiny minimum fill so empty battery is still visually present.
        max(1.5, (bodyWidth - 4) * clampedLevel)
    }

    private var remainingWidth: CGFloat {
        max(0, (bodyWidth - 4) - fillWidth)
    }

    private var bodyCornerRadius: CGFloat {
        bodyHeight * 0.46
    }

    private var innerCornerRadius: CGFloat {
        max(1, (bodyHeight - 4) * 0.48)
    }

    var body: some View {
        HStack(spacing: 1.8) {
            ZStack(alignment: .leading) {
                // iOS-style shell
                RoundedRectangle(cornerRadius: bodyCornerRadius, style: .continuous)
                    .fill(outerColor)

                // Capacity fill: iOS-style bright inner pill
                RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                    .fill(innerColor)
                    .frame(width: fillWidth, height: max(1, bodyHeight - 4))
                    .padding(2)

                if isCharging && remainingWidth > 0.8 {
                    // Charging style: neutral segment reflects the actual remaining percentage.
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: bodyCornerRadius * 0.84, style: .continuous)
                            .fill(chargingSegmentColor)
                            .frame(width: remainingWidth, height: max(1, bodyHeight - 4))
                    }
                    .padding(2)
                }

                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: bodyHeight * 0.52, weight: .black))
                        .foregroundStyle(.white.opacity(0.98))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, max(1.0, min(bodyWidth * 0.15, remainingWidth * 0.5 + 1.0)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: bodyWidth, height: bodyHeight)

            Capsule(style: .continuous)
                .fill(terminalColor)
                .frame(width: max(1.8, bodyHeight * 0.14), height: max(2, bodyHeight * 0.42))
        }
        .compositingGroup()
    }
}

/// Compact battery HUD that sits inside the notch
/// Matches MediaHUDView layout: icon on left wing, percentage on right wing
struct BatteryHUDView: View {
    @ObservedObject var batteryManager: BatteryManager
    let hudWidth: CGFloat     // Total HUD width
    var targetScreen: NSScreen? = nil  // Target screen for multi-monitor support
    
    /// Centralized layout calculator - Single Source of Truth
    private var layout: HUDLayoutCalculator {
        HUDLayoutCalculator(screen: targetScreen ?? NSScreen.main ?? NSScreen.screens.first)
    }
    
    /// Accent color based on battery state
    private var accentColor: Color {
        batteryInnerColor
    }

    private var shouldUseCriticalLowBatteryColor: Bool {
        !batteryManager.isCharging &&
            !batteryManager.isPluggedIn &&
            batteryManager.batteryLevel <= 10
    }

    private var batteryOuterColor: Color {
        if batteryManager.isCharging || batteryManager.isPluggedIn {
            return Color(white: 0.62)
        }
        if shouldUseCriticalLowBatteryColor {
            return Color(red: 0.62, green: 0.12, blue: 0.18)
        }
        return Color(red: 0.16, green: 0.48, blue: 0.24)
    }

    private var batteryInnerColor: Color {
        if batteryManager.isCharging || batteryManager.isPluggedIn {
            return Color(red: 0.46, green: 0.96, blue: 0.56)
        }
        if shouldUseCriticalLowBatteryColor {
            return Color(red: 1.0, green: 0.33, blue: 0.40)
        }
        return Color(red: 0.46, green: 0.93, blue: 0.52)
    }

    private var batteryTerminalColor: Color {
        if batteryManager.isCharging || batteryManager.isPluggedIn {
            return Color(white: 0.62)
        }
        if shouldUseCriticalLowBatteryColor {
            return Color(red: 0.68, green: 0.14, blue: 0.20)
        }
        return Color(red: 0.20, green: 0.56, blue: 0.28)
    }

    private var batteryChargingSegmentColor: Color {
        Color(white: 0.58)
    }

    private func glyphBodyWidth(for iconSize: CGFloat) -> CGFloat {
        if layout.isDynamicIslandMode {
            return max(20, iconSize * 1.22)
        }
        return max(24, iconSize * 1.38)
    }

    private func glyphFrameWidth(for iconSize: CGFloat) -> CGFloat {
        glyphBodyWidth(for: iconSize) + 6
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            if layout.isDynamicIslandMode {
                // DYNAMIC ISLAND: Icon on left edge, percentage on right edge
                let iconSize = layout.iconSize
                let iconFrameWidth = glyphFrameWidth(for: iconSize)
                let symmetricPadding = layout.symmetricPadding(for: iconSize)
                
                HStack {
                    // Battery icon - .leading alignment within frame for edge alignment
                    SystemBatteryAssetIcon(
                        level: batteryManager.batteryLevel,
                        isCharging: batteryManager.isCharging,
                        isPluggedIn: batteryManager.isPluggedIn,
                        width: iconFrameWidth,
                        height: iconSize
                    )
                        .frame(width: iconFrameWidth, height: iconSize, alignment: .leading)
                    
                    Spacer()
                    
                    // Percentage
                    Text("\(batteryManager.batteryLevel)%")
                        .font(.system(size: layout.labelFontSize * 0.8, weight: .semibold))
                        .foregroundStyle(accentColor)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(batteryManager.batteryLevel)))
                }
                .padding(.horizontal, symmetricPadding)
                .frame(height: layout.notchHeight)
            } else {
                // NOTCH MODE: Two wings separated by the notch space
                let iconSize = layout.iconSize
                let iconFrameWidth = glyphFrameWidth(for: iconSize)
                let symmetricPadding = layout.symmetricPadding(for: iconSize)
                let wingWidth = layout.wingWidth(for: hudWidth)
                
                HStack(spacing: 0) {
                    // Left wing: Battery icon near left edge
                    HStack {
                        SystemBatteryAssetIcon(
                            level: batteryManager.batteryLevel,
                            isCharging: batteryManager.isCharging,
                            isPluggedIn: batteryManager.isPluggedIn,
                            width: iconFrameWidth,
                            height: iconSize
                        )
                            .frame(width: iconFrameWidth, height: iconSize, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, symmetricPadding)
                    .frame(width: wingWidth)
                    
                    // Camera notch area (spacer)
                    Spacer()
                        .frame(width: layout.notchWidth)
                    
                    // Right wing: Percentage near right edge
                    HStack {
                        Spacer(minLength: 0)
                        Text("\(batteryManager.batteryLevel)%")
                            .font(.system(size: layout.labelFontSize * 0.8, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(batteryManager.batteryLevel)))
                            .animation(DroppyAnimation.notchState, value: batteryManager.batteryLevel)
                    }
                    .padding(.trailing, symmetricPadding)
                    .frame(width: wingWidth)
                }
                .frame(height: layout.notchHeight)
            }
        }
        .animation(DroppyAnimation.notchState, value: batteryManager.batteryLevel)
        .animation(DroppyAnimation.notchState, value: batteryManager.isCharging)
    }
}

#Preview {
    ZStack {
        Color.black
        BatteryHUDView(
            batteryManager: BatteryManager.shared,
            hudWidth: 300
        )
    }
    .frame(width: 350, height: 60)
}
