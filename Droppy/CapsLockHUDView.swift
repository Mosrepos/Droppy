//
//  CapsLockHUDView.swift
//  Droppy
//
//  Created by Droppy on 09/01/2026.
//  Beautiful Caps Lock HUD matching BatteryHUDView style exactly
//

import SwiftUI

/// Compact Caps Lock HUD that sits inside the notch
/// Matches BatteryHUDView layout exactly: icon on left wing, ON/OFF on right wing
struct CapsLockHUDView: View {
    @ObservedObject var capsLockManager: CapsLockManager
    let hudWidth: CGFloat     // Total HUD width
    var targetScreen: NSScreen? = nil  // Target screen for multi-monitor support
    
    /// Centralized layout calculator - Single Source of Truth
    private var layout: HUDLayoutCalculator {
        HUDLayoutCalculator(screen: targetScreen ?? NSScreen.main ?? NSScreen.screens.first!)
    }
    
    /// Accent color based on Caps Lock state (matches battery green/white scheme)
    private var accentColor: Color {
        capsLockManager.isCapsLockOn ? .green : .white
    }
    
    /// Caps Lock icon - use filled variant when ON
    private var capsLockIcon: String {
        capsLockManager.isCapsLockOn ? "capslock.fill" : "capslock"
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            if layout.isDynamicIslandMode {
                // DYNAMIC ISLAND: Icon on left edge, On/Off on right edge
                let iconSize = layout.iconSize
                let symmetricPadding = layout.symmetricPadding(for: iconSize)
                
                HStack {
                    // Caps Lock icon - .leading alignment within frame
                    Image(systemName: capsLockIcon)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(layout.adjustedColor(accentColor))
                        .symbolEffect(.bounce.up, value: capsLockManager.isCapsLockOn)
                        .contentTransition(.symbolEffect(.replace.byLayer.downUp))
                        .frame(width: 20, height: iconSize, alignment: .leading)
                    
                    Spacer()
                    
                    // On/Off text
                    Text(capsLockManager.isCapsLockOn ? "On" : "Off")
                        .font(.system(size: layout.labelFontSize, weight: .semibold))
                        .foregroundStyle(layout.adjustedColor(accentColor))
                        .contentTransition(.interpolate)
                }
                .padding(.horizontal, symmetricPadding)
                .frame(height: layout.notchHeight)
            } else {
                // NOTCH MODE: Two wings separated by the notch space
                let iconSize = layout.iconSize
                let symmetricPadding = layout.symmetricPadding(for: iconSize)
                let wingWidth = layout.wingWidth(for: hudWidth)
                
                HStack(spacing: 0) {
                    // Left wing: Caps Lock icon near left edge
                    HStack {
                        Image(systemName: capsLockIcon)
                            .font(.system(size: iconSize, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .symbolEffect(.bounce.up, value: capsLockManager.isCapsLockOn)
                            .contentTransition(.symbolEffect(.replace.byLayer.downUp))
                            .frame(width: iconSize, height: iconSize, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, symmetricPadding)
                    .frame(width: wingWidth)
                    
                    // Camera notch area (spacer)
                    Spacer()
                        .frame(width: layout.notchWidth)
                    
                    // Right wing: ON/OFF near right edge
                    HStack {
                        Spacer(minLength: 0)
                        Text(capsLockManager.isCapsLockOn ? "On" : "Off")
                            .font(.system(size: layout.labelFontSize, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .contentTransition(.interpolate)
                            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: capsLockManager.isCapsLockOn)
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
        CapsLockHUDView(
            capsLockManager: CapsLockManager.shared,
            hudWidth: 300
        )
    }
    .frame(width: 350, height: 60)
}
