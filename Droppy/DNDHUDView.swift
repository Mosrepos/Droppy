//
//  DNDHUDView.swift
//  Droppy
//
//  Created by Droppy on 17/01/2026.
//  Focus/DND HUD matching CapsLockHUDView style exactly
//

import SwiftUI

/// Compact Focus/DND HUD that sits inside the notch
/// Matches CapsLockHUDView layout exactly: icon on left wing, ON/OFF on right wing
struct DNDHUDView: View {
    @ObservedObject var dndManager: DNDManager
    let hudWidth: CGFloat     // Total HUD width
    var targetScreen: NSScreen? = nil  // Target screen for multi-monitor support
    
    /// Centralized layout calculator - Single Source of Truth
    private var layout: HUDLayoutCalculator {
        HUDLayoutCalculator(screen: targetScreen ?? NSScreen.main ?? NSScreen.screens.first!)
    }
    
    /// Accent color: purple when Focus ON, white when OFF
    private var accentColor: Color {
        dndManager.isDNDActive ? Color(red: 0.55, green: 0.35, blue: 0.95) : .white
    }
    
    /// Focus icon - use filled variant when ON
    private var focusIcon: String {
        dndManager.isDNDActive ? "moon.fill" : "moon"
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            if layout.isDynamicIslandMode {
                // DYNAMIC ISLAND: Icon on left edge, On/Off on right edge
                let iconSize = layout.iconSize
                let symmetricPadding = layout.symmetricPadding(for: iconSize)
                
                HStack {
                    // Focus icon - .leading alignment within frame
                    Image(systemName: focusIcon)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(layout.adjustedColor(accentColor))
                        .symbolEffect(.bounce.up, value: dndManager.isDNDActive)
                        .contentTransition(.symbolEffect(.replace.byLayer.downUp))
                        .frame(width: 20, height: iconSize, alignment: .leading)
                    
                    Spacer()
                    
                    // On/Off text
                    Text(dndManager.isDNDActive ? "On" : "Off")
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
                    // Left wing: Focus icon near left edge
                    HStack {
                        Image(systemName: focusIcon)
                            .font(.system(size: iconSize, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .symbolEffect(.bounce.up, value: dndManager.isDNDActive)
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
                        Text(dndManager.isDNDActive ? "On" : "Off")
                            .font(.system(size: layout.labelFontSize, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .contentTransition(.interpolate)
                            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: dndManager.isDNDActive)
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
        DNDHUDView(
            dndManager: DNDManager.shared,
            hudWidth: 300
        )
    }
    .frame(width: 350, height: 60)
}
