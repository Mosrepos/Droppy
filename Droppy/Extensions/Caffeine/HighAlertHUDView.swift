//
//  HighAlertHUDView.swift
//  Droppy
//
//  High Alert HUD matching CapsLockHUDView style exactly
//  Shows eyes icon on left wing, timer/Active/Inactive on right wing
//

import SwiftUI

/// Compact High Alert HUD that sits inside the notch
/// Matches CapsLockHUDView layout: icon on left wing, timer on right wing when active
struct HighAlertHUDView: View {
    let isActive: Bool
    let hudWidth: CGFloat     // Total HUD width
    var targetScreen: NSScreen? = nil  // Target screen for multi-monitor support
    
    // Access CaffeineManager for timer display
    private var caffeineManager: CaffeineManager { CaffeineManager.shared }
    
    /// Centralized layout calculator - Single Source of Truth
    private var layout: HUDLayoutCalculator {
        HUDLayoutCalculator(screen: targetScreen ?? NSScreen.main ?? NSScreen.screens.first)
    }
    
    /// Accent color based on High Alert state
    private var accentColor: Color {
        isActive ? .orange : .white
    }
    
    /// High Alert icon - use filled variant when active
    private var alertIcon: String {
        isActive ? "eyes" : "eyes"  // Same icon, color changes
    }
    
    /// Display text - shows timer when active, "Inactive" when not
    private var statusText: String {
        if isActive {
            // Show timer countdown or ∞ for indefinite
            return caffeineManager.formattedRemaining
        } else {
            return "Inactive"
        }
    }
    
    /// Font size for status text - larger for ∞ symbol
    private var statusFontSize: CGFloat {
        if isActive && caffeineManager.formattedRemaining == "∞" {
            return layout.labelFontSize + 6  // Larger for infinity symbol
        }
        return layout.labelFontSize
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            if layout.isDynamicIslandMode {
                // DYNAMIC ISLAND: Icon on left edge, timer/status on right edge
                let iconSize = layout.iconSize
                let symmetricPadding = layout.symmetricPadding(for: iconSize)
                
                HStack {
                    // High Alert icon - .leading alignment within frame
                    Image(systemName: alertIcon)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(layout.adjustedColor(accentColor))
                        .symbolEffect(.bounce.up, value: isActive)
                        .frame(width: 20, height: iconSize, alignment: .leading)
                    
                    Spacer()
                    
                    // Timer/status text
                    Text(statusText)
                        .font(.system(size: statusFontSize, weight: .semibold, design: isActive ? .monospaced : .default))
                        .foregroundStyle(layout.adjustedColor(accentColor))
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, symmetricPadding)
                .frame(height: layout.notchHeight)
            } else {
                // NOTCH MODE: Two wings separated by the notch space
                let iconSize = layout.iconSize
                let symmetricPadding = layout.symmetricPadding(for: iconSize)
                let wingWidth = layout.wingWidth(for: hudWidth)
                
                HStack(spacing: 0) {
                    // Left wing: High Alert icon near left edge
                    HStack {
                        Image(systemName: alertIcon)
                            .font(.system(size: iconSize, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .symbolEffect(.bounce.up, value: isActive)
                            .frame(width: iconSize, height: iconSize, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, symmetricPadding)
                    .frame(width: wingWidth)
                    
                    // Camera notch area (spacer)
                    Spacer()
                        .frame(width: layout.notchWidth)
                    
                    // Right wing: Timer/status near right edge
                    HStack {
                        Spacer(minLength: 0)
                        Text(statusText)
                            .font(.system(size: statusFontSize, weight: .semibold, design: isActive ? .monospaced : .default))
                            .foregroundStyle(accentColor)
                            .contentTransition(.numericText())
                            .animation(DroppyAnimation.notchState, value: statusText)
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
        HighAlertHUDView(
            isActive: true,
            hudWidth: 300
        )
    }
    .frame(width: 350, height: 60)
}
