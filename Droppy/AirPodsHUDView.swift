//
//  AirPodsHUDView.swift
//  Droppy
//
//  Created by Droppy on 11/01/2026.
//  AirPods connection animation HUD - mimics iPhone's AirPods popup
//  Layout matches MediaHUDView for consistent positioning
//

import SwiftUI

/// Model representing connected AirPods
struct ConnectedAirPods: Equatable {
    let name: String
    let type: AirPodsType
    let batteryLevel: Int // Combined battery percentage (0-100)
    let leftBattery: Int?
    let rightBattery: Int?
    let caseBattery: Int?
    
    enum AirPodsType: String, CaseIterable {
        case standard = "airpods"
        case pro = "airpodspro"
        case max = "airpodsmax"
        case gen3 = "airpods.gen3"
        
        /// SF Symbol name for this AirPods type
        var symbolName: String {
            return rawValue
        }
        
        /// Display name for this AirPods type
        var displayName: String {
            switch self {
            case .standard: return "AirPods"
            case .pro: return "AirPods Pro"
            case .max: return "AirPods Max"
            case .gen3: return "AirPods 3"
            }
        }
    }
}

/// AirPods connection HUD mimicking iPhone's popup animation
/// - Slow, elegant 3D Y-axis rotation
/// - Scale-up entrance with spring bounce
/// - Battery levels fade in after rotation starts
struct AirPodsHUDView: View {
    let airPods: ConnectedAirPods
    let hudWidth: CGFloat
    var targetScreen: NSScreen? = nil  // Target screen for multi-monitor support
    
    /// Centralized layout calculator - Single Source of Truth
    private var layout: HUDLayoutCalculator {
        HUDLayoutCalculator(screen: targetScreen ?? NSScreen.main ?? NSScreen.screens.first!)
    }
    
    // Animation states - iPhone-style timing
    @State private var rotationAngle: Double = 0
    @State private var iconScale: CGFloat = 0.4
    @State private var iconOpacity: CGFloat = 0
    @State private var batteryOpacity: CGFloat = 0
    @State private var batteryScale: CGFloat = 0.8
    @State private var ringProgress: CGFloat = 0
    
    /// Battery ring color based on level
    private var batteryColor: Color {
        if airPods.batteryLevel >= 50 {
            return .green
        } else if airPods.batteryLevel >= 20 {
            return .orange
        } else {
            return .red
        }
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            if layout.isDynamicIslandMode {
                dynamicIslandContent
            } else {
                notchModeContent
            }
        }
        .onAppear {
            startIPhoneStyleAnimation()
        }
    }
    
    // MARK: - Dynamic Island Layout
    
    private var dynamicIslandContent: some View {
        let iconSize = layout.iconSize
        let symmetricPadding = layout.symmetricPadding(for: iconSize)
        
        return ZStack {
            // Device name - centered
            VStack {
                Spacer(minLength: 0)
                Text("Connected")
                    .font(.system(size: layout.labelFontSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(height: 16)
                    .opacity(batteryOpacity)
                    .scaleEffect(batteryScale)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 40)
            
            // Icon (left edge) and Battery ring (right edge)
            HStack {
                airPodsIconView(size: iconSize)
                Spacer()
                batteryRingView(size: 20)
            }
            .padding(.horizontal, symmetricPadding)
        }
        .frame(height: layout.notchHeight)
    }
    
    // MARK: - Notch Mode Layout
    
    private var notchModeContent: some View {
        let iconSize = layout.iconSize
        let symmetricPadding = layout.symmetricPadding(for: iconSize)
        let wingWidth = layout.wingWidth(for: hudWidth)
        
        return HStack(spacing: 0) {
            // Left wing: AirPods icon near left edge
            HStack {
                airPodsIconView(size: iconSize)
                    .frame(width: iconSize, height: iconSize, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.leading, symmetricPadding)
            .frame(width: wingWidth)
            
            // Camera notch area (spacer)
            Spacer()
                .frame(width: layout.notchWidth)
            
            // Right wing: Battery ring near right edge
            HStack {
                Spacer(minLength: 0)
                batteryRingView(size: iconSize)
            }
            .padding(.trailing, symmetricPadding)
            .frame(width: wingWidth)
        }
        .frame(height: layout.notchHeight)
    }
    
    // MARK: - AirPods Icon (iPhone-style 3D rotation)
    
    @ViewBuilder
    private func airPodsIconView(size: CGFloat) -> some View {
        Image(systemName: airPods.type.symbolName)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(.white)
            // iPhone-style slow 3D rotation around Y-axis
            .rotation3DEffect(
                .degrees(rotationAngle),
                axis: (x: 0, y: 1, z: 0),
                anchor: .center,
                anchorZ: 0,
                perspective: 0.3
            )
            .frame(width: size, height: size)
            // Scale and opacity entrance
            .scaleEffect(iconScale)
            .opacity(iconOpacity)
    }
    
    // MARK: - Battery Ring
    
    @ViewBuilder
    private func batteryRingView(size: CGFloat) -> some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 3)
            
            // Progress ring
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    batteryColor,
                    style: StrokeStyle(
                        lineWidth: 3,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
            
            // Battery percentage text
            Text("\(airPods.batteryLevel)")
                .font(.system(size: size > 24 ? 11 : 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .frame(width: size, height: size)
        .opacity(batteryOpacity)
        .scaleEffect(batteryScale)
    }
    
    // MARK: - iPhone-Style Animation Sequence
    
    private func startIPhoneStyleAnimation() {
        // === PHASE 1: Icon appears with spring ===
        withAnimation(.spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0)) {
            iconScale = 1.0
            iconOpacity = 1.0
        }
        
        // === PHASE 2: Start slow 3D rotation ===
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 3.5)) {
                rotationAngle = 360
            }
            
            // After full rotation, do a gentle settle oscillation
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                withAnimation(
                    .easeInOut(duration: 2.0)
                    .repeatForever(autoreverses: true)
                ) {
                    rotationAngle = 380
                }
            }
        }
        
        // === PHASE 3: Battery info fades in ===
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeOut(duration: 0.4)) {
                batteryOpacity = 1.0
                batteryScale = 1.0
            }
        }
        
        // === PHASE 4: Battery ring fills ===
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeOut(duration: 0.8)) {
                ringProgress = CGFloat(airPods.batteryLevel) / 100
            }
        }
    }
}

// MARK: - Preview

#Preview("AirPods HUD - Dynamic Island") {
    ZStack {
        Color.black
        AirPodsHUDView(
            airPods: ConnectedAirPods(
                name: "Jordy's AirPods Pro",
                type: .pro,
                batteryLevel: 85,
                leftBattery: 85,
                rightBattery: 90,
                caseBattery: 75
            ),
            hudWidth: 260
        )
    }
    .frame(width: 300, height: 60)
}

#Preview("AirPods HUD - Notch Mode") {
    ZStack {
        Color.black
        AirPodsHUDView(
            airPods: ConnectedAirPods(
                name: "Jordy's AirPods Pro",
                type: .pro,
                batteryLevel: 45,
                leftBattery: 45,
                rightBattery: 50,
                caseBattery: nil
            ),
            hudWidth: 280
        )
    }
    .frame(width: 320, height: 60)
}

#Preview("Low Battery") {
    ZStack {
        Color.black
        AirPodsHUDView(
            airPods: ConnectedAirPods(
                name: "AirPods",
                type: .standard,
                batteryLevel: 15,
                leftBattery: 10,
                rightBattery: 20,
                caseBattery: nil
            ),
            hudWidth: 280
        )
    }
    .frame(width: 320, height: 60)
}
