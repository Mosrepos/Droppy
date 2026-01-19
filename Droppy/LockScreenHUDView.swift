//
//  LockScreenHUDView.swift
//  Droppy
//
//  Created by Droppy on 13/01/2026.
//  Lock/Unlock HUD - iPhone-style unlock animation
//

import SwiftUI

/// Compact Lock Screen HUD that sits inside the notch
/// Shows just the lock icon with smooth unlock animation like iPhone
struct LockScreenHUDView: View {
    @ObservedObject var lockScreenManager: LockScreenManager
    let hudWidth: CGFloat     // Total HUD width
    var targetScreen: NSScreen? = nil  // Target screen for multi-monitor support
    
    /// Centralized layout calculator - Single Source of Truth
    private var layout: HUDLayoutCalculator {
        HUDLayoutCalculator(screen: targetScreen ?? NSScreen.main ?? NSScreen.screens.first!)
    }
    
    // Animation states
    @State private var showUnlockAnim = false
    @State private var lockScale: CGFloat = 1.0
    @State private var lockOpacity: Double = 1.0
    
    /// Whether we're unlocked
    private var isUnlocked: Bool {
        lockScreenManager.lastEvent == .unlocked
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            if layout.isDynamicIslandMode {
                // DYNAMIC ISLAND: Centered icon with animation
                lockIconView
                    .frame(maxWidth: .infinity)
                    .frame(height: layout.notchHeight)
            } else {
                // NOTCH MODE: Icon on left wing only
                let wingWidth = layout.wingWidth(for: hudWidth)
                
                HStack(spacing: 0) {
                    // Left wing: Lock icon near left edge
                    HStack {
                        lockIconView
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 8)
                    .frame(width: wingWidth)
                    
                    // Camera notch area (spacer)
                    Spacer()
                        .frame(width: layout.notchWidth)
                    
                    // Right wing: Empty
                    Spacer()
                        .frame(width: wingWidth)
                }
                .frame(height: layout.notchHeight)
            }
        }
        .onAppear {
            if isUnlocked {
                triggerUnlockAnimation()
            }
        }
        .onChange(of: lockScreenManager.lastEvent) { _, _ in
            if isUnlocked {
                triggerUnlockAnimation()
            }
        }
    }
    
    /// The animated lock icon view with realistic unlock physics
    private var lockIconView: some View {
        let iconSize = layout.iconSize
        
        return ZStack {
            // Unlocked state (lock.open.fill) - swoops in from above
            Image(systemName: "lock.open.fill")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .opacity(showUnlockAnim ? 1 : 0)
                .scaleEffect(showUnlockAnim ? 1.0 : 0.6)
                .offset(y: showUnlockAnim ? 0 : -4)
                .rotationEffect(.degrees(showUnlockAnim ? 0 : -15))
            
            // Locked state (lock.fill) - shrinks and fades as it "unlocks"
            Image(systemName: "lock.fill")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .opacity(showUnlockAnim ? 0 : lockOpacity)
                .scaleEffect(showUnlockAnim ? 0.7 : lockScale)
                .rotationEffect(.degrees(showUnlockAnim ? 10 : 0))
        }
        .frame(width: iconSize + 2, height: iconSize + 2)
    }
    
    /// Trigger the smooth multi-phase unlock animation
    private func triggerUnlockAnimation() {
        // Reset all states
        showUnlockAnim = false
        lockScale = 1.0
        lockOpacity = 1.0
        
        // Phase 1: Quick "trying to unlock" shake (subtle)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeInOut(duration: 0.08)) {
                lockScale = 1.05
            }
        }
        
        // Phase 2: Return and slight compress (like pressing)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
            withAnimation(.easeInOut(duration: 0.06)) {
                lockScale = 0.95
            }
        }
        
        // Phase 3: The unlock! Smooth spring transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.65, blendDuration: 0)) {
                showUnlockAnim = true
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black
        LockScreenHUDView(
            lockScreenManager: LockScreenManager.shared,
            hudWidth: 300
        )
    }
    .frame(width: 350, height: 60)
}
