//
//  DNDHUDView.swift
//  Droppy
//
//  Created by Droppy on 17/01/2026.
//  Do Not Disturb / Focus Mode HUD
//

import SwiftUI

/// HUD view for Do Not Disturb / Focus Mode state
/// Shows a moon icon with purple accent when Focus is active
struct DNDHUDView: View {
    @ObservedObject var dndManager: DNDManager
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let hudWidth: CGFloat
    var targetScreen: NSScreen? = nil
    
    private var wingWidth: CGFloat {
        (hudWidth - notchWidth) / 2
    }
    
    // Purple accent for Focus mode (matches iOS)
    private var accentColor: Color {
        dndManager.isDNDActive ? Color(red: 0.55, green: 0.35, blue: 0.95) : .white
    }
    
    private var iconName: String {
        dndManager.isDNDActive ? "moon.fill" : "moon"
    }
    
    private var statusText: String {
        dndManager.isDNDActive ? "Focus" : "Off"
    }
    
    // Dynamic Island mode detection (screen-aware)
    private var isDynamicIslandMode: Bool {
        let screen = targetScreen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = screen else { return true }
        let hasNotch = screen.safeAreaInsets.top > 0
        let forceTest = UserDefaults.standard.bool(forKey: "forceDynamicIslandTest")
        if !screen.isBuiltIn { return true }
        let useDynamicIsland = UserDefaults.standard.object(forKey: "useDynamicIslandStyle") as? Bool ?? true
        return (!hasNotch || forceTest) && useDynamicIsland
    }
    
    private var isTransparentDI: Bool {
        isDynamicIslandMode && UserDefaults.standard.bool(forKey: "useDynamicIslandTransparent")
    }
    
    private var displayColor: Color {
        isTransparentDI ? .white : accentColor
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            if isDynamicIslandMode {
                // DYNAMIC ISLAND: Compact horizontal layout
                HStack(spacing: 12) {
                    Image(systemName: iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(displayColor)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 20, height: 20)
                    
                    Text(statusText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(displayColor)
                        .contentTransition(.interpolate)
                }
                .padding(.horizontal, 14)
                .frame(height: notchHeight)
            } else {
                // NOTCH MODE: Wings layout
                HStack(spacing: 0) {
                    // Left wing: Icon
                    HStack {
                        Image(systemName: iconName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 26, height: 26)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 16)
                    .frame(width: wingWidth)
                    
                    // Camera notch area
                    Spacer()
                        .frame(width: notchWidth)
                    
                    // Right wing: Status text
                    HStack {
                        Spacer(minLength: 0)
                        Text(statusText)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .contentTransition(.interpolate)
                    }
                    .padding(.trailing, 16)
                    .frame(width: wingWidth)
                }
                .frame(height: notchHeight)
            }
        }
    }
}

// MARK: - Preview

#Preview("DND HUD") {
    ZStack {
        Color.gray.opacity(0.3)
        
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.black)
            .frame(width: 280, height: 40)
            .overlay {
                DNDHUDView(
                    dndManager: DNDManager.shared,
                    notchWidth: 180,
                    notchHeight: 37,
                    hudWidth: 280
                )
            }
    }
    .frame(width: 400, height: 100)
}
