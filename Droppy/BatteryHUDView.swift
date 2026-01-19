//
//  BatteryHUDView.swift
//  Droppy
//
//  Created by Droppy on 07/01/2026.
//  Beautiful battery HUD matching MediaHUDView style
//

import SwiftUI

/// Compact battery HUD that sits inside the notch
/// Matches MediaHUDView layout: icon on left wing, percentage on right wing
struct BatteryHUDView: View {
    @ObservedObject var batteryManager: BatteryManager
    let hudWidth: CGFloat     // Total HUD width
    var targetScreen: NSScreen? = nil  // Target screen for multi-monitor support
    
    /// Centralized layout calculator - Single Source of Truth
    private var layout: HUDLayoutCalculator {
        HUDLayoutCalculator(screen: targetScreen ?? NSScreen.main ?? NSScreen.screens.first!)
    }
    
    /// Accent color based on battery state
    private var accentColor: Color {
        if batteryManager.isCharging || batteryManager.isPluggedIn {
            return .green
        } else if batteryManager.isLowBattery {
            return .orange
        } else {
            return .white
        }
    }
    
    /// Dynamic battery icon based on level and charging state
    private var batteryIcon: String {
        if batteryManager.isCharging || batteryManager.isPluggedIn {
            return "battery.100.bolt"
        }
        let level = batteryManager.batteryLevel
        if level >= 75 {
            return "battery.100"
        } else if level >= 50 {
            return "battery.75"
        } else if level >= 25 {
            return "battery.50"
        } else {
            return "battery.25"
        }
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            if layout.isDynamicIslandMode {
                // DYNAMIC ISLAND: Icon on left edge, percentage on right edge
                let iconSize = layout.iconSize
                let symmetricPadding = layout.symmetricPadding(for: iconSize)
                
                HStack {
                    // Battery icon - .leading alignment within frame for edge alignment
                    Image(systemName: batteryIcon)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(layout.adjustedColor(accentColor))
                        .symbolEffect(.bounce, value: batteryManager.isCharging)
                        .contentTransition(.symbolEffect(.replace.byLayer))
                        .frame(width: 20, height: iconSize, alignment: .leading)
                    
                    Spacer()
                    
                    // Percentage
                    Text("\(batteryManager.batteryLevel)%")
                        .font(.system(size: layout.labelFontSize, weight: .semibold))
                        .foregroundStyle(layout.adjustedColor(accentColor))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(batteryManager.batteryLevel)))
                }
                .padding(.horizontal, symmetricPadding)
                .frame(height: layout.notchHeight)
            } else {
                // NOTCH MODE: Two wings separated by the notch space
                let iconSize = layout.iconSize
                let symmetricPadding = layout.symmetricPadding(for: iconSize)
                let wingWidth = layout.wingWidth(for: hudWidth)
                
                HStack(spacing: 0) {
                    // Left wing: Battery icon near left edge
                    HStack {
                        Image(systemName: batteryIcon)
                            .font(.system(size: iconSize, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .symbolEffect(.bounce, value: batteryManager.isCharging)
                            .contentTransition(.symbolEffect(.replace.byLayer))
                            .frame(width: iconSize, height: iconSize, alignment: .leading)
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
                            .font(.system(size: layout.labelFontSize, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(batteryManager.batteryLevel)))
                            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: batteryManager.batteryLevel)
                    }
                    .padding(.trailing, symmetricPadding)
                    .frame(width: wingWidth)
                }
                .frame(height: layout.notchHeight)
            }
        }
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
